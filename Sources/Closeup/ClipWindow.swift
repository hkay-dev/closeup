import AppKit
import AVFoundation
import AVKit

/// A short clip that's bundled with the app, looping without sound in a window of its own, for a Setup step that
/// happens outside the app (macOS's camera box and System Settings). Its file is in Resources, which build-app.sh copies.
enum ClipWindow {
    private static var window: NSWindow?
    private static var current: URL?
    private static var looper: AVPlayerLooper?
    private static var closeObserver: NSObjectProtocol?

    static func url(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "mp4") }

    static func show(_ clip: URL, title: String) {
        if let window, current == clip {
            bringForward(window)
            return
        }
        window?.close()
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: clip))
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.center()
        Self.window = window
        current = clip
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                               queue: .main) { _ in
            player.pause()
            looper = nil
            Self.window = nil
            current = nil
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            closeObserver = nil
        }
        // The window takes the clip's own size, so its words show at the size they were recorded.
        Task { @MainActor in
            if let track = try? await AVURLAsset(url: clip).loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize), size.width > 0, Self.window === window {
                window.setContentSize(size)
                window.contentAspectRatio = size
                window.center()
            }
        }
        bringForward(window)
        player.play()
    }
}
