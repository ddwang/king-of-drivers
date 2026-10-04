import CoreHID
import Foundation
import IOKit
import Observation

/// Connects each XUSB controller to its own virtual HID gamepad and tracks player slots.
@MainActor @Observable
final class Bridge {
    struct Pad: Identifiable {
        let id: UInt64
        let name: String
        let player: Int
        let virtual: Bool
    }

    private(set) var pads: [Pad] = []
    private(set) var notice: String?
    @ObservationIgnored private var watcher: USBWatcher?
    @ObservationIgnored private let log: ((String) -> Void)?

    init(log: ((String) -> Void)? = nil) {
        self.log = log
        watcher = USBWatcher { [unowned self] in attach($0) }
    }

    private func attach(_ service: io_service_t) {
        let (states, continuation) = AsyncStream.makeStream(of: Gamepad.self)
        let controller: Controller
        do {
            controller = try Controller(service: service, onState: { continuation.yield($0) },
                                        onStop: { continuation.finish() })
        } catch {
            notice = "A controller is in use by another app."
            log?("Couldn't open controller: \(error)")
            return
        }
        notice = nil
        let player = (1...).first { slot in !pads.contains { $0.player == slot } }!
        let device = virtualGamepad(product: controller.name)
        let id = controller.id
        pads.append(Pad(id: id, name: controller.name, player: player, virtual: device != nil))
        log?(String(format: "Connected player %d: %@ (%04x:%04x). Virtual gamepad: %@.", player, controller.name,
                    controller.vendorID, controller.productID, device == nil ? "unavailable, needs Apple's entitlement" : "active"))
        Task {
            let reports = Reports()
            if let device { await device.activate(delegate: reports) }
            var last: Gamepad?
            for await state in states where state != last {
                last = state
                log?(state.summary)
                guard let device else { continue }
                let report = state.hidReport
                await reports.update(report)
                try? await device.dispatchInputReport(data: report, timestamp: .now)
            }
            pads.removeAll { $0.id == id }
            log?("Disconnected player \(player): \(controller.name).")
        }
        controller.start(player: player)
    }
}
