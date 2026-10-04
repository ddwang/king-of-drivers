import Foundation

struct Gamepad: Equatable {
    var buttons: UInt16 = 0
    var leftTrigger: UInt8 = 0
    var rightTrigger: UInt8 = 0
    var leftX: Int16 = 0
    var leftY: Int16 = 0
    var rightX: Int16 = 0
    var rightY: Int16 = 0

    init() {}

    init?(packet: [UInt8]) {
        guard packet.count == 20, packet[0] == 0, packet[1] == 20 else { return nil }
        func word(at offset: Int) -> UInt16 {
            UInt16(packet[offset]) | UInt16(packet[offset + 1]) << 8
        }
        buttons = word(at: 2)
        leftTrigger = packet[4]
        rightTrigger = packet[5]
        leftX = Int16(bitPattern: word(at: 6))
        leftY = Int16(bitPattern: word(at: 8))
        rightX = Int16(bitPattern: word(at: 10))
        rightY = Int16(bitPattern: word(at: 12))
    }

    func pressed(_ bit: Int) -> Bool {
        buttons & (1 << bit) != 0
    }

    var hat: UInt8 {
        let horizontal = (pressed(3) ? 1 : 0) - (pressed(2) ? 1 : 0)
        let vertical = (pressed(1) ? 1 : 0) - (pressed(0) ? 1 : 0)
        switch (horizontal, vertical) {
        case (0, -1): return 0
        case (1, -1): return 1
        case (1, 0): return 2
        case (1, 1): return 3
        case (0, 1): return 4
        case (-1, 1): return 5
        case (-1, 0): return 6
        case (-1, -1): return 7
        default: return 8
        }
    }

    var hidReport: Data {
        let orderedButtons = [12, 13, 14, 15, 8, 9, 5, 4, 6, 7, 10]
        var mapped: UInt16 = 0
        for (index, bit) in orderedButtons.enumerated() where pressed(bit) {
            mapped |= 1 << index
        }
        var bytes = [UInt8(truncatingIfNeeded: mapped), UInt8(mapped >> 8), hat]
        let axes = [Int(leftX), -Int(leftY), Int(rightX), -Int(rightY)]
        for axis in axes {
            let encoded = UInt16(bitPattern: Int16(clamping: axis))
            bytes += [UInt8(truncatingIfNeeded: encoded), UInt8(encoded >> 8)]
        }
        bytes += [leftTrigger, rightTrigger]
        return Data(bytes)
    }

    static let descriptor = Data([
        0x05, 0x01, 0x09, 0x05, 0xA1, 0x01,
        0x05, 0x09, 0x19, 0x01, 0x29, 0x0B,
        0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x0B, 0x81, 0x02,
        0x75, 0x01, 0x95, 0x05, 0x81, 0x03,
        0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07,
        0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14,
        0x75, 0x04, 0x95, 0x01, 0x81, 0x42,
        0x75, 0x04, 0x95, 0x01, 0x81, 0x03,
        0x65, 0x00, 0x35, 0x00, 0x45, 0x00,
        0x09, 0x30, 0x09, 0x31, 0x09, 0x33, 0x09, 0x34,
        0x16, 0x00, 0x80, 0x26, 0xFF, 0x7F,
        0x75, 0x10, 0x95, 0x04, 0x81, 0x02,
        0x09, 0x32, 0x09, 0x35, 0x15, 0x00, 0x26, 0xFF, 0x00,
        0x75, 0x08, 0x95, 0x02, 0x81, 0x02, 0xC0,
    ])

    var summary: String {
        String(format: "buttons=%04x LT=%3d RT=%3d LX=%6d LY=%6d RX=%6d RY=%6d",
               buttons, leftTrigger, rightTrigger, leftX, leftY, rightX, rightY)
    }
}
