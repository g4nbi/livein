import Foundation
import Network
import CoreMedia
import VideoToolbox

// MARK: - RTMP Chunk Type Definitions

private enum RTMPMessageType: UInt8 {
    case setChunkSize    = 0x01
    case abort           = 0x02
    case acknowledgement = 0x03
    case userControl     = 0x04
    case windowAckSize   = 0x05
    case setPeerBandwidth = 0x06
    case audio           = 0x08
    case video           = 0x09
    case dataAMF0        = 0x12
    case commandAMF0     = 0x14
}

private struct RTMPChunk {
    var chunkStreamID: UInt8
    var timestamp: UInt32
    var messageLength: UInt32
    var messageType: RTMPMessageType
    var messageStreamID: UInt32
    var payload: Data
}

// MARK: - RTMPStreamService

protocol RTMPStreamServiceDelegate: AnyObject {
    func streamService(_ service: RTMPStreamService, didChangeStatus status: StreamStatus)
    func streamService(_ service: RTMPStreamService, didUpdateStats stats: StreamStats)
}

final class RTMPStreamService: NSObject {
    weak var delegate: RTMPStreamServiceDelegate?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.g4nbi.livein.rtmp", qos: .userInitiated)

    private var status: StreamStatus = .idle {
        didSet { DispatchQueue.main.async { self.delegate?.streamService(self, didChangeStatus: self.status) } }
    }

    private var stats = StreamStats()
    private var statsTimer: DispatchSourceTimer?
    private var startTime: Date?
    private var totalBytesSent: Int64 = 0
    private var bytesInInterval: Int64 = 0

    private var rtmpURL: String = ""
    private var streamKey: String = ""

    // Reconnect state
    private var shouldReconnect = false
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 8

    // RTMP handshake state
    private enum HandshakeState { case c0c1, c2, done }
    private var handshakeState: HandshakeState = .c0c1
    private var receiveBuffer = Data()
    private var chunkSize: UInt32 = 128
    private var windowAckSize: UInt32 = 2_500_000
    private var peerBandwidth: UInt32 = 2_500_000
    private var sequenceNumber: UInt32 = 0
    private var lastAckSent: UInt32 = 0
    private var videoSequence: Int = 0
    private var audioSequence: Int = 0
    private var streamID: UInt32 = 1
    private var isPublishing = false

    // MARK: - Public API

    func connect(rtmpsURL: String, streamKey: String, autoReconnect: Bool) {
        self.rtmpURL = rtmpsURL
        self.streamKey = streamKey
        self.shouldReconnect = autoReconnect
        self.reconnectAttempt = 0
        establishConnection()
    }

    func disconnect() {
        shouldReconnect = false
        stopStatsTimer()
        queue.async { [weak self] in
            self?.sendCloseStream()
            self?.connection?.cancel()
            self?.connection = nil
            self?.isPublishing = false
            self?.handshakeState = .c0c1
            self?.receiveBuffer.removeAll()
        }
        status = .idle
        stats = StreamStats()
    }

    func sendVideoBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isPublishing else { return }
        guard let dataBuffer = sampleBuffer.dataBuffer else { return }

        var data = Data()
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr,
              let dataPointer else { return }

        data.append(contentsOf: UnsafeRawBufferPointer(start: dataPointer, count: totalLength))

        let isKeyFrame = sampleBuffer.isKeyFrame
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        let timestamp = UInt32(CMTimeGetSeconds(pts) * 1000)

        var videoTag = Data()
        // Frame type + codec (H264)
        let frameTypeByte: UInt8 = isKeyFrame ? 0x17 : 0x27
        videoTag.append(frameTypeByte)
        // AVC NALU type
        videoTag.append(0x01)
        // Composition time (cts)
        let cts = dts == .invalid ? 0 : Int32((CMTimeGetSeconds(pts) - CMTimeGetSeconds(dts)) * 1000)
        videoTag.append(UInt8((cts >> 16) & 0xFF))
        videoTag.append(UInt8((cts >> 8) & 0xFF))
        videoTag.append(UInt8(cts & 0xFF))
        videoTag.append(contentsOf: data)

        if isKeyFrame, let sps = sampleBuffer.sps, let pps = sampleBuffer.pps {
            sendAVCDecoder(sps: sps, pps: pps, timestamp: timestamp)
        }

