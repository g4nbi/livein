import AVFoundation
import Combine

final class CameraService: NSObject {
    let session = AVCaptureSession()
    private(set) var currentPosition: AVCaptureDevice.Position = .back

    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOutput: AVCaptureAudioDataOutput?

    private let sessionQueue = DispatchQueue(label: "com.g4nbi.livein.camera", qos: .userInitiated)

    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onAudioSampleBuffer: ((CMSampleBuffer) -> Void)?

    var isMuted: Bool = false {
        didSet { updateAudioMute() }
    }

    // MARK: - Setup

    func requestPermissions() async -> Bool {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        var videoGranted = videoStatus == .authorized
        var audioGranted = audioStatus == .authorized

        if videoStatus == .notDetermined {
            videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        }
        if audioStatus == .notDetermined {
            audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        }
        return videoGranted && audioGranted
    }

    func configure(resolution: VideoResolution, frameRate: FrameRate) {
        sessionQueue.async { [weak self] in
            self?.configureOnQueue(resolution: resolution, frameRate: frameRate)
        }
    }

    private func configureOnQueue(resolution: VideoResolution, frameRate: FrameRate) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Preset
        let preset: AVCaptureSession.Preset = resolution == .hd1080 ? .hd1920x1080 : .hd1280x720
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }

        // Video input
        if let device = camera(for: currentPosition) {
            configureDevice(device, frameRate: frameRate)
            if let input = try? AVCaptureDeviceInput(device: device) {
                if session.canAddInput(input) {
                    if let old = videoInput { session.removeInput(old) }
                    session.addInput(input)
                    videoInput = input
                }
            }
        }

        // Audio input
        if let mic = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: mic) {
            if session.canAddInput(input) {
                if let old = audioInput { session.removeInput(old) }
                session.addInput(input)
                audioInput = input
            }
        }

        // Video output
        let vOut = AVCaptureVideoDataOutput()
        vOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        vOut.alwaysDiscardsLateVideoFrames = true
        vOut.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(vOut) {
            if let old = videoOutput { session.removeOutput(old) }
            session.addOutput(vOut)
            videoOutput = vOut

            if let connection = vOut.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                connection.isVideoMirrored = currentPosition == .front
            }
        }

        // Audio output
        let aOut = AVCaptureAudioDataOutput()
        aOut.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(aOut) {
            if let old = audioOutput { session.removeOutput(old) }
            session.addOutput(aOut)
            audioOutput = aOut
        }
    }

    private func configureDevice(_ device: AVCaptureDevice, frameRate: FrameRate) {
        guard let format = bestFormat(for: device, frameRate: frameRate) else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate.rawValue))
            device.unlockForConfiguration()
        } catch {}
    }

    private func bestFormat(for device: AVCaptureDevice, frameRate: FrameRate) -> AVCaptureDevice.Format? {
        device.formats.last { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let supports = format.videoSupportedFrameRateRanges.contains { range in
                range.maxFrameRate >= Double(frameRate.rawValue)
            }
            return dims.width >= 1280 && supports
        }
    }

    // MARK: - Controls

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
        }
    }

    func flipCamera(resolution: VideoResolution, frameRate: FrameRate) {
        currentPosition = currentPosition == .back ? .front : .back
        configure(resolution: resolution, frameRate: frameRate)
    }

    private func updateAudioMute() {
        audioInput?.device.perform { [weak self] in
            guard let self else { return }
            // Mute is handled at encoder level by dropping audio buffers
        }
    }

    // MARK: - Helpers

    private func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return session.devices.first
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureVideoDataOutput {
            onVideoSampleBuffer?(sampleBuffer)
        } else if output is AVCaptureAudioDataOutput {
            if !isMuted {
                onAudioSampleBuffer?(sampleBuffer)
            }
        }
    }
}

// MARK: - Device extension helper

private extension AVCaptureDevice {
    func perform(_ block: @escaping () -> Void) {
        block()
    }
}
