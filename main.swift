import ServiceManagement
import SwiftUI

struct KingOfDriversApp: App {
    @State private var bridge = Bridge()

    var body: some Scene {
        MenuBarExtra("King of Drivers 2026", systemImage: "gamecontroller") {
            MenuContent(bridge: bridge)
        }
    }
}

struct MenuContent: View {
    let bridge: Bridge
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        if bridge.pads.isEmpty { Text("No controllers connected") }
        ForEach(bridge.pads) { pad in Text("Player \(pad.player): \(pad.name)") }
        if bridge.pads.contains(where: { !$0.virtual }) {
            Text("Virtual gamepad unavailable in this build")
        }
        if let notice = bridge.notice { Text(notice) }
        Divider()
        Toggle("Open at Login", isOn: $openAtLogin)
            .onChange(of: openAtLogin) { _, enabled in
                try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                openAtLogin = SMAppService.mainApp.status == .enabled
            }
        Button("Quit King of Drivers 2026") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

func selfTest() throws {
    func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure("Self-test failed: \(message)") }
    }
    func config(_ body: [UInt8]) -> [UInt8] {
        let total = body.count + 9
        return [9, 2, UInt8(total & 0xff), UInt8(total >> 8), 4, 1, 0, 0xa0, 0xfa] + body
    }
    let xusb: [UInt8] = [9, 4, 0, 0, 2, 0xff, 0x5d, 0x01, 0,
                         17, 0x21, 0, 1, 1, 0x25, 0x81, 0x14, 0, 0, 0, 0, 0x13, 1, 8, 0, 0,
                         7, 5, 0x81, 3, 0x20, 0, 4,
                         7, 5, 0x01, 3, 0x20, 0, 8]
    let headset: [UInt8] = [9, 4, 1, 0, 2, 0xff, 0x5d, 0x03, 0,
                            7, 5, 0x82, 3, 0x20, 0, 2,
                            7, 5, 0x02, 3, 0x20, 0, 4]
    let expected = XUSBInterface(configuration: 1, number: 0, input: 0x81, output: 0x01)
    try require(findXUSBInterface(in: config(xusb + headset)) == expected, "standard wired descriptor")
    try require(findXUSBInterface(in: config(headset + xusb)) == expected, "XUSB interface after another interface")
    try require(findXUSBInterface(in: config(xusb + headset), number: 0) == expected, "interface number filter")
    try require(findXUSBInterface(in: config(headset)) == nil, "non-input XUSB protocol")
    try require(findXUSBInterface(in: config(Array(xusb.prefix(9)) + headset)) == nil, "XUSB interface without endpoints")
    for length in 0..<config(xusb).count {
        _ = findXUSBInterface(in: Array(config(xusb).prefix(length)))
    }
    var noOutput = xusb
    noOutput.removeLast(7)
    try require(findXUSBInterface(in: config(noOutput))?.output == nil, "input-only interface")
    print("PASS: XUSB descriptor parsing, interface selection, and truncated descriptors.")
}

@main
enum Main {
    static func main() throws {
        switch CommandLine.arguments.dropFirst().first {
        case "self-test":
            try selfTest()
        case "monitor":
            setvbuf(stdout, nil, _IOLBF, 0)
            print("Watching for wired Xbox 360 controllers. Ctrl-C stops.")
            let bridge = MainActor.assumeIsolated { Bridge(log: { print($0) }) }
            withExtendedLifetime(bridge) { dispatchMain() }
        default:
            KingOfDriversApp.main()
        }
    }
}
