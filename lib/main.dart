import 'dart:convert' show utf8;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:async';

import 'package:research/views/command_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 BLE Firmware Updater',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const FirmwareUpdaterPage(),
    );
  }
}

class FirmwareUpdaterPage extends StatefulWidget {
  const FirmwareUpdaterPage({super.key});

  @override
  State<FirmwareUpdaterPage> createState() => _FirmwareUpdaterPageState();
}

class _FirmwareUpdaterPageState extends State<FirmwareUpdaterPage> {
  // BLE Configuration to match the provided ESP32 code
  // The ESP32 code uses ONE characteristic for everything.
  static const String serviceUuid = "66443771-D481-49B0-BE32-8CE24AC0F09C";
  static const String writeCharacteristicUuid =
      "66443772-D481-49B0-BE32-8CE24AC0F09C";
  // NOTE: The notify characteristic has been removed as it's not in the Arduino code.

  final Guid myServiceUuid = Guid(serviceUuid);

  // State variables
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = "Ready to scan for BLE devices";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  // All notify-related variables have been removed.

  List<ScanResult> _scanResults = [];
  Uint8List? _firmwareData;
  String? _selectedFileName;
  List<BluetoothService> _discoveredServices = [];

  @override
  void initState() {
    super.initState();
    _initializeBLE();
  }

  @override
  void dispose() {
    // Disconnect from any device when the widget is removed.
    _disconnect();
    super.dispose();
  }