        sendRTMPChunk(chunkStreamID: 6, timestamp: timestamp,
                      messageType: .video, messageStreamID: streamID,
                      payload: videoTag)
    }

    func sendAudioData(_ data: Data, pts: CMTime) {
        guard isPublishing else { return }
        let timestamp = UInt32(CMTimeGetSeconds(pts) * 1000)

        var audioTag = Data()
        // AAC, 44.1kHz, 16-bit stereo (or match actual)
        audioTag.append(0xAF) // Sound format=AAC, 44.1kHz, 16bit, stereo
        audioTag.append(0x01) // AAC raw
        audioTag.append(contentsOf: data)

        sendRTMPChunk(chunkStreamID: 4, timestamp: timestamp,
                      messageType: .audio, messageStreamID: streamID,
                      payload: audioTag)
    }

    // MARK: - Connection

    private func establishConnection() {
        status = reconnectAttempt > 0 ? .reconnecting : .connecting

        guard let (host, port, app) = parseRTMPSURL(rtmpURL) else {
            status = .error("URL tidak valid: \(rtmpURL)")
            return
        }

        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = 15
        tcpOptions.enableKeepalive = true
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 443)
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn
        self.handshakeState = .c0c1
        self.receiveBuffer.removeAll()
        self.isPublishing = false

        conn.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, app: app)
        }
        conn.start(queue: queue)
        receiveData()
    }

    private func handleConnectionState(_ state: NWConnection.State, app: String) {
        switch state {
        case .ready:
            sendHandshakeC0C1()
        case .failed(let error):
            handleDisconnect(reason: error.localizedDescription)
        case .cancelled:
            if shouldReconnect {
                handleDisconnect(reason: "Connection cancelled")
            }
        default:
            break
        }
    }

    private func handleDisconnect(reason: String) {
        isPublishing = false
        stopStatsTimer()

        guard shouldReconnect, reconnectAttempt < maxReconnectAttempts else {
            status = .error(reason)
            return
        }

        let delay = min(pow(2.0, Double(reconnectAttempt)), 60.0)
        reconnectAttempt += 1
        status = .reconnecting

        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.establishConnection()
        }
    }

    // MARK: - Receive

    private func receiveData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.receiveBuffer.append(data) }
            self.processReceiveBuffer()
            if !isComplete && error == nil { self.receiveData() }
        }
    }

    private func processReceiveBuffer() {
        switch handshakeState {
        case .c0c1:
            break
        case .c2:
            // S0 + S1 + S2 = 1 + 1536 + 1536 = 3073 bytes
            if receiveBuffer.count >= 3073 {
                let s1 = receiveBuffer.subdata(in: 1..<1537)
                receiveBuffer.removeFirst(3073)
                sendHandshakeC2(s1: s1)
                handshakeState = .done
                sendConnect()
            }
        case .done:
            processRTMPMessages()
        }
    }

    private func processRTMPMessages() {
        while receiveBuffer.count > 0 {
            guard let (consumed, _) = parseChunk(from: receiveBuffer) else { break }
            receiveBuffer.removeFirst(consumed)
        }
    }

    private func parseChunk(from data: Data) -> (consumed: Int, chunk: RTMPChunk?)? {
        guard !data.isEmpty else { return nil }
        let firstByte = data[0]
        let chunkStreamID = Int(firstByte & 0x3F)
        let headerType = (firstByte >> 6) & 0x03

        var offset = 1
        let headerSize: Int
        switch headerType {
        case 0: headerSize = 11
        case 1: headerSize = 7
        case 2: headerSize = 3
        default: return (1, nil)
        }

        guard data.count >= offset + headerSize else { return nil }

        var timestamp: UInt32 = 0
        if headerSize >= 3 {
            timestamp = UInt32(data[offset]) << 16 | UInt32(data[offset+1]) << 8 | UInt32(data[offset+2])
            offset += 3
        }

        var messageLength: UInt32 = 0
        var messageType: UInt8 = 0
        if headerSize >= 7 {
            messageLength = UInt32(data[offset]) << 16 | UInt32(data[offset+1]) << 8 | UInt32(data[offset+2])
            messageType = data[offset+3]
            offset += 4
        }

        var messageStreamID: UInt32 = 0
        if headerSize >= 11 {
            messageStreamID = UInt32(data[offset]) | UInt32(data[offset+1]) << 8 |
                              UInt32(data[offset+2]) << 16 | UInt32(data[offset+3]) << 24
            offset += 4
        }

        guard data.count >= offset + Int(messageLength) else { return nil }
        let payload = data.subdata(in: offset..<offset+Int(messageLength))

        if let type = RTMPMessageType(rawValue: messageType) {
            handleInboundMessage(type: type, payload: payload, chunkStreamID: chunkStreamID)
        }

        return (offset + Int(messageLength), nil)
    }

    private func handleInboundMessage(type: RTMPMessageType, payload: Data, chunkStreamID: Int) {
        switch type {
        case .windowAckSize:
            if payload.count >= 4 {
                windowAckSize = UInt32(payload[0]) << 24 | UInt32(payload[1]) << 16 |
                                UInt32(payload[2]) << 8 | UInt32(payload[3])
            }
        case .setPeerBandwidth:
            if payload.count >= 4 {
                peerBandwidth = UInt32(payload[0]) << 24 | UInt32(payload[1]) << 16 |
                                UInt32(payload[2]) << 8 | UInt32(payload[3])
            }
        case .commandAMF0:
            handleAMFCommand(payload)
        case .acknowledgement:
            break
        default:
            break
        }
    }

    private func handleAMFCommand(_ payload: Data) {
        // Parse AMF0 command name
        guard payload.count > 2 else { return }
        let nameLength = Int(UInt16(payload[1]) << 8 | UInt16(payload[2]))
        guard payload.count >= 3 + nameLength else { return }
        let commandName = String(data: payload.subdata(in: 3..<3+nameLength), encoding: .utf8) ?? ""

        switch commandName {
        case "_result":
            if !isPublishing {
                sendCreateStream()
            }
        case "onStatus":
            handleOnStatus(payload)
        default:
            break
        }
    }

    private func handleOnStatus(_ payload: Data) {
        // Check for NetStream.Publish.Start
        let payloadStr = String(data: payload, encoding: .utf8) ?? ""
        if payloadStr.contains("NetStream.Publish.Start") {
            isPublishing = true
            reconnectAttempt = 0
            status = .live
            startTime = Date()
            totalBytesSent = 0
            bytesInInterval = 0
            startStatsTimer()
            sendAACConfig()
        } else if payloadStr.contains("NetStream.Publish.BadName") ||
                  payloadStr.contains("NetConnection.Connect.Rejected") {
            status = .error("Stream key atau URL tidak valid")
            shouldReconnect = false
        }
    }

    // MARK: - RTMP Send Helpers

    private func sendHandshakeC0C1() {
        var c0c1 = Data(count: 1537)
        c0c1[0] = 0x03 // RTMP version 3
        // C1: timestamp (4 bytes) + zeros (4 bytes) + random (1528 bytes)
        let ts = UInt32(Date().timeIntervalSince1970 * 1000).bigEndian
        withUnsafeBytes(of: ts) { c0c1.replaceSubrange(1..<5, with: $0) }
        for i in 9..<1537 { c0c1[i] = UInt8.random(in: 0...255) }
        send(c0c1)
        handshakeState = .c2
    }

    private func sendHandshakeC2(s1: Data) {
        var c2 = Data(count: 1536)
        // Echo S1 back
        c2.replaceSubrange(0..<min(s1.count, 1536), with: s1.prefix(1536))
        send(c2)
    }

    private func sendConnect() {
        guard let (_, _, app) = parseRTMPSURL(rtmpURL) else { return }
        var payload = Data()
        payload.append(contentsOf: amfString("connect"))
        payload.append(contentsOf: amfNumber(1.0))
        // AMF Object
        payload.append(0x03) // object marker
        payload.append(contentsOf: amfObjectKey("app"))
        payload.append(contentsOf: amfString(app))
        payload.append(contentsOf: amfObjectKey("type"))
        payload.append(contentsOf: amfString("nonprivate"))
        payload.append(contentsOf: amfObjectKey("flashVer"))
        payload.append(contentsOf: amfString("FMLE/3.0 (compatible; FMSc/1.0)"))
        payload.append(contentsOf: amfObjectKey("tcUrl"))
        payload.append(contentsOf: amfString(rtmpURL))
        payload.append(contentsOf: [0x00, 0x00, 0x09]) // object end marker

        sendRTMPChunk(chunkStreamID: 3, timestamp: 0, messageType: .commandAMF0,
                      messageStreamID: 0, payload: payload)
    }

    private func sendCreateStream() {
        var payload = Data()
        payload.append(contentsOf: amfString("createStream"))
        payload.append(contentsOf: amfNumber(2.0))
        payload.append(0x05) // null
        sendRTMPChunk(chunkStreamID: 3, timestamp: 0, messageType: .commandAMF0,
                      messageStreamID: 0, payload: payload)
    }

    private func sendPublish() {
        var payload = Data()
        payload.append(contentsOf: amfString("publish"))
        payload.append(contentsOf: amfNumber(0.0))
        payload.append(0x05) // null
        payload.append(contentsOf: amfString(streamKey))
        payload.append(contentsOf: amfString("live"))
        sendRTMPChunk(chunkStreamID: 8, timestamp: 0, messageType: .commandAMF0,
                      messageStreamID: streamID, payload: payload)
    }

    private func sendCloseStream() {
        guard isPublishing else { return }
        var payload = Data()
        payload.append(contentsOf: amfString("closeStream"))
        payload.append(contentsOf: amfNumber(0.0))
        payload.append(0x05)
        sendRTMPChunk(chunkStreamID: 8, timestamp: 0, messageType: .commandAMF0,
                      messageStreamID: streamID, payload: payload)
    }

    private func sendAVCDecoder(sps: Data, pps: Data, timestamp: UInt32) {
        var tag = Data()
        tag.append(0x17) // key frame + H264
        tag.append(0x00) // AVC sequence header
        tag.append(0x00); tag.append(0x00); tag.append(0x00) // composition time 0
        // AVCDecoderConfigurationRecord
        tag.append(0x01) // configurationVersion
        tag.append(sps[1]); tag.append(sps[2]); tag.append(sps[3])
        tag.append(0xFF) // lengthSizeMinusOne = 3
        tag.append(0xE1) // numSequenceParameterSets = 1
        tag.append(UInt8(sps.count >> 8)); tag.append(UInt8(sps.count & 0xFF))
        tag.append(contentsOf: sps)
        tag.append(0x01) // numPictureParameterSets = 1
        tag.append(UInt8(pps.count >> 8)); tag.append(UInt8(pps.count & 0xFF))
        tag.append(contentsOf: pps)
        sendRTMPChunk(chunkStreamID: 6, timestamp: timestamp,
                      messageType: .video, messageStreamID: streamID, payload: tag)
    }

    private func sendAACConfig() {
        // AAC LC, 44100 Hz, 2 channels
        let aacConfig: [UInt8] = [0x12, 0x10]
        var tag = Data()
        tag.append(0xAF) // AAC, 44.1kHz, 16bit, stereo
        tag.append(0x00) // AAC sequence header
        tag.append(contentsOf: aacConfig)
        sendRTMPChunk(chunkStreamID: 4, timestamp: 0,
                      messageType: .audio, messageStreamID: streamID, payload: tag)
    }

    private func sendRTMPChunk(chunkStreamID: UInt8, timestamp: UInt32, messageType: RTMPMessageType,
                                messageStreamID: UInt32, payload: Data) {
        var data = Data()
        // Type 0 chunk header (basic header + full message header)
        data.append(chunkStreamID & 0x3F) // chunk type 0
        // Timestamp (3 bytes)
        let ts = min(timestamp, 0xFFFFFF)
        data.append(UInt8((ts >> 16) & 0xFF))
        data.append(UInt8((ts >> 8) & 0xFF))
        data.append(UInt8(ts & 0xFF))
        // Message length (3 bytes)
        let length = UInt32(payload.count)
        data.append(UInt8((length >> 16) & 0xFF))
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))
        // Message type (1 byte)
        data.append(messageType.rawValue)
        // Message stream ID (4 bytes, little endian)
        data.append(UInt8(messageStreamID & 0xFF))
        data.append(UInt8((messageStreamID >> 8) & 0xFF))
        data.append(UInt8((messageStreamID >> 16) & 0xFF))
        data.append(UInt8((messageStreamID >> 24) & 0xFF))

        // Payload split into chunks of chunkSize
        var offset = 0
        var firstChunk = true
        while offset < payload.count {
            if !firstChunk {
                // Type 3 continuation chunk header
                data.append(0xC0 | (chunkStreamID & 0x3F))
            }
            let end = min(offset + Int(chunkSize), payload.count)
            data.append(contentsOf: payload[offset..<end])
            offset = end
            firstChunk = false
        }

        send(data)

        let bytesSent = Int64(data.count)
        totalBytesSent += bytesSent
        bytesInInterval += bytesSent

        // Acknowledgement
        sequenceNumber += UInt32(data.count)
        if sequenceNumber - lastAckSent >= windowAckSize {
            sendAcknowledgement()
            lastAckSent = sequenceNumber
        }
    }

    private func sendAcknowledgement() {
        var data = Data()
        data.append(0x02) // chunk stream 2
        data.append(0x00); data.append(0x00); data.append(0x00) // timestamp
        data.append(0x00); data.append(0x00); data.append(0x04) // length
        data.append(RTMPMessageType.acknowledgement.rawValue)
        data.append(0x00); data.append(0x00); data.append(0x00); data.append(0x00)
        let seq = sequenceNumber.bigEndian
        withUnsafeBytes(of: seq) { data.append(contentsOf: $0) }
        send(data)
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Stats

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.updateStats() }
        timer.resume()
        statsTimer = timer
    }

    private func stopStatsTimer() {
        statsTimer?.cancel()
        statsTimer = nil
    }

    private func updateStats() {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let kbps = Double(bytesInInterval) * 8.0 / 1000.0
        bytesInInterval = 0

        var s = StreamStats()
        s.uploadKbps = kbps
        s.duration = elapsed
        s.totalBytesSent = totalBytesSent
        stats = s
        DispatchQueue.main.async { self.delegate?.streamService(self, didUpdateStats: s) }
    }

    // MARK: - URL Parsing

    private func parseRTMPSURL(_ url: String) -> (host: String, port: Int, app: String)? {
        // Expected: rtmps://host[:port]/app
        var str = url
        let isRTMPS = str.hasPrefix("rtmps://")
        str = str.replacingOccurrences(of: "rtmps://", with: "")
              .replacingOccurrences(of: "rtmp://", with: "")

        let parts = str.split(separator: "/", maxSplits: 1)
        guard parts.count >= 1 else { return nil }

        let hostPort = String(parts[0])
        let app = parts.count > 1 ? String(parts[1]) : "live2"

        let hostComponents = hostPort.split(separator: ":")
        let host = String(hostComponents[0])
        let port = hostComponents.count > 1 ? Int(hostComponents[1]) ?? (isRTMPS ? 443 : 1935) : (isRTMPS ? 443 : 1935)

        return (host, port, app)
    }

    // MARK: - AMF0 Helpers

    private func amfString(_ s: String) -> [UInt8] {
        let bytes = Array(s.utf8)
        return [0x02, UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
    }

    private func amfObjectKey(_ s: String) -> [UInt8] {
        let bytes = Array(s.utf8)
        return [UInt8(bytes.count >> 8), UInt8(bytes.count & 0xFF)] + bytes
    }

    private func amfNumber(_ n: Double) -> [UInt8] {
        var num = n.bitPattern.bigEndian
        return [0x00] + withUnsafeBytes(of: &num) { Array($0) }
    }

    func sendCreateStreamAfterResult() {
        sendCreateStream()
    }

    func startPublishing() {
        sendPublish()
    }
}

