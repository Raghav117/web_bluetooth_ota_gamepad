import 'dart:async' show StreamSubscription;
import 'dart:convert' show utf8;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class CommandScreen extends StatefulWidget {
  // We receive the connected device from the Firmware Updater screen.
  final BluetoothDevice device;

  const CommandScreen({super.key, required this.device});

  @override
  State<CommandScreen> createState() => _CommandScreenState();
}

class _CommandScreenState extends State<CommandScreen> {
  // The specific UUID for sending commands, as per your request.
  static const String commandCharacteristicUuidString =
      "66443773-D481-49B0-BE32-8CE24AC0F09C";
  final Guid commandCharacteristicUuid = Guid(commandCharacteristicUuidString);

  BluetoothCharacteristic? _commandCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  String _statusMessage = "Initializing...";
  String _lastCommand = "None";
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    // When the screen loads, immediately start looking for the required characteristic.
    _findCommandCharacteristic();

    // Listen to connection state changes
    _connectionStateSubscription = widget.device.connectionState.listen((
      state,
    ) {
      if (state == BluetoothConnectionState.disconnected) {
        setState(() {
          _isReady = false;
          _statusMessage =
              "❌ Device has disconnected. Please go back and reconnect.";
        });
      }
    });
  }

  @override
  void dispose() {
    // Clean up the listener when the screen is closed.
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _findCommandCharacteristic() async {
    setState(() {
      _statusMessage = "Discovering services to find command characteristic...";
      _isReady = false;
    });

    try {
      if (!widget.device.isConnected) {
        setState(() {
          _statusMessage = "❌ Error: Device is disconnected.";
        });
        return;
      }

      List<BluetoothService> services = await widget.device.discoverServices();
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.uuid == commandCharacteristicUuid) {
            setState(() {
              _commandCharacteristic = char;
              _isReady = true;
              _statusMessage = "✅ Ready! Press any key to send a command.";
            });
            print("✅ Command characteristic found!");
            return; // Exit the function once we've found our characteristic
          }
        }
      }

      // This part runs if the characteristic is not found after checking all services.
      setState(() {
        _statusMessage =
            "⚠️ Error: Command characteristic not found on this device.\nCheck the ESP32 UUIDs.";
      });
      print(
        "⚠️ Command characteristic UUID ${commandCharacteristicUuid.toString()} not found.",
      );
    } catch (e) {
      setState(() {
        _statusMessage = "❌ Error finding services: ${e.toString()}";
      });
      print("❌ Error during characteristic discovery: $e");
    }
  }

  /// Sends a single character command over BLE.
  Future<void> _sendCommand(String key) async {
    if (_commandCharacteristic == null || !_isReady) {
      print("Cannot send command: Characteristic not ready or not found.");
      return;
    }

    try {
      // Encode the key string into bytes and write it.
      await _commandCharacteristic!.write(
        utf8.encode(key),
        withoutResponse: true, // Use `writeWithoutResponse` for higher speed.
      );
      print("Sent key command: $key");
      setState(() {
        _lastCommand = key; // Update the UI to show the last command sent.
      });
    } catch (e) {
      print("❌ Error sending command: ${e.toString()}");
      setState(() {
        _statusMessage = "❌ Error sending command: ${e.toString()}";
        _isReady = false; // Set state to not ready if a write fails.
      });
    }
  }

  /// The keyboard event handler that triggers the command.
  void _handleKey(RawKeyEvent event) {
    // We only care about key down events to avoid sending the same command twice.
    if (event is RawKeyDownEvent) {
      // `event.logicalKey.keyLabel` gives us the character representation (e.g., "a", "W", "5", "F5").
      final String key = event.logicalKey.keyLabel;
      _sendCommand(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A FocusNode is required for the RawKeyboardListener to capture events.
    final FocusNode focusNode = FocusNode();
    // Request focus so it starts listening as soon as the screen is visible.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => focusNode.requestFocus(),
    );

    return RawKeyboardListener(
      focusNode: focusNode,
      onKey: _isReady
          ? _handleKey
          : null, // Only listen for keys when the characteristic is ready.
      child: Scaffold(
        appBar: AppBar(title: const Text('Keyboard Controller')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Controlling: ${widget.device.platformName}",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Icon(
                  _isReady
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: _isReady ? Colors.green : Colors.red,
                  size: 60,
                ),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 40),
                Text(
                  'Last Command Sent:',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _lastCommand,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                if (!_isReady)
                  ElevatedButton.icon(
                    onPressed: _findCommandCharacteristic,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Retry Search"),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
