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

    var isWaiting: Bool { if case .waiting = phase { true } else { false } }
    private var verifying = false

    func start() {
        guard !busy else { return }
        attempt += 1
        switch kind {
        case .platformTools:
            download(Self.platformToolsURL, attempt: attempt) { try Self.installPlatformTools(zip: $0); return nil }
        case .obs:
            // Try Again after a drag that didn't happen: eject the image the last attempt left mounted.
            if case .waiting = phase { DispatchQueue.global(qos: .utility).async { Self.cleanUp() } }
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
    /// Google's Apple Developer team, as `codesign -dv` reads it on the SDK's adb.
    static let googleTeamID = "EQHXZ8M8AV"

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

    /// OBS Studio if it's installed in /Applications, where Launch Services knows it, or the copy this app put in
    /// place. Copies on a mounted image, in ~/Applications, the Trash or Downloads don't count, since macOS only turns
    /// on a camera extension from an app in /Applications.
    static func installedOBS() -> URL? {
        let copy = applicationsDirectory.appendingPathComponent("OBS.app")
        let ownCopy = FileManager.default.fileExists(atPath: copy.path) ? copy : nil
        if bareMac { return ownCopy }
        let known = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: obsBundleID).first { url in
            !url.lastPathComponent.hasPrefix(".") && url.path.hasPrefix("/Applications/")
        }
        return known ?? ownCopy
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
        phase = .installing(kind == .obs ? "Checking that OBS is genuine and copying it into Applications…" : "Installing platform tools…")
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
        let code = (error as? URLError)?.code
        if code == .cancelled { return }
        if let code, [.cannotWriteToFile, .cannotCreateFile, .cannotOpenFile].contains(code) {
            fail(WebcamError(message: "There isn't room on this Mac for the download. Free some space, then try again.",
                             detail: error.localizedDescription))
            return
        }
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
        sweep(parent) { $0.hasPrefix(".platform-tools-") }
        let staging = parent.appendingPathComponent(".platform-tools-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        let unzip = run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        guard unzip.status == 0 else {
            throw WebcamError(message: "The platform tools couldn't be unpacked on this Mac. Try again.", detail: "ditto: \(unzip.text)")
        }
        let tools = staging.appendingPathComponent("platform-tools", isDirectory: true)
        let adb = tools.appendingPathComponent("adb")
        guard fileManager.isExecutableFile(atPath: adb.path) else {
            throw WebcamError(message: "The platform tools downloaded, but adb didn't run on this Mac. Try again.",
                              detail: "No adb in the zip.")
        }
        // Signed by Google through Apple, before anything runs it.
        let requirement = "=anchor apple generic and certificate leaf[subject.OU] = \"\(googleTeamID)\""
        let signature = run("/usr/bin/codesign", ["--verify", "--strict", "-R", requirement, adb.path])
        guard signature.status == 0 else {
            throw WebcamError(message: "The platform tools downloaded, but adb didn't run on this Mac. Try again.",
                              detail: "adb failed its signature check: \(signature.text)")
        }
        let version = run(adb.path, ["version"])
        guard version.status == 0, version.text.contains("Android Debug Bridge") else {
            throw WebcamError(message: "The platform tools downloaded, but adb didn't run on this Mac. Try again.",
                              detail: "adb version: \(version.text)")
        }
        let destination = platformToolsDirectory
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: tools, to: destination)
    }

    /// Removes what a crashed or force-quit install left behind: only the hidden names this installer makes.
    private static func sweep(_ directory: URL, _ isLeftover: (String) -> Bool) {
        let fileManager = FileManager.default
        for name in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [] where isLeftover(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
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
                guard let data, error == nil, status != 0 else {
                    throw WebcamError(message: "Couldn't reach GitHub to find OBS. Check that the Mac is online, then try again.",
                                      detail: "GitHub releases: \(error?.localizedDescription ?? "no answer")")
                }
                guard status == 200 else {
                    throw WebcamError(message: "GitHub didn't answer right now. Try again later, or get OBS from obsproject.com.",
                                      detail: "GitHub releases: HTTP \(status) \(String(decoding: data.prefix(300), as: UTF8.self))")
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
        track(mount: mount)
        var detach = true
        defer { if detach { Self.detach(mount) } }
        let app = URL(fileURLWithPath: mount).appendingPathComponent("OBS.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw WebcamError(message: "The OBS download has no OBS app in it. Get it from obsproject.com instead.",
                              detail: "No OBS.app in \(mount).")
        }
        try verifyOBS(app)
        let applications = applicationsDirectory
        if DevMode.isOn { try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true) }
        guard FileManager.default.isWritableFile(atPath: applications.path) else {
            // Stays mounted for the drag; ejected once the step is done, on Try Again, or at quit.
            detach = false
            DispatchQueue.main.async {
                if DevMode.isOn { DevMode.record("open-url", mount) } else { NSWorkspace.shared.open(URL(fileURLWithPath: mount)) }
            }
            return .waiting("Drag OBS into the Applications folder in the Finder window that opened. This step finishes by itself.")
        }
        // Copied under a hidden name and renamed, so a half-done copy never counts as installed.
        let destination = applications.appendingPathComponent("OBS.app")
        sweep(applications) { $0.hasPrefix(".OBS-") && $0.hasSuffix(".app") }
        let partial = applications.appendingPathComponent(".OBS-\(UUID().uuidString).app")
        track(copy: partial)
        defer { try? FileManager.default.removeItem(at: partial); track(copy: nil) }
        let copy = run("/usr/bin/ditto", [app.path, partial.path])
        guard copy.status == 0, (try? FileManager.default.moveItem(at: partial, to: destination)) != nil else {
            throw WebcamError(message: "OBS couldn't be copied into Applications. Try again, or drag it in from obsproject.com's download.",
                              detail: "ditto: \(copy.text)")
        }
        return nil
    }

    // MARK: Mounted images

    private static let mountLock = NSLock()
    private static var mounts: Set<String> = []
    private static var copyInProgress: URL?

    private static func track(mount: String) {
        mountLock.lock(); mounts.insert(mount); mountLock.unlock()
    }

    private static func track(copy: URL?) {
        mountLock.lock(); copyInProgress = copy; mountLock.unlock()
    }

    private static func detach(_ mount: String) {
        _ = run("/usr/bin/hdiutil", ["detach", mount, "-quiet", "-force"])
        mountLock.lock(); mounts.remove(mount); mountLock.unlock()
    }

    /// Ejects every OBS image this app mounted and removes a copy cut short. Runs at quit, so it waits.
    static func cleanUp() {
        mountLock.lock()
        let open = mounts, partial = copyInProgress
        mountLock.unlock()
        for mount in open { detach(mount) }
        if let partial { try? FileManager.default.removeItem(at: partial) }
    }

    /// While the user drags OBS in by hand, checks the copy in Applications off main, one check at a time. Finder writes
    /// under the final name as it copies, and `codesign --verify --deep` fails until the copy is whole. Once it passes:
    /// idle, eject the image, and tell Setup.
    func checkDraggedCopy() {
        guard kind == .obs, isWaiting, !verifying else { return }
        verifying = true
        let current = attempt
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let ok = (try? Self.verifyOBS(Self.applicationsDirectory.appendingPathComponent("OBS.app"))) != nil
            if ok { Self.cleanUp() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.verifying = false
                guard ok, self.attempt == current, self.isWaiting else { return }
                self.phase = .idle
                self.onInstalled()
            }
        }
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
