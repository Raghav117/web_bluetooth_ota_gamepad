import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import 'package:research/controllers/ultrasonic_controller.dart';

class UltrasonicControl extends StatefulWidget {
  final UltrasonicController controller;
  final void Function(String command) onSendCommand;

  const UltrasonicControl({super.key, required this.controller, required this.onSendCommand});

  @override
  State<UltrasonicControl> createState() => _UltrasonicControlState();
}

class _UltrasonicControlState extends State<UltrasonicControl> {
  Timer? _debouncer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant UltrasonicControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _debouncer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleToggle(bool value) {
    widget.controller.setEnabled(value);
    if (value) {
      widget.onSendCommand('ULTRASONIC_${widget.controller.range}');
    } else {
      widget.onSendCommand('ULTRASONIC_OFF');
    }
  }

  void _handleRangeChanged(double value) {
    final int intVal = value.round();
    widget.controller.setRange(intVal);
    _debouncer?.cancel();
    _debouncer = Timer(const Duration(milliseconds: 300), () {
      widget.onSendCommand('ULTRASONIC_${widget.controller.range}');
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.controller.enabled;
    final double range = widget.controller.range.toDouble();

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
                'Ultrasonic Sensor',
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
          if (enabled) ...[
            const SizedBox(height: 16),
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
                value: range,
                min: 10.0,
                max: 100.0,
                divisions: 90, // 10..100 inclusive
                label: '${range.round()}',
                onChanged: _handleRangeChanged,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('10', style: Theme.of(context).textTheme.bodySmall),
                Text('Range (${range.round()})', style: Theme.of(context).textTheme.bodySmall),
                Text('100', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


