#pragma once

#include <IOKit/IOKitLib.h>
#include <stdint.h>

// Thin wrappers over IOKit's IOUSBLib plug-in API. The App Sandbox's
// com.apple.security.device.usb entitlement allows these user clients but
// denies the IOUSBHost framework's clients.

typedef struct USBDevice USBDevice;
typedef struct USBInterface USBInterface;

USBDevice *usb_device_open(io_service_t service, IOReturn *error);
uint8_t usb_device_configuration(USBDevice *device);
IOReturn usb_device_descriptor(USBDevice *device, uint8_t index, const uint8_t **bytes, uint16_t *length);
IOReturn usb_device_configure(USBDevice *device, uint8_t value);
void usb_device_close(USBDevice *device);

// Opens the interface and selects its first interrupt IN and OUT pipes.
USBInterface *usb_interface_open(io_service_t service, IOReturn *error);
// Blocks until a report arrives. On entry, *size is the buffer capacity.
IOReturn usb_interface_read(USBInterface *interface, uint8_t *buffer, uint32_t *size);
IOReturn usb_interface_write(USBInterface *interface, uint8_t *buffer, uint32_t size);
void usb_interface_close(USBInterface *interface);
