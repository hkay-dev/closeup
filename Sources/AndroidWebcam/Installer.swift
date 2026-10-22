import AppKit
import Foundation

/// Downloads and installs what Setup needs, so nobody needs Terminal or Homebrew: Google's platform tools (adb) into
/// the app's support folder, and OBS Studio from its GitHub release into /Applications. The dev instance installs both
/// inside its own directory instead.
final class Installer: NSObject, ObservableObject, URLSessionDownloadDelegate {
    enum Kind { case platformTools, obs }

    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)   // total is 0 until the server says
        case installing(String)
        case failed(String)
        case waiting(String)                               // the user finishes it by hand
    }

    let kind: Kind
    @Published private(set) var phase: Phase = .idle
    /// Runs on main once something landed, so Setup checks again at once.
    var onInstalled: () -> Void = {}

    private var session: URLSession?
    private var task: URLSessionTask?
    private var attempt = 0
    private var afterDownload: ((URL) throws -> Phase?)?

    init(_ kind: Kind) { self.kind = kind }

    var busy: Bool {
        switch phase {
        case .downloading, .installing: true
        default: false
        }
    }

    var canCancel: Bool { if case .downloading = phase { true } else { false } }

    func start() {
        guard !busy else { return }
        attempt += 1
        switch kind {
        case .platformTools:
            download(Self.platformToolsURL, attempt: attempt) { try Self.installPlatformTools(zip: $0); return nil }
        case .obs:
            phase = .installing("Finding the latest OBS…")
            findOBSDownload(attempt: attempt)
        }
    }

    func cancel() {
        attempt += 1
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        phase = .idle
    }

    // MARK: Where things go

    static let platformToolsURL = URL(string: "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip")!
    static let platformToolsPage = URL(string: "https://developer.android.com/tools/releases/platform-tools")!
    static let obsPage = URL(string: "https://obsproject.com/download")!
    static let obsReleaseAPI = URL(string: "https://api.github.com/repos/obsproject/obs-studio/releases/latest")!
    static let obsBundleID = "com.obsproject.obs-studio"
    /// The OBS Project's Apple Developer team, as `codesign -dv` reads it on OBS.app.
    static let obsTeamID = "2MMRE5MTB8"

    /// A dev instance started with ANDROID_WEBCAM_DEV_BARE=1 acts like a Mac with nothing installed: only the adb and
    /// OBS it downloaded into its own directory count, and OBS's camera counts as off.
    static let bareMac = DevMode.isOn && ProcessInfo.processInfo.environment["ANDROID_WEBCAM_DEV_BARE"] == "1"

    /// `~/Library/Application Support/<app name>`, or the dev instance's directory.
    static var supportDirectory: URL {
        if let directory = DevMode.directory { return directory }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var platformToolsDirectory: URL { supportDirectory.appendingPathComponent("platform-tools", isDirectory: true) }

    /// /Applications, or `<dev dir>/Applications` so tests never install into the real one.
    static var applicationsDirectory: URL {
        DevMode.directory?.appendingPathComponent("Applications", isDirectory: true) ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    /// OBS Studio if it's installed: where Launch Services knows it, or the copy this app put in place.
    static func installedOBS() -> URL? {
        let copy = applicationsDirectory.appendingPathComponent("OBS.app")
        let ownCopy = FileManager.default.fileExists(atPath: copy.path) ? copy : nil
        if bareMac { return ownCopy }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: obsBundleID) ?? ownCopy
    }

    /// VirtualCamera.extensionState, except that a bare dev Mac has no OBS camera.
    static func cameraState() -> VirtualCamera.ExtensionState {
        bareMac ? .missing : VirtualCamera.extensionState()
    }

    // MARK: Download

    private func download(_ url: URL, attempt: Int, then finish: @escaping (URL) throws -> Phase?) {
        phase = .downloading(received: 0, total: 0)
        afterDownload = finish
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        let task = session.downloadTask(with: url)
        task.taskDescription = String(attempt)
        self.session = session
        self.task = task
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard downloadTask.taskDescription == String(attempt) else { return }
        let total = max(totalBytesExpectedToWrite, 0)
        // About 200 updates over a download is plenty for a progress bar.
        if case let .downloading(received, _) = phase, total > 0, totalBytesWritten - received < total / 200,
           totalBytesWritten < total { return }
        phase = .downloading(received: totalBytesWritten, total: total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadTask.taskDescription == String(attempt), let finish = afterDownload else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            fail(WebcamError(message: "The download didn't come through. Try again in a minute.",
                             detail: "\(downloadTask.originalRequest?.url?.absoluteString ?? "") answered HTTP \(status)."))
            return
        }
        // The file goes away when this returns, so move it first.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" +
            (downloadTask.originalRequest?.url?.lastPathComponent ?? "download"))
        do {
            try FileManager.default.moveItem(at: location, to: file)
        } catch {
            fail(WebcamError(message: "The download couldn't be saved on this Mac.", detail: "\(error)"))
            return
        }
        let current = attempt
        phase = .installing(kind == .obs ? "Checking and installing OBS…" : "Installing platform tools…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try finish(file) }
            try? FileManager.default.removeItem(at: file)
            DispatchQueue.main.async {
                guard let self, self.attempt == current else { return }
                switch result {
                case let .success(next):
                    self.phase = next ?? .idle
                    self.onInstalled()
                case let .failure(error): self.fail(error)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        guard task.taskDescription == String(attempt), let error else { return }
        self.task = nil
        self.session = nil
        if (error as? URLError)?.code == .cancelled { return }
        fail(WebcamError(message: "The download stopped. Check that the Mac is online, then try again.",
                         detail: error.localizedDescription))
    }

    private func fail(_ error: Error) {
        task = nil
        session = nil
        let message = (error as? WebcamError)?.message ?? error.localizedDescription
        if let detail = (error as? WebcamError)?.detail { fputs("Setup download failed. \(detail)\n", stderr) }
        phase = .failed(message)
    }

    // MARK: Platform tools

    /// Unzips into a folder next to the final one, checks adb runs, then puts it in place.
    static func installPlatformTools(zip: URL) throws {
        let fileManager = FileManager.default
        let parent = supportDirectory
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".platform-tools-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let unzip = run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        guard unzip.status == 0 else {
            throw WebcamError(message: "The platform tools couldn't be unpacked on this Mac. Try again.", detail: "ditto: \(unzip.text)")
        }
        let tools = staging.appendingPathComponent("platform-tools", isDirectory: true)
        let adb = tools.appendingPathComponent("adb")
        let version = fileManager.isExecutableFile(atPath: adb.path) ? run(adb.path, ["version"]) : (status: -1, text: "no adb in the zip")
        guard version.status == 0, version.text.contains("Android Debug Bridge") else {
            throw WebcamError(message: "The platform tools downloaded, but adb didn't run on this Mac. Try again.",
                              detail: "adb version: \(version.text)")
        }
        let destination = platformToolsDirectory
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: tools, to: destination)
    }

    // MARK: OBS

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let assets: [Asset]
    }

    /// `macOS-Apple` on Apple silicon, `macOS-Intel` otherwise, from the hardware rather than this build, so Rosetta
    /// doesn't pick the Intel copy.
    static var obsAssetPlatform: String {
        var arm: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &arm, &size, nil, 0) == 0 && arm == 1 ? "macOS-Apple" : "macOS-Intel"
    }

    private func findOBSDownload(attempt: Int) {
        var request = URLRequest(url: Self.obsReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: Result<URL, Error> = Result {
                guard let data, error == nil, status == 200 else {
                    throw WebcamError(message: "Couldn't reach GitHub to find OBS. Check that the Mac is online, then try again.",
                                      detail: "GitHub releases: HTTP \(status) \(error?.localizedDescription ?? "")")
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let platform = Self.obsAssetPlatform
                guard let asset = release.assets.first(where: { $0.name.hasSuffix("-\(platform).dmg") }) else {
                    throw WebcamError(message: "OBS \(release.tag_name) has no download for this Mac yet. Get it from obsproject.com instead.",
                                      detail: "No *-\(platform).dmg among \(release.assets.map(\.name)).")
                }
                return asset.browser_download_url
            }
            DispatchQueue.main.async {
                guard let self, self.attempt == attempt else { return }
                switch result {
                case let .success(url): self.download(url, attempt: attempt) { try Self.installOBS(dmg: $0) }
                case let .failure(error): self.fail(error)
                }
            }
        }.resume()
    }

    /// Mounts the disk image, checks OBS.app's signature, and copies it into Applications. When Applications isn't
    /// writable, opens the mounted disk in Finder and returns what the user does next.
    static func installOBS(dmg: URL) throws -> Phase? {
        let attach = run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-plist", dmg.path])
        // stderr shares the pipe, so read only the plist itself.
        let xml = attach.text.range(of: "<?xml").map { String(attach.text[$0.lowerBound...]) } ?? ""
        guard attach.status == 0,
              let plist = try? PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mount = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw WebcamError(message: "The OBS download didn't open. Try again.", detail: "hdiutil attach: \(attach.text)")
        }
        var detach = true
        defer { if detach { _ = run("/usr/bin/hdiutil", ["detach", mount, "-quiet", "-force"]) } }
        let app = URL(fileURLWithPath: mount).appendingPathComponent("OBS.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw WebcamError(message: "The OBS download has no OBS app in it. Get it from obsproject.com instead.",
                              detail: "No OBS.app in \(mount).")
        }
        try verifyOBS(app)
        let applications = applicationsDirectory
        if DevMode.isOn { try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true) }
        guard FileManager.default.isWritableFile(atPath: applications.path) else {
            detach = false
            DispatchQueue.main.async {
                if DevMode.isOn { DevMode.record("open-url", mount) } else { NSWorkspace.shared.open(URL(fileURLWithPath: mount)) }
            }
            return .waiting("Drag OBS into the Applications folder in the Finder window that opened. This step finishes by itself.")
        }
        let destination = applications.appendingPathComponent("OBS.app")
        let copy = run("/usr/bin/ditto", [app.path, destination.path])
        guard copy.status == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw WebcamError(message: "OBS couldn't be copied into Applications. Try again, or drag it in from obsproject.com's download.",
                              detail: "ditto: \(copy.text)")
        }
        return nil
    }

    /// Passes when the app's signature holds and it's signed by the OBS Project through Apple, not just any certificate
    /// that claims the team.
    static func verifyOBS(_ app: URL) throws {
        let requirement = "=anchor apple generic and identifier \"\(obsBundleID)\" and certificate leaf[subject.OU] = \"\(obsTeamID)\""
        let check = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", requirement, app.path])
        let info = run("/usr/bin/codesign", ["-dv", app.path])
        let team = info.text.split(separator: "\n").first { $0.hasPrefix("TeamIdentifier=") }?.dropFirst("TeamIdentifier=".count)
        guard check.status == 0, team.map(String.init) == obsTeamID else {
            throw WebcamError(message: "The OBS download failed its signature check, so it wasn't installed. Get OBS from obsproject.com instead.",
                              detail: "codesign --verify: \(check.text) team: \(team ?? "none")")
        }
    }

    /// Runs a tool to the end and returns its status and combined output.
    static func run(_ path: String, _ arguments: [String]) -> (status: Int32, text: String) {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
