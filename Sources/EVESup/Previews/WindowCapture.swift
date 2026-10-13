import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Streams one window's contents at thumbnail size with ScreenCaptureKit.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Called on the main thread with each new frame.
    var onFrame: (@MainActor (IOSurfaceRef) -> Void)?
    /// Called on the main thread if the stream stops by itself (window closed, permission revoked…).
    var onStop: (@MainActor (Error) -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "EVESup.capture", qos: .userInteractive)

    func start(window: SCWindow, pointSize: CGSize, scale: CGFloat, fps: Double) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = Self.configuration(pointSize: pointSize, sourceSize: window.frame.size, scale: scale, fps: fps)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func update(pointSize: CGSize, sourceSize: CGSize, scale: CGFloat, fps: Double) {
        let configuration = Self.configuration(pointSize: pointSize, sourceSize: sourceSize, scale: scale, fps: fps)
        stream?.updateConfiguration(configuration) { error in
            if let error { Log.warn("couldn't update capture settings: \(error.localizedDescription)") }
        }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        stream.stopCapture { _ in }
    }

    /// Frames come out in the source window's shape (scaled to fit the
    /// preview), so the preview can place them without baked-in black bars.
    private static func configuration(pointSize: CGSize, sourceSize: CGSize, scale: CGFloat, fps: Double) -> SCStreamConfiguration {
        var size = pointSize
        if sourceSize.width > 0, sourceSize.height > 0 {
            let factor = min(pointSize.width / sourceSize.width, pointSize.height / sourceSize.height)
            size = CGSize(width: sourceSize.width * factor, height: sourceSize.height * factor)
        }
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int((size.width * scale).rounded()))
        configuration.height = max(2, Int((size.height * scale).rounded()))
        configuration.minimumFrameInterval = CMTime(seconds: 1 / min(max(fps, 1), 60), preferredTimescale: 600)
        configuration.queueDepth = 4
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        return configuration
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusValue) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onFrame?(surface) }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.stream = nil
                self?.onStop?(error)
            }
        }
    }
}
