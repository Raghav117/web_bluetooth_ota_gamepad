# ESP32 BLE Firmware Updater

A Flutter Web application for updating ESP32 firmware over Bluetooth Low Energy (BLE).

## Features

- 🔍 **BLE Device Scanning**: Automatically scans for ESP32 devices advertising the specified service UUID
- 📁 **File Selection**: Select `.bin` firmware files from local storage
- 📤 **Chunked Upload**: Uploads firmware in 512-byte chunks with configurable delays
- 📊 **Progress Tracking**: Real-time upload progress with percentage and byte count
- 🌐 **Web Compatible**: Works in modern web browsers with Web Bluetooth API support

## BLE Configuration

The app is configured to work with ESP32 devices that advertise the following BLE service:

- **Service UUID**: `12345678-1234-5678-1234-56789abcdef0`
- **Characteristic UUID**: `12345678-1234-5678-1234-56789abcdef1` (write-only)

## Setup Instructions

### 1. Install Dependencies

```bash
flutter pub get
```

### 2. Run the Application

For web development:
```bash
flutter run -d chrome
```

For production build:
```bash
flutter build web
```

### 3. ESP32 Setup

Your ESP32 device should:

1. **Advertise the correct service UUID**: `12345678-1234-5678-1234-56789abcdef0`
2. **Implement the write characteristic**: `12345678-1234-5678-1234-56789abcdef1`
3. **Handle incoming data chunks**: Process 512-byte chunks and write to flash memory

Example ESP32 BLE service setup (Arduino):
```cpp
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SERVICE_UUID        "12345678-1234-5678-1234-56789abcdef0"
#define CHARACTERISTIC_UUID "12345678-1234-5678-1234-56789abcdef1"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        // Process firmware chunk
        // Write to flash memory
        // Handle firmware update logic
      }
    }
};

void setup() {
  Serial.begin(115200);
  
  BLEDevice::init("ESP32_Firmware_Updater");
  pServer = BLEDevice::createServer();
  
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_WRITE
                    );
                    
  pCharacteristic->setCallbacks(new MyCallbacks());
  
  pService->start();
  
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);
  BLEDevice::startAdvertising();
  
  Serial.println("Waiting for client connection...");
}
```

## Web BLE Limitations & Compatibility

### ⚠️ Important Limitations

1. **HTTPS Required**: Web Bluetooth API only works over HTTPS or localhost
2. **Browser Support**: Only supported in Chrome, Edge, and Opera
3. **User Interaction**: BLE operations must be triggered by user interaction (button click)
4. **Permission Required**: Users must explicitly grant Bluetooth permissions
5. **Device Filtering**: Some browsers may filter BLE devices based on service UUIDs

### Supported Browsers

- ✅ Chrome 56+
- ✅ Edge 79+
- ✅ Opera 43+
- ❌ Firefox (no Web Bluetooth support)
- ❌ Safari (limited Web Bluetooth support)

### HTTPS Requirements

For production deployment, you must serve the app over HTTPS:

```bash
# Development with HTTPS
flutter run -d chrome --web-port 8080 --web-hostname 0.0.0.0

# Production build
flutter build web
# Serve with HTTPS-enabled server
```

## Usage Guide

### 1. Start the Application

1. Open the app in a supported browser
2. Grant Bluetooth permissions when prompted
3. The app will show "Bluetooth is ready" when initialized

### 2. Scan for Devices

1. Click "Scan for ESP32" button
2. The app will scan for 10 seconds
3. Found devices will appear in the list
4. Only devices advertising the correct service UUID will be shown

### 3. Connect to Device

1. Click "Connect" next to your ESP32 device
2. Wait for connection confirmation
3. The app will automatically discover the firmware update characteristic

### 4. Select Firmware File

1. Click "Select .bin File"
2. Choose your firmware file (`.bin` format)
3. File size will be displayed

### 5. Upload Firmware

1. Click "Upload Firmware" button
2. Monitor progress in real-time
3. Wait for completion confirmation

## Configuration

### Chunk Size and Timing

You can modify these constants in `lib/main.dart`:

```dart
static const int chunkSize = 512;           // Bytes per chunk
static const int delayBetweenChunks = 20;   // Milliseconds between chunks
```

### Service UUIDs

Update these constants to match your ESP32 configuration:

```dart
static const String serviceUuid = "12345678-1234-5678-1234-56789abcdef0";
static const String characteristicUuid = "12345678-1234-5678-1234-56789abcdef1";
```

## Troubleshooting

### Common Issues

1. **"Bluetooth is not available"**
   - Ensure Bluetooth is enabled on your device
   - Check browser compatibility
   - Try refreshing the page

2. **"No devices found"**
   - Verify ESP32 is advertising the correct service UUID
   - Check if ESP32 is in range and discoverable
   - Try restarting the ESP32

3. **"Connection failed"**
   - Ensure ESP32 is not connected to another device
   - Check if ESP32 is in pairing mode
   - Verify service/characteristic UUIDs match

4. **"Upload failed"**
   - Check ESP32 flash memory space
   - Verify ESP32 is processing chunks correctly
   - Try reducing chunk size or increasing delay

### Debug Information

Enable debug logging by adding this to your ESP32 code:
```cpp
void onWrite(BLECharacteristic *pCharacteristic) {
  std::string value = pCharacteristic->getValue();
  Serial.printf("Received %d bytes\n", value.length());
  // Process firmware chunk
}
```

## Security Considerations

- **HTTPS Required**: Always serve over HTTPS in production
- **User Permissions**: BLE access requires explicit user consent
- **Data Validation**: ESP32 should validate incoming firmware data
- **Flash Protection**: Implement proper flash memory protection on ESP32

## Dependencies

- `flutter_blue_plus`: ^1.31.8 - BLE functionality
- `file_picker`: ^8.0.0+1 - File selection for web
- `http`: ^1.2.0 - Web compatibility

## License

This project is provided as-is for educational and development purposes.
# web_bluetooth_ota_gamepad
