import 'dart:async' show StreamSubscription, Timer;
import 'dart:convert' show utf8;
import 'package:flutter/material.dart';
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

  Timer? _commandTimer;
  String? _activeCommand;

  // Speed control variables
  double _speedValue = 1.0; // Default speed value
  Timer? _speedDebouncer;
  String _lastSpeedCommand = "SPEED_100";

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
    _commandTimer?.cancel();
    _speedDebouncer?.cancel();
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
              _statusMessage = "✅ Ready! Use the gamepad to send commands.";
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

  void _handlePress(String command) {
    if (_activeCommand != null || !_isReady)
      return; // Prevent multiple commands

    print("Sent direction command: $command");

    // Start sending the command immediately
    _sendCommand(command);

    setState(() {
      _activeCommand = command;
    });
  }

  /// Handles the release event of a button.
  void _handleRelease() {
    if (_activeCommand == null) return; // Nothing to release

    _commandTimer?.cancel();
    _sendCommand("STOP"); // Tell the car to stop moving
    setState(() {
      _activeCommand = null;
    });
  }

  /// Handles speed slider changes with debouncing
  void _onSpeedChanged(double value) {
    setState(() {
      _speedValue = value;
    });

    // Cancel previous debouncer
    _speedDebouncer?.cancel();

    // Start new debouncer
    _speedDebouncer = Timer(const Duration(milliseconds: 500), () {
      if (_isReady) {
        int speedInt = value.round();
        String speedCommand = "SPEED_${speedInt + 0}";
        _sendCommand(speedCommand);
        setState(() {
          _lastSpeedCommand = speedCommand;
        });
        print("Sent speed command: $speedCommand");
      }
    });
  }

  /// Sends a directional command over BLE.
  Future<void> _sendCommand(String direction) async {
    if (_commandCharacteristic == null || !_isReady) {
      print("Cannot send command: Characteristic not ready or not found.");
      return;
    }

    try {
      // Encode the direction string into bytes and write it.
      await _commandCharacteristic!.write(
        utf8.encode(direction),
        withoutResponse: false, // Use `writeWithoutResponse` for higher speed.
      );
      print("Sent direction command: $direction");
      setState(() {
        _lastCommand =
            direction; // Update the UI to show the last command sent.
      });
    } catch (e) {
      print("❌ Error sending command: ${e.toString()}");
      setState(() {
        _statusMessage = "❌ Error sending command: ${e.toString()}";
        _isReady = false; // Set state to not ready if a write fails.
      });
    }
  }

  /// Creates a directional button for the gamepad
  Widget _buildDirectionButton({
    required String direction,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 80,
      height: 80,
      child: GestureDetector(
        onTapDown: (_) => _handlePress(direction),
        onTapUp: (_) => _handleRelease(),
        onTapCancel: () =>
            _handleRelease(), // Also stop if the gesture is canceled

        child: Icon(icon, size: 32),
      ),
    );
  }

  /// Creates the speed control widget
  Widget _buildSpeedControl() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Speed Control',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_speedValue.round()}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).colorScheme.primary,
              inactiveTrackColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.3),
              thumbColor: Theme.of(context).colorScheme.primary,
              overlayColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: (_speedValue),
              min: 1.0,
              max: 255.0,
              divisions: 255, // 255 values (1-255)
              onChanged: _isReady ? _onSpeedChanged : null,
              label: '${(_speedValue).round()}',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Slow', style: Theme.of(context).textTheme.bodySmall),
              Text('Fast', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 12),
          // Text(
          //   'Last Speed Command: $_lastSpeedCommand',
          //   style: Theme.of(
          //     context,
          //   ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          // ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gamepad Controller'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ListView(
            children: [
              // Device info
              Text(
                "Controlling: ${widget.device.platformName}",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),

              // Status indicator
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

              // Speed Control Section
              _buildSpeedControl(),
              const SizedBox(height: 24),

              // Gamepad
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Directional Controls',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Up button
                    _buildDirectionButton(
                      direction: 'UP',
                      icon: Icons.keyboard_arrow_up,
                      color: Colors.blue,
                      onPressed: () => _sendCommand('UP'),
                    ),
                    const SizedBox(height: 16),

                    // Middle row with left and right buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildDirectionButton(
                          direction: 'LEFT',
                          icon: Icons.keyboard_arrow_left,
                          color: Colors.orange,
                          onPressed: () => _sendCommand('LEFT'),
                        ),
                        const SizedBox(width: 32),
                        _buildDirectionButton(
                          direction: 'RIGHT',
                          icon: Icons.keyboard_arrow_right,
                          color: Colors.orange,
                          onPressed: () => _sendCommand('RIGHT'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Down button
                    _buildDirectionButton(
                      direction: 'DOWN',
                      icon: Icons.keyboard_arrow_down,
                      color: Colors.blue,
                      onPressed: () => _sendCommand('DOWN'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Last command display
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
              const SizedBox(height: 24),

              // Retry button if not ready
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
    );
  }
}
