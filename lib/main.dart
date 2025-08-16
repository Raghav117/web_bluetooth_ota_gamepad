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
      title: 'ESP32 BLE CAR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
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
  static const String serviceUuid = "88881231-A981-99B0-BA32-1BD54A51B97C";
  static const String writeCharacteristicUuid =
      "88881232-A981-99B0-BA32-1BD54A51B97C";
  // NOTE: The notify characteristic has been removed as it's not in the Arduino code.

  final Guid myServiceUuid = Guid(serviceUuid);

  // State variables
  bool _isScanning = false;
  bool _isConnected = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = "Initializing Bluetooth...";
  BluetoothAdapterState _bluetoothState = BluetoothAdapterState.unknown;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  // All notify-related variables have been removed.

  List<ScanResult> _scanResults = [];
  Uint8List? _firmwareData;
  String? _selectedFileName;
  List<BluetoothService> _discoveredServices = [];

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _otaSectionKey = GlobalKey();
  bool _showFirmwareSection = false;

  @override
  void initState() {
    super.initState();
    _initializeBLE();
    _checkBluetoothSupport();
  }

  void _checkBluetoothSupport() async {
    try {
      // Check if Bluetooth is supported
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState == BluetoothAdapterState.unavailable) {
        setState(() {
          _bluetoothState = BluetoothAdapterState.unavailable;
          _statusMessage = "❌ Bluetooth is not supported on this device.";
        });
      }
    } catch (e) {
      print("Error checking Bluetooth support: $e");
    }
  }

  @override
  void dispose() {
    // Disconnect from any device when the widget is removed.
    _disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeBLE() {
    // Listen to Bluetooth adapter state changes
    FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _bluetoothState = state;
        switch (state) {
          case BluetoothAdapterState.on:
            _statusMessage = "Bluetooth is ready";
            break;
          case BluetoothAdapterState.off:
            _statusMessage =
                "❌ Bluetooth is turned off. Please enable Bluetooth in settings.";
            break;
          case BluetoothAdapterState.turningOn:
            _statusMessage = "Bluetooth is turning on...";
            break;
          case BluetoothAdapterState.turningOff:
            _statusMessage = "Bluetooth is turning off...";
            break;
          case BluetoothAdapterState.unauthorized:
            _statusMessage =
                "❌ Bluetooth permission denied. Please grant Bluetooth permissions in settings.";
            break;
          case BluetoothAdapterState.unavailable:
            _statusMessage = "❌ Bluetooth is not supported on this device.";
            break;
          case BluetoothAdapterState.unknown:
            _statusMessage = "Bluetooth state unknown...";
            break;
        }
      });
    });
  }

  Future<void> _requestBluetoothPermissions() async {
    try {
      // Try to turn on Bluetooth and request permissions
      await FlutterBluePlus.turnOn();
    } catch (e) {
      print("Error requesting Bluetooth permissions: $e");
      setState(() {
        _statusMessage =
            "❌ Failed to enable Bluetooth: $e\nPlease enable Bluetooth in your device settings.";
      });
    }
  }

  Future<void> _openBluetoothSettings() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      // If we can't turn on Bluetooth programmatically, show a dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Bluetooth Required'),
            content: const Text(
              'This app requires Bluetooth to be enabled. Please go to your device settings and turn on Bluetooth.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _startScan() async {
    // Check if Bluetooth is enabled before scanning
    if (_bluetoothState != BluetoothAdapterState.on) {
      setState(() {
        _statusMessage =
            "❌ Cannot scan: Bluetooth is not enabled. Current state: $_bluetoothState";
      });
      return;
    }

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

      // If the error is about Bluetooth being off, update the state
      if (e.toString().contains("Bluetooth must be turned on")) {
        setState(() {
          _bluetoothState = BluetoothAdapterState.off;
          _statusMessage =
              "❌ Bluetooth is turned off. Please enable Bluetooth in settings.";
        });
      } else if (e.toString().contains("permission") ||
          e.toString().contains("denied")) {
        setState(() {
          _bluetoothState = BluetoothAdapterState.unauthorized;
          _statusMessage =
              "❌ Bluetooth permission denied. Please grant Bluetooth permissions in settings.";
        });
      }
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
      _showFirmwareSection = false;
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
      // await Future.delayed(const Duration(milliseconds: 10));

      // Step 2: Send file size
      ByteData byteData = ByteData(4)
        ..setUint32(0, _firmwareData!.length, Endian.little);
      await _writeCharacteristic!.write(
        byteData.buffer.asUint8List(),
        withoutResponse: false,
      );
      // await Future.delayed(const Duration(milliseconds: 10));

      // await Future.delayed(const Duration(milliseconds: 0));

      // Step 3: Send firmware data in chunks
      int chunkSize = 247 - 3;
      for (int i = 0; i < _firmwareData!.length; i += chunkSize) {
        int end = (i + chunkSize > _firmwareData!.length)
            ? _firmwareData!.length
            : i + chunkSize;
        print(i);
        print(end);
        print(chunkSize);
        List<int> chunk = _firmwareData!.sublist(i, end);
        await _writeCharacteristic!.write(chunk, withoutResponse: true);
        await Future.delayed(const Duration(milliseconds: 50));

        // await Future.delayed(
        //   const Duration(milliseconds: 10),
        // ); // Small delay to prevent buffer overflow

        setState(() {
          _uploadProgress = (i + chunk.length) / _firmwareData!.length;
          _statusMessage =
              "Uploading: ${(_uploadProgress * 100).toStringAsFixed(0)}%";
        });
      }

      // await Future.delayed(const Duration(milliseconds: 10));

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
        controller: _scrollController,
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
                    Row(
                      children: [
                        Icon(
                          _bluetoothState == BluetoothAdapterState.on
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color: _bluetoothState == BluetoothAdapterState.on
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_statusMessage)),
                      ],
                    ),
                    if (_bluetoothState != BluetoothAdapterState.on) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _openBluetoothSettings,
                        icon: const Icon(Icons.bluetooth),
                        label: const Text('Turn On Bluetooth'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
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
                    if (_bluetoothState != BluetoothAdapterState.on) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Bluetooth must be enabled to scan for devices',
                                style: TextStyle(color: Colors.orange[800]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                (_isScanning ||
                                    _isConnected ||
                                    _bluetoothState != BluetoothAdapterState.on)
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

            // CTAs shown only after connection
            if (_isConnected) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CommandScreen(device: _connectedDevice!),
                          ),
                        );
                      },
                      icon: const Icon(Icons.sports_esports),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Text('Gamepad Controller'),
                      ),
                      style: ElevatedButton.styleFrom(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        minimumSize: const Size.fromHeight(64),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _showFirmwareSection = true;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final ctx = _otaSectionKey.currentContext;
                          if (ctx != null) {
                            Scrollable.ensureVisible(
                              ctx,
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                            );
                          }
                        });
                      },
                      icon: const Icon(Icons.system_update_alt),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Text('Firmware Update'),
                      ),
                      style: ElevatedButton.styleFrom(
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        minimumSize: const Size.fromHeight(64),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // File Selection + Upload shows only after Firmware Update CTA
            if (_showFirmwareSection) bluetooth_ota_widget(context),
          ],
        ),
      ),
    );
  }

  Column bluetooth_ota_widget(BuildContext context) {
    return Column(
      key: _otaSectionKey,
      children: [
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
                        (_firmwareData == null || !_isConnected || _isUploading)
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
    );
  }
}
