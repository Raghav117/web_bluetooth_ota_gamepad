import 'package:flutter/material.dart';
import 'package:research/controllers/infrared_controller.dart';
import 'dart:async'; // Added for Timer

class InfraredControl extends StatefulWidget {
  final InfraredController controller;
  final void Function(String command) onSendCommand;

  const InfraredControl({super.key, required this.controller, required this.onSendCommand});

  @override
  State<InfraredControl> createState() => _InfraredControlState();
}

class _InfraredControlState extends State<InfraredControl> {
  // Speed control variables
  double _speedValue = 100.0; // Default speed value
  Timer? _speedDebouncer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant InfraredControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _speedDebouncer?.cancel();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleToggle(bool value) {
    widget.controller.setEnabled(value);
    widget.onSendCommand(value ? 'INFRARED_ON' : 'INFRARED_OFF');
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
      int speedInt = value.round();
      String speedCommand = "SPEED_${speedInt + 0}";
      widget.onSendCommand(speedCommand);
      print("Sent speed command: $speedCommand");
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.controller.enabled;

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
          // Infrared toggle row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Infrared Sensor',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  Text(
                    enabled ? 'On' : 'Off',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: enabled,
                    onChanged: _handleToggle,
                  ),
                ],
              ),
            ],
          ),
          
          // Speed control section (only show when infrared is enabled)
          if (enabled) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            
            // Speed control header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Speed Control',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Speed slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Theme.of(context).colorScheme.primary,
                inactiveTrackColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                thumbColor: Theme.of(context).colorScheme.primary,
                overlayColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: _speedValue,
                min: 1.0,
                max: 255.0,
                divisions: 255, // 255 values (1-255)
                onChanged: _onSpeedChanged,
                label: '${_speedValue.round()}',
              ),
            ),
            const SizedBox(height: 8),
            
            // Speed labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Slow', style: Theme.of(context).textTheme.bodySmall),
                Text('Fast', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


