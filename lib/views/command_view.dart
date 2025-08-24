import 'dart:async' show StreamSubscription, Timer;
import 'dart:convert' show utf8;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:research/controllers/ultrasonic_controller.dart';
import 'package:research/controllers/infrared_controller.dart';
import 'package:research/views/ultrasonic_control.dart';
import 'package:research/views/infrared_control.dart';

// Motor configuration model
class MotorConfig {
  final String speed; // L, M, H
  final String direction; // CW, ACW

  MotorConfig({required this.speed, required this.direction});

  @override
  String toString() => '${speed}_$direction';
}

// Direction configuration model
class DirectionConfig {
  final MotorConfig leftMotor;
  final MotorConfig rightMotor;

  DirectionConfig({required this.leftMotor, required this.rightMotor});

  String toCommand() =>
      '${leftMotor.speed}_${rightMotor.speed}_${leftMotor.direction}_${rightMotor.direction}';
}

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
      "88881233-A981-99B0-BA32-1BD54A51B97C";
  final Guid commandCharacteristicUuid = Guid(commandCharacteristicUuidString);

  BluetoothCharacteristic? _commandCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  String _statusMessage = "Initializing...";
  String _lastCommand = "None";
  bool _isReady = false;

  Timer? _commandTimer;
  String? _activeCommand;

  // Motor configuration for each direction
  Map<String, DirectionConfig> _motorConfigs = {
    'UP': DirectionConfig(
      leftMotor: MotorConfig(speed: 'M', direction: 'CW'),
      rightMotor: MotorConfig(speed: 'M', direction: 'CW'),
    ),
    'DOWN': DirectionConfig(
      leftMotor: MotorConfig(speed: 'M', direction: 'ACW'),
      rightMotor: MotorConfig(speed: 'M', direction: 'ACW'),
    ),
    'LEFT': DirectionConfig(
      leftMotor: MotorConfig(speed: 'M', direction: 'ACW'),
      rightMotor: MotorConfig(speed: 'M', direction: 'CW'),
    ),
    'RIGHT': DirectionConfig(
      leftMotor: MotorConfig(speed: 'M', direction: 'CW'),
      rightMotor: MotorConfig(speed: 'M', direction: 'ACW'),
    ),
  };

  final UltrasonicController _ultrasonicController = UltrasonicController();
  final InfraredController _infraredController = InfraredController();

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
    _ultrasonicController.dispose();
    _infraredController.dispose();
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
    print("Sent direction command: $command");

    if (_activeCommand != null || !_isReady) {
      return; // Prevent multiple commands
    }

    // Send the command directly since it's already the motor command
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

  /// Shows the motor configuration dialog for all directions
  void _showMotorConfigDialog() {
    // Create temporary copies of all configurations
    Map<String, DirectionConfig> tempConfigs = Map.from(_motorConfigs);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                height: MediaQuery.of(context).size.height * 0.8,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Configure Motor Settings',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(),

                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: ['UP', 'DOWN', 'LEFT', 'RIGHT'].map((
                            direction,
                          ) {
                            DirectionConfig config = tempConfigs[direction]!;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ExpansionTile(
                                title: Row(
                                  children: [
                                    Icon(
                                      direction == 'UP'
                                          ? Icons.keyboard_arrow_up
                                          : direction == 'DOWN'
                                          ? Icons.keyboard_arrow_down
                                          : direction == 'LEFT'
                                          ? Icons.keyboard_arrow_left
                                          : Icons.keyboard_arrow_right,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$direction Direction',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      children: [
                                        // Left Motor Configuration
                                        Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Left Motor (LM)',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                ),
                                                const SizedBox(height: 8),

                                                // Speed selection
                                                Text(
                                                  'Speed:',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: ['L', 'M', 'H'].map((
                                                    speed,
                                                  ) {
                                                    return Expanded(
                                                      child: RadioListTile<String>(
                                                        title: Text(
                                                          speed,
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                        ),
                                                        value: speed,
                                                        groupValue: config
                                                            .leftMotor
                                                            .speed,
                                                        onChanged: (value) {
                                                          setState(() {
                                                            tempConfigs[direction] = DirectionConfig(
                                                              leftMotor: MotorConfig(
                                                                speed: value!,
                                                                direction: config
                                                                    .leftMotor
                                                                    .direction,
                                                              ),
                                                              rightMotor: config
                                                                  .rightMotor,
                                                            );
                                                          });
                                                        },
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        dense: true,
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),

                                                const SizedBox(height: 8),

                                                // Direction selection
                                                Text(
                                                  'Direction:',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: RadioListTile<String>(
                                                        title: const Text(
                                                          'CW',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        subtitle: const Text(
                                                          'Clockwise',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        value: 'CW',
                                                        groupValue: config
                                                            .leftMotor
                                                            .direction,
                                                        onChanged: (value) {
                                                          setState(() {
                                                            tempConfigs[direction] =
                                                                DirectionConfig(
                                                                  leftMotor: MotorConfig(
                                                                    speed: config
                                                                        .leftMotor
                                                                        .speed,
                                                                    direction:
                                                                        value!,
                                                                  ),
                                                                  rightMotor: config
                                                                      .rightMotor,
                                                                );
                                                          });
                                                        },
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        dense: true,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: RadioListTile<String>(
                                                        title: const Text(
                                                          'ACW',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        subtitle: const Text(
                                                          'Anti-clockwise',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        value: 'ACW',
                                                        groupValue: config
                                                            .leftMotor
                                                            .direction,
                                                        onChanged: (value) {
                                                          setState(() {
                                                            tempConfigs[direction] =
                                                                DirectionConfig(
                                                                  leftMotor: MotorConfig(
                                                                    speed: config
                                                                        .leftMotor
                                                                        .speed,
                                                                    direction:
                                                                        value!,
                                                                  ),
                                                                  rightMotor: config
                                                                      .rightMotor,
                                                                );
                                                          });
                                                        },
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        dense: true,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),

                                        const SizedBox(height: 12),

                                        // Right Motor Configuration
                                        Card(
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Right Motor (RM)',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                ),
                                                const SizedBox(height: 8),

                                                // Speed selection
                                                Text(
                                                  'Speed:',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: ['L', 'M', 'H'].map((
                                                    speed,
                                                  ) {
                                                    return Expanded(
                                                      child: RadioListTile<String>(
                                                        title: Text(
                                                          speed,
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                        ),
                                                        value: speed,
                                                        groupValue: config
                                                            .rightMotor
                                                            .speed,
                                                        onChanged: (value) {
                                                          setState(() {
                                                            tempConfigs[direction] = DirectionConfig(
                                                              leftMotor: config
                                                                  .leftMotor,
                                                              rightMotor: MotorConfig(
                                                                speed: value!,
                                                                direction: config
                                                                    .rightMotor
                                                                    .direction,
                                                              ),
                                                            );
                                                          });
                                                        },
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        dense: true,
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),

                                                const SizedBox(height: 8),

                                                // Direction selection
                                                Text(
                                                  'Direction:',
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.bodySmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: RadioListTile<String>(
                                                        title: const Text(
                                                          'CW',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        subtitle: const Text(
                                                          'Clockwise',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        value: 'CW',
                                                        groupValue: config
                                                            .rightMotor
                                                            .direction,
                                                        onChanged: (value) {
                                                          setState(() {
                                                            tempConfigs[direction] =
                                                                DirectionConfig(
                                                                  leftMotor: config
                                                                      .leftMotor,
                                                                  rightMotor: MotorConfig(
                                                                    speed: config
                                                                        .rightMotor
                                                                        .speed,
                                                                    direction:
                                                                        value!,
                                                                  ),
                                                                );
                                                          });
                                                        },
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        dense: true,
                                                      ),
                                                    ),
                                                    Expanded(
                                                      child: RadioListTile<String>(
                                                        title: const Text(
                                                          'ACW',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                        subtitle: const Text(
                                                          'Anti-clockwise',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        value: 'ACW',
                                                        groupValue: config
                                                            .rightMotor
                                                            .direction,
                                                        onChanged: (value) {
                                                          setState(() {
                                                            tempConfigs[direction] =
                                                                DirectionConfig(
                                                                  leftMotor: config
                                                                      .leftMotor,
                                                                  rightMotor: MotorConfig(
                                                                    speed: config
                                                                        .rightMotor
                                                                        .speed,
                                                                    direction:
                                                                        value!,
                                                                  ),
                                                                );
                                                          });
                                                        },
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        dense: true,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    // Actions
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              this.setState(() {
                                _motorConfigs = tempConfigs;
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Save All'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Creates a directional button for the gamepad
  Widget _buildDirectionButton({
    required String direction,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.07, // Responsive width
      height: MediaQuery.of(context).size.width * 0.07, // Square aspect ratio
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTapDown: (_) => _handlePress(direction),
          onTapUp: (_) => _handleRelease(),
          onTapCancel: () => _handleRelease(),
          child: Center(
            child: Icon(
              icon,
              size:
                  MediaQuery.of(context).size.width *
                  0.06, // Responsive icon size
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
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
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(
            MediaQuery.of(context).size.width * 0.04,
          ), // Responsive padding
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

              // Ultrasonic Control Section
              UltrasonicControl(
                controller: _ultrasonicController,
                onSendCommand: (command) {
                  // Only send when ready
                  if (_isReady) {
                    _sendCommand(command);
                  }
                },
              ),
              const SizedBox(height: 24),

              // Infrared Control Section
              InfraredControl(
                controller: _infraredController,
                onSendCommand: (command) {
                  if (_isReady) {
                    _sendCommand(command);
                  }
                },
              ),
              const SizedBox(height: 24),

              // Gamepad
              Container(
                padding: EdgeInsets.all(
                  MediaQuery.of(context).size.width * 0.06,
                ), // Responsive padding
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
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Directional Controls',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => _showMotorConfigDialog(),
                          icon: const Icon(Icons.edit),
                          tooltip: 'Configure Motor Settings',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Up button
                    _buildDirectionButton(
                      direction: _motorConfigs['UP']?.toCommand() ?? 'UP',
                      icon: Icons.keyboard_arrow_up,
                      color: Colors.blue,
                      onPressed: () {},
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.width * 0.04,
                    ), // Responsive spacing
                    // Middle row with left and right buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildDirectionButton(
                          direction: _motorConfigs['LEFT']?.toCommand() ?? 'LEFT',
                          icon: Icons.keyboard_arrow_left,
                          color: Colors.orange,
                          onPressed: () {},
                        ),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.08,
                        ), // Responsive spacing
                        _buildDirectionButton(
                          direction: _motorConfigs['RIGHT']?.toCommand() ?? 'RIGHT',
                          icon: Icons.keyboard_arrow_right,
                          color: Colors.orange,
                          onPressed: () {},
                        ),
                      ],
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).size.width * 0.04,
                    ), // Responsive spacing
                    // Down button
                    _buildDirectionButton(
                      direction: _motorConfigs['DOWN']?.toCommand() ?? 'DOWN',
                      icon: Icons.keyboard_arrow_down,
                      color: Colors.blue,
                      onPressed: () {},
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
