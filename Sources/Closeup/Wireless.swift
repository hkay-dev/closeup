import dnssd
import Foundation
import os

/// Phones on wireless debugging (kata:android-webcam#b60q), off by default so the app stays USB only. Settings'
/// "Phones over Wi-Fi" switch sets `wirelessAdb` and takes effect at once; `CLOSEUP_WIRELESS=1` (or `0`) in
/// the environment wins over it, for dev runs.
enum Wireless {
    static let defaultsKey = "wirelessAdb"
    static let environmentKey = "CLOSEUP_WIRELESS"

    static var enabled: Bool {
        if let value = ProcessInfo.processInfo.environment[environmentKey] {
            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
        return Prefs.defaults.bool(forKey: defaultsKey)
    }

    static var forcedByEnvironment: Bool { ProcessInfo.processInfo.environment[environmentKey] != nil }
}

/// Finds Bonjour services of one type on the local network and resolves each to an IPv4 "address:port", with
/// callbacks on main. adb's own mDNS can't be relied on: a server started while the switch was off has it turned off
/// (ADB_MDNS=0), and the app never restarts a server other tools share.
final class BonjourBrowser {
    /// Service name to "address:port", for the ones resolved so far.
    private(set) var services: [String: String] = [:]
    var onChange: () -> Void = {}
    private let type: String
    private var browseRef: DNSServiceRef?
    private var lookups: [String: Lookup] = [:]

    /// One service's resolve, then its address lookup. A class, so the C callbacks have a stable context.
    private final class Lookup {
        weak var browser: BonjourBrowser?
        let name: String
        var ref: DNSServiceRef?
        var port: UInt16 = 0
        init(browser: BonjourBrowser, name: String) { self.browser = browser; self.name = name }
        func cancel() { if let ref { DNSServiceRefDeallocate(ref) }; ref = nil }
    }

    init(type: String) { self.type = type }
    deinit { stop() }

    func start() {
        guard browseRef == nil else { return }
        var ref: DNSServiceRef?
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard DNSServiceBrowse(&ref, 0, 0, type, "local.", Self.browsed, context) == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, .main)
        browseRef = ref
    }

    func stop() {
        if let browseRef { DNSServiceRefDeallocate(browseRef) }
        browseRef = nil
        for lookup in lookups.values { lookup.cancel() }
        lookups = [:]
        services = [:]
    }

    private static let browsed: DNSServiceBrowseReply = { _, flags, interface, error, name, type, domain, context in
        guard error == kDNSServiceErr_NoError, let context, let name, let type, let domain else { return }
        let browser = Unmanaged<BonjourBrowser>.fromOpaque(context).takeUnretainedValue()
        browser.browsed(String(cString: name), type: type, domain: domain, interface: interface,
                        added: flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0)
    }

    private func browsed(_ name: String, type: UnsafePointer<CChar>, domain: UnsafePointer<CChar>, interface: UInt32, added: Bool) {
        lookups[name]?.cancel()
        lookups[name] = nil
        guard added else {
            if services.removeValue(forKey: name) != nil { onChange() }
            return
        }
        let lookup = Lookup(browser: self, name: name)
        var ref: DNSServiceRef?
        guard DNSServiceResolve(&ref, 0, interface, name, type, domain, Self.resolved,
                                Unmanaged.passUnretained(lookup).toOpaque()) == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, .main)
        lookup.ref = ref
        lookups[name] = lookup
    }

    private static let resolved: DNSServiceResolveReply = { _, _, interface, error, _, host, port, _, _, context in
        guard error == kDNSServiceErr_NoError, let context, let host else { return }
        let lookup = Unmanaged<Lookup>.fromOpaque(context).takeUnretainedValue()
        lookup.cancel()
        lookup.port = UInt16(bigEndian: port)
        var ref: DNSServiceRef?
        guard DNSServiceGetAddrInfo(&ref, 0, interface, DNSServiceProtocol(kDNSServiceProtocol_IPv4), host, BonjourBrowser.addressed,
                                    context) == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, .main)
        lookup.ref = ref
    }

    private static let addressed: DNSServiceGetAddrInfoReply = { _, _, _, error, _, address, _, context in
        guard error == kDNSServiceErr_NoError, let context, let address, address.pointee.sa_family == sa_family_t(AF_INET) else { return }
        let lookup = Unmanaged<Lookup>.fromOpaque(context).takeUnretainedValue()
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        guard inet_ntop(AF_INET, &ip, &text, socklen_t(text.count)) != nil, let browser = lookup.browser else { return }
        lookup.cancel()
        let found = "\(String(cString: text)):\(lookup.port)"
        guard browser.services[lookup.name] != found else { return }
        browser.services[lookup.name] = found
        browser.onChange()
    }
}