  void _initializeBLE() {
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        setState(() {
          _statusMessage = "Bluetooth is ready";
        });
      } else {
        setState(() {
          _statusMessage = "Bluetooth is not available: $state";
        });
      }
    });
  }

  Future<void> _startScan() async {
    // The scanning logic remains the same, it correctly filters by service UUID.
    try {
      setState(() {
        _isScanning = true;
        _scanResults.clear();
        _statusMessage = "Scanning for BLE devices...";
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        withServices: [myServiceUuid],
        androidUsesFineLocation: false,
      );

      FlutterBluePlus.scanResults.listen((results) {
        final uniqueResults = <String, ScanResult>{};
        for (var r in results) {
          uniqueResults[r.device.remoteId.toString()] = r;
        }
        setState(() {
          _scanResults = uniqueResults.values.toList();
        });
      });

      Timer(const Duration(seconds: 15), () {
        FlutterBluePlus.stopScan();
        setState(() {
          _isScanning = false;
          _statusMessage =
              "Scan completed. Found ${_scanResults.length} device(s)";
        });
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _statusMessage = "Error scanning: $e";
      });
      print("Scan error: $e");
    }
  }

  // MODIFIED: This function is simplified to work with the single characteristic.
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      setState(() {
        _statusMessage = "Connecting to ${device.platformName}...";
      });

      await device.connect(timeout: const Duration(seconds: 15));

      setState(() {
        _connectedDevice = device;
        _isConnected = true;
        _statusMessage = "Connected! Discovering services...";
      });

      List<BluetoothService> services = await device.discoverServices();
      _discoveredServices = services;
      setState(() {});

      BluetoothService? targetService;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          targetService = service;
          break;
        }
      }

      if (targetService != null) {
        // Find the single write characteristic
        for (var char in targetService.characteristics) {
          if (char.uuid.toString().toLowerCase() ==
              writeCharacteristicUuid.toLowerCase()) {
            _writeCharacteristic = char;
          }
        }

        if (_writeCharacteristic != null) {
          setState(() {
            _statusMessage =
                "✅ Found required characteristic! Ready to upload.";
          });
          // No need to subscribe to notifications, as the ESP32 doesn't send them.
        } else {
          setState(() {
            _statusMessage =
                "⚠️ Found service, but missing the required characteristic.";
          });
        }
      } else {
        setState(() {
          _statusMessage = "⚠️ Service UUID not found. Check ESP32 code.";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "❌ Connection failed: $e";
        _isConnected = false; // Ensure connection status is correct on failure
      });
      print("❌ Connection error: $e");
    }
  }

  // REMOVED: The _subscribeToNotifications function is no longer needed.

  // MODIFIED: This function is simplified.
  Future<void> _disconnect() async {
    await _connectedDevice?.disconnect();
    setState(() {
      _connectedDevice = null;
      _isConnected = false;
      _writeCharacteristic = null;
      _discoveredServices.clear();
      _statusMessage = "Disconnected from device";
    });
  }

  Future<void> _selectFirmwareFile() async {
    // This function is correct and requires no changes.
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
      );
      if (result != null) {
        setState(() {
          _selectedFileName = result.files.first.name;
          _firmwareData = result.files.first.bytes;
          _statusMessage = "Selected: ${result.files.first.name}";
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Error selecting file: $e";
      });
    }
  }

  Future<void> _uploadFirmware() async {
    // This upload logic is correct for the provided Arduino OTA protocol.
    if (_firmwareData == null ||
        _writeCharacteristic == null ||
        !_isConnected) {
      setState(() {
        _statusMessage =
            "❌ Error: Connect to a device and select a file first.";
      });
      return;
    }

    try {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
        _statusMessage = "🚀 Starting ESP32 OTA update...";
      });

      // Step 1: Send "OPEN" command
      await _writeCharacteristic!.write(
        utf8.encode("OPEN"),
        withoutResponse: false,
      );
      await Future.delayed(const Duration(milliseconds: 10));

      // Step 2: Send file size
      ByteData byteData = ByteData(4)
        ..setUint32(0, _firmwareData!.length, Endian.little);
      await _writeCharacteristic!.write(
        byteData.buffer.asUint8List(),
        withoutResponse: true,
      );
      await Future.delayed(const Duration(milliseconds: 10));

      // Step 3: Send firmware data in chunks
      int chunkSize = _connectedDevice!.mtuNow - 3;
      for (int i = 0; i < _firmwareData!.length; i += chunkSize) {
        int end = (i + chunkSize > _firmwareData!.length)
            ? _firmwareData!.length
            : i + chunkSize;
        List<int> chunk = _firmwareData!.sublist(i, end);
        await _writeCharacteristic!.write(chunk, withoutResponse: true);
        await Future.delayed(
          const Duration(milliseconds: 10),
        ); // Small delay to prevent buffer overflow

        setState(() {
          _uploadProgress = (i + chunk.length) / _firmwareData!.length;
          _statusMessage =
              "Uploading: ${(_uploadProgress * 100).toStringAsFixed(0)}%";
        });
      }

      await Future.delayed(const Duration(milliseconds: 10));

      // Step 4: Send "DONE" command
      await _writeCharacteristic!.write(
        utf8.encode("DONE"),
        withoutResponse: false,
      );

      setState(() {
        _statusMessage = "✅ Upload complete! Device will reboot.";
        _uploadProgress = 1.0;
      });
    } catch (e) {
      setState(() {
        _statusMessage = "❌ Error during upload: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  // REMOVED: sendCommand and handleKey are no longer needed as the ESP32 code doesn't support them.

  @override
  Widget build(BuildContext context) {
    // MODIFIED: The UI is simplified by removing the RawKeyboardListener and the ACK message display.
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 BLE Firmware Updater'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // This button will only appear when a device is connected.
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.keyboard_alt_outlined),
              tooltip: 'Keyboard Controller',
              onPressed: () {
                // When pressed, navigate to the CommandScreen, passing the
                // currently connected device.
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CommandScreen(device: _connectedDevice!),
                  ),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(_statusMessage),
                    if (_isConnected) ...[
                      const SizedBox(height: 8),
                      Text('Device: ${_connectedDevice!.platformName}'),
                      // The ACK message Text widget has been removed.
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Scan Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Discovery',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isScanning || _isConnected
                                ? null
                                : _startScan,
                            icon: _isScanning
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search),
                            label: Text(
                              _isScanning ? 'Scanning...' : 'Scan for Devices',
                            ),
                          ),
                        ),
                        if (_isConnected) ...[
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _disconnect,
                            icon: const Icon(Icons.bluetooth_disabled),
                            label: const Text('Disconnect'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_scanResults.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Found Devices:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ..._scanResults.map(
                        (result) => ListTile(
                          title: Text(
                            result.device.platformName.isNotEmpty
                                ? result.device.platformName
                                : 'Unknown Device',
                          ),
                          subtitle: Text(result.device.remoteId.toString()),
                          trailing: ElevatedButton(
                            onPressed: _isConnected
                                ? null
                                : () => _connectToDevice(result.device),
                            child: const Text('Connect'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File Selection Card - No changes needed
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Firmware File',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    if (_selectedFileName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'Selected: $_selectedFileName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : _selectFirmwareFile,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Select Firmware (.bin)'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Upload Card - No changes needed
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_firmwareData == null ||
                                !_isConnected ||
                                _isUploading)
                            ? null
                            : _uploadFirmware,
                        icon: _isUploading
                            ? const SizedBox.shrink()
                            : const Icon(Icons.upload_file),
                        label: Text(
                          _isUploading ? 'UPLOADING...' : 'Upload to ESP32',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (_isUploading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: _uploadProgress),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
