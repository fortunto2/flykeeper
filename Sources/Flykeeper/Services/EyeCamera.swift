import AVFoundation
import CoreVideo
import Foundation

/// The back camera, reduced to a small luminance grid. Nothing is recorded, written or sent:
/// each frame is sampled into the fly's photoreceptors and dropped.
final class EyeCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Grid the frame is reduced to. A fly has about 700 ommatidia an eye, so anything finer
    /// is thrown away by the sampling anyway.
    static let width = 64
    static let height = 48

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "co.superduperai.flykeeper.eye")
    private let lock = NSLock()
    private var luma = [Float](repeating: 0.5, count: width * height)
    private(set) var isRunning = false

    /// Latest frame, copied out under a lock; the capture queue writes, the render loop reads.
    func frame() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return luma
    }

    /// Why the eye could not open. Two different facts that look identical from outside, and
    /// reporting one as the other sends the keeper to Settings to fix a camera that is not
    /// there — the simulator has none at all.
    enum Failure: Sendable {
        case denied
        case noCamera
    }

    func start() async -> Failure? {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return .denied }
        return await withCheckedContinuation { k in
            queue.async {
                guard self.configure() else { k.resume(returning: .noCamera); return }
                self.session.startRunning()
                self.isRunning = true
                k.resume(returning: nil)
            }
        }
    }

    func stop() {
        queue.async {
            guard self.isRunning else { return }
            self.session.stopRunning()
            self.isRunning = false
        }
    }

    private func configure() -> Bool {
        guard session.inputs.isEmpty else { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .low
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        let out = AVCaptureVideoDataOutput()
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        out.alwaysDiscardsLateVideoFrames = true
        out.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(out) else { return false }
        session.addOutput(out)
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        // Plane 0 of 4:2:0 is luminance already — the fly's achromatic channel, for free.
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let w = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let h = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let src = base.assumingMemoryBound(to: UInt8.self)
        var grid = [Float](repeating: 0, count: Self.width * Self.height)
        for y in 0..<Self.height {
            let sy = min(y * h / Self.height, h - 1)
            for x in 0..<Self.width {
                let sx = min(x * w / Self.width, w - 1)
                grid[y * Self.width + x] = Float(src[sy * stride + sx]) / 255
            }
        }
        lock.lock(); luma = grid; lock.unlock()
    }
}