/// Connects phones this Mac has paired with whenever they're on the network, as adb's own mDNS would. A phone that
/// was never paired refuses the connection, so each address is tried at most every few minutes.
final class WirelessConnector {
    /// What adb lists right now, so a phone it already has isn't connected twice.
    var listed: () -> [AndroidDevice] = { [] }
    private let browser = BonjourBrowser(type: "_adb-tls-connect._tcp")
    private var lastTry: [String: Date] = [:]

    init() { browser.onChange = { [weak self] in self?.connectMissing() } }

    func start() { browser.start() }
    func stop() { browser.stop(); lastTry = [:] }

    /// Also called when adb's list changes, since a phone that drops off Wi-Fi shows up here again on its own.
    func connectMissing() {
        for (name, address) in browser.services where !isListed(name: name, address: address) {
            if let last = lastTry[address], Date().timeIntervalSince(last) < 180 { continue }
            lastTry[address] = Date()
            // adb's own mDNS, when it's on, usually gets there first; give it a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, !self.isListed(name: name, address: address) else { return }
                DispatchQueue.global(qos: .utility).async { _ = try? ADB.command(["connect", address], timeout: 10) }
            }
        }
    }

    /// adb names a phone it found itself "<service name>._adb-tls-connect._tcp", and one connected by address "ip:port".
    private func isListed(name: String, address: String) -> Bool {
        listed().contains { $0.serial.hasPrefix(name) || $0.serial == address }
    }
}

/// Pairs a phone over Wi-Fi the way Android Studio does: the Mac shows a QR code with a made-up service name and
/// password, the phone's "Pair device with QR code" scans it and advertises that name on the network, and the Mac runs
/// `adb pair` against it. The phone's "Pair device with pairing code" works the same way with the six digits it
/// shows. After pairing, the phone advertises its connect service and WirelessConnector (or adb itself) connects it.
final class WirelessPairing: ObservableObject {
    enum Phase: Equatable {
        case waiting
        case pairing
        case connecting
        case connected(String)
        case failed(String)
    }

    @Published private(set) var phase = Phase.waiting
    @Published private(set) var qrPayload = ""
    var close: () -> Void = {}
    /// Runs on main once adb has paired, so the app looks for the phone at once.
    var onPaired: () -> Void = {}

    private static let prefix = "Closeup-"
    private let browser = BonjourBrowser(type: "_adb-tls-pairing._tcp")
    private var serviceName = ""
    private var password = ""
    private var code: String?
    private var attempt = 0
    /// The phone's id from `adb pair` ("adb-R5CY11B8DHD-KmFSaA"), and the wireless phones listed before it paired.
    private var pairedGUID: String?
    private var wirelessBefore: Set<String> = []
    private var timeout: DispatchWorkItem?

    init() { browser.onChange = { [weak self] in self?.lookForPhone() } }

    func start(listed: [AndroidDevice]) {
        wirelessBefore = Set(listed.filter(\.wireless).map(\.serial))
        restart()
        browser.start()
    }

    func stop() {
        attempt += 1
        timeout?.cancel()
        browser.stop()
    }

