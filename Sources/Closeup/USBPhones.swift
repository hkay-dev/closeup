import Foundation
import IOKit
import IOKit.usb

/// An Android phone on USB as IOKit sees it, whether or not USB debugging is on, so Setup can tell
/// "nothing plugged in" from "plugged in, but adb can't see it yet".
struct USBPhone: Equatable, Codable {
    let vendorID: Int
    /// The USB product string, such as "Pixel 8" (Samsung says "SAMSUNG_Android").
    let product: String?
    let serial: String?
    /// adb's USB interface is there, which only happens while USB debugging is on.
    let debugging: Bool

    var brand: PhoneBrand { USBPhones.brands[vendorID] ?? .other }

    /// A name for Setup: the product string when it names the phone, else the maker.
    var displayName: String {
        if let product, !product.localizedCaseInsensitiveContains("android"), !product.isEmpty { return product }
        switch brand {
        case .samsung: return "Your Samsung phone"
        case .google: return "Your Pixel"
        case .xiaomi: return "Your Xiaomi phone"
        case .oneplus: return "Your OnePlus phone"
        case .motorola: return "Your Motorola phone"
        case .other: return "Your phone"
        }
    }
}

enum USBPhones {
    static let brands: [Int: PhoneBrand] = [0x04E8: .samsung, 0x18D1: .google, 0x2717: .xiaomi, 0x2A70: .oneplus, 0x22B8: .motorola]
    private static let apple = 0x05AC
    /// Other makers of Android phones (Sony, LG, Huawei, OPPO, vivo, HTC, Lenovo, ZTE, Asus, TCL, Meizu). Any phone with
    /// USB debugging on counts too, from its adb interface.
    private static let otherMakers: Set<Int> = [0x0FCE, 0x1004, 0x12D1, 0x22D9, 0x2D95, 0x0BB4, 0x17EF, 0x19D2, 0x0B05, 0x1BBB, 0x2A45]
    /// Interface classes of things that aren't phones: audio, HID, mass storage, hubs, video.
    private static let notPhone: Set<Int> = [1, 3, 8, 9, 14]

    /// The dev instance reads `devUSBPhones` (a JSON array of USBPhone) instead, so the connection states can be
    /// walked without unplugging anything: dev.sh start 'devUSBPhones:=[{"vendorID":1256,"debugging":false}]'.
    static func list() -> [USBPhone] {
        if DevMode.isOn {
            guard let text = Prefs.defaults.string(forKey: "devUSBPhones") else { return [] }
            return (try? JSONDecoder().decode([USBPhone].self, from: Data(text.utf8))) ?? []
        }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var phones: [USBPhone] = []
        while case let device = IOIteratorNext(iterator), device != 0 {
            defer { IOObjectRelease(device) }
            if let phone = phone(device) { phones.append(phone) }
        }
        return phones
    }

    private static func phone(_ device: io_registry_entry_t) -> USBPhone? {
        guard let vendor = number(device, "idVendor"), vendor != apple else { return nil }
        let interfaces = interfaceTriples(device)
        let adb = interfaces.contains { $0 == (0xFF, 0x42, 0x01) }
        let known = brands[vendor] != nil || otherMakers.contains(vendor)
        // A known maker's phone, unless every interface says it's a drive, a hub or the like (a Samsung SSD, say).
        // An unconfigured device has no interfaces yet and counts.
        guard adb || (known && !(!interfaces.isEmpty && interfaces.allSatisfy { notPhone.contains($0.0) })) else { return nil }
        return USBPhone(vendorID: vendor, product: string(device, "USB Product Name") ?? string(device, "kUSBProductString"),
                        serial: string(device, "USB Serial Number") ?? string(device, "kUSBSerialNumberString"), debugging: adb)
    }

    /// (class, subclass, protocol) of each interface under the device.
    private static func interfaceTriples(_ device: io_registry_entry_t) -> [(Int, Int, Int)] {
        var children: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(device, kIOServicePlane, &children) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(children) }
        var found: [(Int, Int, Int)] = []
        while case let child = IOIteratorNext(children), child != 0 {
            defer { IOObjectRelease(child) }
            if let type = number(child, "bInterfaceClass") {
                found.append((type, number(child, "bInterfaceSubClass") ?? 0, number(child, "bInterfaceProtocol") ?? 0))
            }
        }
        return found
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func number(_ entry: io_registry_entry_t, _ key: String) -> Int? { (property(entry, key) as? NSNumber)?.intValue }
    private static func string(_ entry: io_registry_entry_t, _ key: String) -> String? { property(entry, key) as? String }
}
