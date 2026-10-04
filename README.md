# King of Drivers 2026

King of Drivers 2026 is a macOS menu bar app that makes wired Xbox 360–protocol
USB controllers work on Apple Silicon Macs. It reads each controller over USB
and presents it to games as a standard HID gamepad.

macOS has no driver for these controllers, and the older 360Controller kernel
extension doesn't support Apple Silicon. Many third-party pads and arcade
sticks use this protocol, including models from Mad Catz, PDP, and PowerA.

The app runs in the App Sandbox and uses no kernel extension, DriverKit
extension, or Accessibility access.

## Status

King of Drivers 2026 is in development. The virtual gamepad is waiting on
Apple's `com.apple.developer.hid.virtual.device` entitlement. Until Apple
grants it, the app reads controllers but can't present them to games. In that
case, the menu shows "Virtual gamepad unavailable in this build".

| Part | State |
| --- | --- |
| USB input through IOKit's IOUSBLib, inside the App Sandbox | Works. Tested on macOS 27 with a Mad Catz BrawlPad (`1bad:f02a`): D-pad and diagonals, A/B/X/Y, LB/RB, and both triggers. |
| Hot-plug | Works. Unplugging and replugging disconnects and reconnects the controller. |
| Any wired controller with an XUSB interface (class `ff/5d/01`) | Built. Only the BrawlPad has been tested. |
| Player LEDs for up to 4 controllers | Works. Confirmed on the BrawlPad for player 1. |
| Virtual HID gamepad per controller, through CoreHID | Waiting on Apple's entitlement. |
| Open at login | Built. Not yet tested. |

The Xbox 360 wireless receiver and third-party Xbox One controllers use other
protocols and aren't supported yet.

## Requirements

- An Apple Silicon Mac with macOS 26 or later
- Xcode, to build the app. The Command Line Tools alone lack the SwiftUI macro
  plugin that the build needs.

## Build and test

To build the app and run the self-test, run:

```sh
make check app
```

This signs the app ad hoc. To sign with your own certificate, pass its SHA-1
hash from `security find-identity -v -p codesigning`:

```sh
make app SIGN=<certificate-sha1>
```

To print controller connections and input changes from the command line, run:

```sh
"./build/King of Drivers 2026.app/Contents/MacOS/KingOfDrivers" monitor
```

To start the menu bar app, run:

```sh
open "build/King of Drivers 2026.app"
```

Only one app can claim a controller at a time. If King of Drivers 2026 reports
that a controller is in use, quit the other app. Then unplug the controller and
plug it back in.

## How it works

1. `usblib.c` wraps IOKit's IOUSBLib plug-in API. The sandbox's
   `com.apple.security.device.usb` entitlement allows IOUSBLib's user clients
   but denies the newer IOUSBHost framework's clients.
2. `USBWatcher` watches IOKit for USB devices and interfaces, then filters
   them in code. USB matching rules require a vendor ID for vendor-specific
   classes, so class-only matching dictionaries don't work.
3. Some controllers connect without an active USB configuration. In that case,
   `configureIfXUSB` selects the configuration that contains the XUSB
   interface. It closes other devices without changing them.
4. For each XUSB interface, `Controller` claims the interface, sets the player
   LED, and reads 20-byte input reports on a dedicated thread.
5. `Bridge` gives each controller the lowest free player number. It forwards
   each decoded `Gamepad` state to that controller's `HIDVirtualDevice`.

## References

- [IOUSBLib](https://developer.apple.com/documentation/iokit/iousblib_h)
- [CoreHID virtual devices](https://developer.apple.com/documentation/corehid/creatingvirtualdevices)
- [HIDVirtualDevice and the Mac App Store](https://developer.apple.com/forums/thread/822647)
- [CoreHID or DriverKit for a virtual gamepad](https://developer.apple.com/forums/thread/845599)