// MARK: - CMSampleBuffer Extensions

private extension CMSampleBuffer {
    var isKeyFrame: Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false)
        if let array = attachments as? [[CFString: Any]],
           let first = array.first,
           let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        return true
    }

    var sps: Data? {
        guard let description = CMSampleBufferGetFormatDescription(self),
              let paramSets = CMVideoFormatDescriptionGetH264ParameterSetAt(description, 0) else { return nil }
        return Data(bytes: paramSets.pointer, count: paramSets.size)
    }

    var pps: Data? {
        guard let description = CMSampleBufferGetFormatDescription(self),
              let paramSets = CMVideoFormatDescriptionGetH264ParameterSetAt(description, 1) else { return nil }
        return Data(bytes: paramSets.pointer, count: paramSets.size)
    }
}

private func CMVideoFormatDescriptionGetH264ParameterSetAt(_ description: CMFormatDescription, _ index: Int) -> (pointer: UnsafePointer<UInt8>, size: Int)? {
    var count = 0
    var nalUnitHeaderLength: Int32 = 0
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        description, parameterSetIndex: index,
        parameterSetPointerOut: nil,
        parameterSetSizeOut: nil,
        parameterSetCountOut: &count,
        nalUnitHeaderLengthOut: &nalUnitHeaderLength
    )
    guard count > index else { return nil }
    var pointer: UnsafePointer<UInt8>?
    var size = 0
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        description, parameterSetIndex: index,
        parameterSetPointerOut: &pointer,
        parameterSetSizeOut: &size,
        parameterSetCountOut: nil,
        nalUnitHeaderLengthOut: nil
    )
    guard let pointer else { return nil }
    return (pointer, size)
}
