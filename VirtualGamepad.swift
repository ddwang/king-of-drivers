import CoreHID
import Foundation

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

actor Reports: HIDVirtualDeviceDelegate {
    private var latest = Gamepad().hidReport

    func update(_ data: Data) { latest = data }

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedSetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, data: Data) throws {
        throw Failure("Output and feature reports are unsupported.")
    }

    func hidVirtualDevice(_ device: HIDVirtualDevice, receivedGetReportRequestOfType type: HIDReportType,
                          id: HIDReportID?, maxSize: Int) throws -> Data {
        guard type == .input, id == nil, maxSize >= latest.count else {
            throw Failure("Unsupported report request.")
        }
        return latest
    }
}

/// Returns nil when the app lacks Apple's `com.apple.developer.hid.virtual.device` entitlement.
func virtualGamepad(product: String) -> HIDVirtualDevice? {
    HIDVirtualDevice(properties: HIDVirtualDevice.Properties(
        descriptor: Gamepad.descriptor, vendorID: 0, productID: 0,
        product: product, manufacturer: "King of Drivers 2026"
    ))
}
