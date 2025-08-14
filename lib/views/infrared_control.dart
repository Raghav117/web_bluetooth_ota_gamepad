import 'package:flutter/material.dart';
import 'package:research/controllers/infrared_controller.dart';

class InfraredControl extends StatefulWidget {
  final InfraredController controller;
  final void Function(String command) onSendCommand;

  const InfraredControl({super.key, required this.controller, required this.onSendCommand});

  @override
  State<InfraredControl> createState() => _InfraredControlState();
}

class _InfraredControlState extends State<InfraredControl> {
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
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleToggle(bool value) {
    widget.controller.setEnabled(value);
    widget.onSendCommand(value ? 'INFRARED_ON' : 'INFRARED_OFF');
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
      child: Row(
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
    );
  }
}