    func restart() {
        attempt += 1
        timeout?.cancel()
        serviceName = Self.prefix + Self.random(6, from: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        password = Self.random(10, from: "abcdefghijkmnpqrstuvwxyz23456789")
        qrPayload = "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
        code = nil
        pairedGUID = nil
        phase = .waiting
        lookForPhone()
    }

    /// The six digits from the phone's "Pair device with pairing code" screen. Pairs once the phone's pairing service
    /// is on the network, which it is while that screen is open.
    func pair(code: String) {
        guard phase == .waiting || isFailed else { return }
        if isFailed { restart() }
        self.code = code
        lookForPhone()
    }

    /// adb's list changed while connecting: the phone that just paired has arrived.
    func devicesChanged(_ devices: [AndroidDevice]) {
        guard phase == .connecting else { return }
        let arrived = devices.first { device in
            device.wireless && device.authorized
                && (pairedGUID.map { device.serial.hasPrefix($0) } == true || !wirelessBefore.contains(device.serial))
        }
        if let arrived {
            timeout?.cancel()
            phase = .connected(arrived.displayName)
        }
    }

    private var isFailed: Bool { if case .failed = phase { true } else { false } }

    private func lookForPhone() {
        guard phase == .waiting else { return }
        if let address = browser.services[serviceName] {
            run(address: address, secret: password)
        } else if let code, let address = browser.services.first(where: { !$0.key.hasPrefix(Self.prefix) })?.value {
            run(address: address, secret: code)
        }
    }

    private func run(address: String, secret: String) {
        phase = .pairing
        let attempt = attempt
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try ADB.command(["pair", address, secret], timeout: 20) }
            DispatchQueue.main.async {
                guard let self, self.attempt == attempt else { return }
                switch result {
                case let .success(text) where text.contains("Successfully paired"):
                    self.pairedGUID = text.range(of: #"guid=([^\]\s]+)"#, options: .regularExpression)
                        .map { String(text[$0].dropFirst(5)) }
                    self.phase = .connecting
                    self.onPaired()
                    let timeout = DispatchWorkItem { [weak self] in
                        guard let self, self.phase == .connecting else { return }
                        self.phase = .failed("It paired, but the phone didn't connect. Check that Wireless debugging is still on, then try again.")
                    }
                    self.timeout = timeout
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
                default:
                    self.code = nil
                    self.phase = .failed(secret == self.password
                        ? "The phone didn't pair. Scan the new code and try again."
                        : "That code didn't work. Check the six digits on the phone and try again.")
                    if secret == self.password { self.restartKeepingFailure() }
                }
            }
        }
    }

    /// A failed QR pairing can't be retried with the same code, so a new one goes up under the failure message.
    private func restartKeepingFailure() {
        let failure = phase
        restart()
        phase = failure
    }

    private static func random(_ count: Int, from characters: String) -> String {
        let pool = Array(characters)
        return String((0..<count).map { _ in pool.randomElement()! })
    }
}

/// One log line per second while capturing, for the wireless latency session. Frames and bytes received, the
/// longest gap between packets, and how far arrival has drifted behind the phone's clock.
///
/// Watch it with `log stream --level info --predicate 'subsystem == "com.harsha.closeup" AND category == "wireless-latency"'`.
///
/// The phone and Mac clocks differ, so `behind_ms` is arrival minus pts measured from the least delayed packet
/// seen since capture started. It sits near 0 on a link that keeps up and grows while frames queue. The two
/// clocks also drift a few ms in five minutes, so read the trend, not a single digit.
final class PacketLog {
    private static let log = Logger(subsystem: "com.harsha.closeup", category: "wireless-latency")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "closeup.packet-log", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var frames = 0, bytes = 0
    private var longestGap: UInt64 = 0
    private var lastArrival: UInt64?
    private var packetsThisSecond = 0
    private var floorOffset: Int64?
    private var behindLast: Int64?, behindMax: Int64?

    init(label: String) {
        Self.log.info("capture started \(label, privacy: .public)")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.flush() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        lock.lock(); let running = timer; timer = nil; lock.unlock()
        running?.cancel()
    }

    /// Called once the whole packet has been read. pts is the phone's capture time in microseconds.
    func record(size: Int, pts: Int64, configuration: Bool) {
        let arrival = DispatchTime.now().uptimeNanoseconds
        lock.lock(); defer { lock.unlock() }
        if let lastArrival { longestGap = max(longestGap, arrival - lastArrival) }
        lastArrival = arrival
        packetsThisSecond += 1
        bytes += size
        guard !configuration else { return }
        frames += 1
        let offset = Int64(arrival / 1000) - pts
        let floor = min(floorOffset ?? offset, offset)
        floorOffset = floor
        let behind = offset - floor
        behindLast = behind
        behindMax = max(behindMax ?? behind, behind)
    }

    private func flush() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        guard let lastArrival else { lock.unlock(); return }    // the camera is still opening
        // A second with no packet at all is one long gap that hasn't ended yet.
        let gap = packetsThisSecond == 0 ? now - lastArrival : longestGap
        let line = "frames=\(frames) bytes=\(bytes) max_gap_ms=\(gap / 1_000_000) "
            + "behind_ms=\(behindLast.map { String($0 / 1000) } ?? "-") behind_max_ms=\(behindMax.map { String($0 / 1000) } ?? "-")"
        frames = 0; bytes = 0; longestGap = 0; packetsThisSecond = 0; behindLast = nil; behindMax = nil
        lock.unlock()
        Self.log.info("\(line, privacy: .public)")
    }
}
