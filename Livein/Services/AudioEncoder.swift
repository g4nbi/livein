import AudioToolbox
import CoreMedia

protocol AudioEncoderDelegate: AnyObject {
    func audioEncoder(_ encoder: AudioEncoder, didOutput data: Data, pts: CMTime)
}

final class AudioEncoder {
    weak var delegate: AudioEncoderDelegate?

    private var converter: AudioConverterRef?
    private var outputFormat = AudioStreamBasicDescription()
    private var inputFormat = AudioStreamBasicDescription()
    private var inputQueue: [CMSampleBuffer] = []
    private let lock = NSLock()

    func configure(from sampleBuffer: CMSampleBuffer) {
        guard converter == nil,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }

        guard let inASBD = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return }
        inputFormat = inASBD.pointee

        outputFormat = AudioStreamBasicDescription(
            mSampleRate: inputFormat.mSampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: inputFormat.mChannelsPerFrame,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var conv: AudioConverterRef?
        AudioConverterNew(&inputFormat, &outputFormat, &conv)
        converter = conv
    }

    func encode(sampleBuffer: CMSampleBuffer) {
        guard let converter else {
            configure(from: sampleBuffer)
            return
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        var lengthAtOffset = 0
        var dataLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &dataLength, dataPointerOut: &dataPointer)
        guard let dataPointer else { return }

        let outputBufferSize = 2048
        var outputBuffer = [UInt8](repeating: 0, count: outputBufferSize)
        var outputSize = UInt32(outputBufferSize)
        var numberOfPackets: UInt32 = 1

        var outputPacketDescription = AudioStreamPacketDescription()
        let inputData = UnsafeMutableRawPointer(dataPointer)

        var ioData = AudioBufferList()
        ioData.mNumberBuffers = 1
        ioData.mBuffers.mNumberChannels = outputFormat.mChannelsPerFrame
        ioData.mBuffers.mDataByteSize = outputSize

        outputBuffer.withUnsafeMutableBytes { ptr in
            ioData.mBuffers.mData = ptr.baseAddress

            var inputDataSize = UInt32(dataLength)
            var inputPacketCount = inputDataSize / (inputFormat.mBytesPerFrame > 0 ? inputFormat.mBytesPerFrame : 1)
            if inputPacketCount == 0 { inputPacketCount = UInt32(dataLength) / inputFormat.mChannelsPerFrame / 2 }

            let userData = UnsafeMutableRawPointer(mutating: inputData)

            AudioConverterFillComplexBuffer(
                converter,
                { _, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData in
                    guard let inUserData else { return kAudio_ParamError }
                    let sizeAvailable = ioNumberDataPackets.pointee * 2
                    ioData.pointee.mBuffers.mData = inUserData
                    ioData.pointee.mBuffers.mDataByteSize = UInt32(sizeAvailable)
                    return noErr
                },
                userData,
                &numberOfPackets,
                &ioData,
                &outputPacketDescription
            )

            outputSize = ioData.mBuffers.mDataByteSize
        }

        if outputSize > 0 {
            let outputData = Data(outputBuffer.prefix(Int(outputSize)))
            delegate?.audioEncoder(self, didOutput: outputData, pts: pts)
        }
    }

    func invalidate() {
        if let conv = converter {
            AudioConverterDispose(conv)
            converter = nil
        }
    }
}
