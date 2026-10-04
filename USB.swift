import Foundation
import IOKit

/// The wired Xbox 360 (XUSB) interface and its interrupt endpoints in one configuration.
struct XUSBInterface: Equatable {
    var configuration: UInt8
    var number: UInt8
    var input: UInt8
    var output: UInt8?
}

/// Finds the first XUSB interface (class ff/5d/01, alternate setting 0) in a raw configuration descriptor.
func findXUSBInterface(in config: [UInt8], number: UInt8? = nil) -> XUSBInterface? {
    guard config.count >= 9, config[1] == 2 else { return nil }
    var found: XUSBInterface?
    var offset = 0
    while offset + 2 <= config.count {
        let length = Int(config[offset])
        guard length >= 2, offset + length <= config.count else { break }
        let type = config[offset + 1]
        if type == 4, length >= 9 {
            if let found, found.input != 0 { return found }
            let matches = config[offset + 3] == 0 && config[offset + 5] == 0xff && config[offset + 6] == 0x5d &&
                config[offset + 7] == 0x01 && (number == nil || config[offset + 2] == number)
            found = matches ? XUSBInterface(configuration: config[5], number: config[offset + 2], input: 0) : nil
        } else if type == 5, length >= 7, found != nil, config[offset + 3] & 0x03 == 0x03 {
            let address = config[offset + 2]
            if address & 0x80 != 0, found?.input == 0 { found?.input = address }
            if address & 0x80 == 0, found?.output == nil { found?.output = address }
        }
        offset += length
    }
    return found?.input == 0 ? nil : found
}

private func registry<T>(_ service: io_service_t, _ key: String) -> T? {
    IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, nil,
                                    IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? T
}

private func registryInt(_ service: io_service_t, _ key: String) -> Int {
    registry(service, key) ?? 0
}

/// Selects the XUSB configuration on an unconfigured vendor-specific device so its interface appears.
/// Devices that are already configured, or have no XUSB interface, are closed unchanged.
func configureIfXUSB(_ service: io_service_t) {
    var error: IOReturn = 0
    guard let device = usb_device_open(service, &error) else { return }
    defer { usb_device_close(device) }
    var bytes: UnsafePointer<UInt8>?
    var length: UInt16 = 0
    guard usb_device_configuration(device) == 0, usb_device_descriptor(device, 0, &bytes, &length) == kIOReturnSuccess,
          let bytes, let xusb = findXUSBInterface(in: Array(UnsafeBufferPointer(start: bytes, count: Int(length)))) else {
        return
    }
    usb_device_configure(device, xusb.configuration)
}

/// One claimed XUSB interface. A dedicated thread reads input reports until the controller disconnects.
final class Controller: @unchecked Sendable {
    let id: UInt64
    let name: String
    let vendorID: Int
    let productID: Int
    private let usb: OpaquePointer
    private let onState: @Sendable (Gamepad) -> Void
    private let onStop: @Sendable () -> Void

    init(service: io_service_t, onState: @escaping @Sendable (Gamepad) -> Void,
         onStop: @escaping @Sendable () -> Void) throws {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)
        id = entryID
        vendorID = registryInt(service, "idVendor")
        productID = registryInt(service, "idProduct")
        name = registry(service, "USB Product Name") ?? String(format: "Controller %04x:%04x", vendorID, productID)
        var error: IOReturn = 0
        guard let usb = usb_interface_open(service, &error) else {
            throw Failure(String(format: "USB interface open failed: 0x%08x", error))
        }
        self.usb = usb
        self.onState = onState
        self.onStop = onStop
    }

    func start(player: Int) {
        let thread = Thread { [self] in
            // XUSB LED command 01 03 NN; 06-09 light quadrant 1-4 steadily.
            if (1...4).contains(player) {
                var led: [UInt8] = [0x01, 0x03, UInt8(0x05 + player)]
                usb_interface_write(usb, &led, UInt32(led.count))
            }
            var buffer = [UInt8](repeating: 0, count: 64)
            while true {
                var size = UInt32(buffer.count)
                guard usb_interface_read(usb, &buffer, &size) == kIOReturnSuccess else { break }
                if let state = Gamepad(packet: Array(buffer.prefix(Int(size)))) { onState(state) }
            }
            usb_interface_close(usb)
            onStop()
        }
        thread.name = "King of Drivers player \(player)"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}

/// Delivers IOKit matching notifications for XUSB devices and interfaces on the main queue.
@MainActor
final class USBWatcher {
    private let port = IONotificationPortCreate(kIOMainPortDefault)
    private let onInterface: (io_service_t) -> Void

    init(onInterface: @escaping (io_service_t) -> Void) {
        self.onInterface = onInterface
        IONotificationPortSetDispatchQueue(port, .main)
        // Vendor-specific class matching needs a vendor ID under USB matching rules, so filter here instead.
        watch("IOUSBHostDevice") { device in
            if registryInt(device, "bDeviceClass") == 0xff { configureIfXUSB(device) }
        }
        watch("IOUSBHostInterface") { [unowned self] interface in
            let protocolID = [registryInt(interface, "bInterfaceClass"), registryInt(interface, "bInterfaceSubClass"),
                              registryInt(interface, "bInterfaceProtocol")]
            if protocolID == [0xff, 0x5d, 0x01] { self.onInterface(interface) }
        }
    }

    private final class Handler {
        let handle: (io_service_t) -> Void
        init(_ handle: @escaping (io_service_t) -> Void) { self.handle = handle }
    }

    private func watch(_ serviceClass: String, _ handle: @escaping (io_service_t) -> Void) {
        let handler = Unmanaged.passRetained(Handler(handle)).toOpaque()
        var iterator: io_iterator_t = 0
        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching(serviceClass), { context, iterator in
            let handler = Unmanaged<Handler>.fromOpaque(context!).takeUnretainedValue()
            drain(iterator, handler.handle)
        }, handler, &iterator)
        drain(iterator, handle)
    }
}

private func drain(_ iterator: io_iterator_t, _ handle: (io_service_t) -> Void) {
    while case let service = IOIteratorNext(iterator), service != 0 {
        handle(service)
        IOObjectRelease(service)
    }
}
