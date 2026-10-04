#include "usblib.h"
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdlib.h>

struct USBDevice {
    IOUSBDeviceInterface650 **device;
};

struct USBInterface {
    IOUSBInterfaceInterface650 **interface;
    UInt8 input;
    UInt8 output;
};

static void *query(io_service_t service, CFUUIDRef type, CFUUIDRef interfaceID, IOReturn *error) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    *error = IOCreatePlugInInterfaceForService(service, type, kIOCFPlugInInterfaceID, &plugin, &score);
    if (*error != kIOReturnSuccess || !plugin) {
        if (*error == kIOReturnSuccess) *error = kIOReturnError;
        return NULL;
    }
    void *result = NULL;
    HRESULT status = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(interfaceID), &result);
    IODestroyPlugInInterface(plugin);
    if (status != S_OK || !result) {
        *error = kIOReturnUnsupported;
        return NULL;
    }
    return result;
}

USBDevice *usb_device_open(io_service_t service, IOReturn *error) {
    IOUSBDeviceInterface650 **device = query(service, kIOUSBDeviceUserClientTypeID, kIOUSBDeviceInterfaceID650, error);
    if (!device) return NULL;
    *error = (*device)->USBDeviceOpen(device);
    if (*error != kIOReturnSuccess) {
        (*device)->Release(device);
        return NULL;
    }
    USBDevice *result = malloc(sizeof(*result));
    if (!result) {
        *error = kIOReturnNoMemory;
        (*device)->USBDeviceClose(device);
        (*device)->Release(device);
        return NULL;
    }
    result->device = device;
    return result;
}

uint8_t usb_device_configuration(USBDevice *device) {
    UInt8 value = 0;
    return (*device->device)->GetConfiguration(device->device, &value) == kIOReturnSuccess ? value : 0;
}

IOReturn usb_device_descriptor(USBDevice *device, uint8_t index, const uint8_t **bytes, uint16_t *length) {
    IOUSBConfigurationDescriptorPtr descriptor = NULL;
    IOReturn result = (*device->device)->GetConfigurationDescriptorPtr(device->device, index, &descriptor);
    if (result != kIOReturnSuccess) return result;
    *bytes = (const uint8_t *)descriptor;
    *length = USBToHostWord(descriptor->wTotalLength);
    return kIOReturnSuccess;
}

IOReturn usb_device_configure(USBDevice *device, uint8_t value) {
    return (*device->device)->SetConfiguration(device->device, value);
}

void usb_device_close(USBDevice *device) {
    (*device->device)->USBDeviceClose(device->device);
    (*device->device)->Release(device->device);
    free(device);
}

USBInterface *usb_interface_open(io_service_t service, IOReturn *error) {
    IOUSBInterfaceInterface650 **interface =
        query(service, kIOUSBInterfaceUserClientTypeID, kIOUSBInterfaceInterfaceID650, error);
    if (!interface) return NULL;
    *error = (*interface)->USBInterfaceOpen(interface);
    if (*error != kIOReturnSuccess) {
        (*interface)->Release(interface);
        return NULL;
    }
    USBInterface *result = calloc(1, sizeof(*result));
    if (!result) {
        *error = kIOReturnNoMemory;
        (*interface)->USBInterfaceClose(interface);
        (*interface)->Release(interface);
        return NULL;
    }
    result->interface = interface;
    UInt8 endpoints = 0;
    (*interface)->GetNumEndpoints(interface, &endpoints);
    for (unsigned pipe = 1; pipe <= endpoints; pipe++) {
        UInt8 direction, number, type, interval;
        UInt16 maxPacketSize;
        if ((*interface)->GetPipeProperties(interface, (UInt8)pipe, &direction, &number, &type, &maxPacketSize, &interval) !=
                kIOReturnSuccess || type != kUSBInterrupt) continue;
        if (direction == kUSBIn && !result->input) result->input = (UInt8)pipe;
        if (direction == kUSBOut && !result->output) result->output = (UInt8)pipe;
    }
    if (!result->input) {
        *error = kIOReturnNotFound;
        usb_interface_close(result);
        return NULL;
    }
    return result;
}

IOReturn usb_interface_read(USBInterface *interface, uint8_t *buffer, uint32_t *size) {
    return (*interface->interface)->ReadPipe(interface->interface, interface->input, buffer, size);
}

IOReturn usb_interface_write(USBInterface *interface, uint8_t *buffer, uint32_t size) {
    if (!interface->output) return kIOReturnNotFound;
    return (*interface->interface)->WritePipe(interface->interface, interface->output, buffer, size);
}

void usb_interface_close(USBInterface *interface) {
    (*interface->interface)->USBInterfaceClose(interface->interface);
    (*interface->interface)->Release(interface->interface);
    free(interface);
}
