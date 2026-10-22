import Foundation

/// Settings' Check for Updates: asks GitHub for the newest release, only when the button is pressed.
enum Updates {
    static let releasesPage = URL(string: "https://github.com/hkay-dev/android-webcam/releases")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/hkay-dev/android-webcam/releases/latest")!

    enum Result: Equatable {
        case upToDate
        case available(version: String, page: URL)
        case failed(String)
    }

    /// Calls back on main.
    static func check(current: String, completion: @escaping (Result) -> Void) {
        // The dev instance stands in for GitHub: dev.sh start devLatestRelease=v9.9.9 (or =none for no releases).
        if DevMode.isOn, let fake = Prefs.defaults.string(forKey: "devLatestRelease") {
            let result = fake == "none" ? Result.failed(noReleases) : answer(tag: fake, page: releasesPage, current: current)
            DispatchQueue.main.async { completion(result) }
            return
        }
        var request = URLRequest(url: latestAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: Result
            if error != nil || status == 0 {
                result = .failed("Couldn't reach GitHub. Check that the Mac is online, then try again.")
            } else if status == 404 {
                result = .failed(noReleases)
            } else if let data, (200..<300).contains(status),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String {
                let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPage
                result = answer(tag: tag, page: page, current: current)
            } else {
                result = .failed("GitHub didn't answer as expected (HTTP \(status)). Try again later.")
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private static let noReleases = "There are no releases on GitHub yet."

    private static func answer(tag: String, page: URL, current: String) -> Result {
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(latest, than: current) ? .available(version: latest, page: page) : .upToDate
    }

    /// Compares the numbers of a dotted version, so 0.10.0 is newer than 0.9.2. A build without a version
    /// ("development build") counts as older than any release.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func numbers(_ version: String) -> [Int] {
            let core = version.split(separator: "-").first.map(String.init) ?? version
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = numbers(candidate), b = numbers(current)
        guard b.contains(where: { $0 != 0 }) || current.first?.isNumber == true else { return true }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
