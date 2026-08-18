import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/feature_flags.dart';
import '../models/trainer_capabilities.dart';
import '../services/workout_service.dart';
import '../services/trainer_service.dart';

class TrainerSettingsScreen extends StatefulWidget {
  const TrainerSettingsScreen({super.key});

  @override
  State<TrainerSettingsScreen> createState() => _TrainerSettingsScreenState();
}

class _TrainerSettingsScreenState extends State<TrainerSettingsScreen> {
  TrainerCapabilities? _currentCapabilities;
  TrainerCapabilities? _detectedCapabilities;

  @override
  void initState() {
    super.initState();
    _loadCapabilities();
  }

  void _loadCapabilities() {
    final workoutService = context.read<WorkoutService>();
    final trainerService = context.read<TrainerService>();

    _currentCapabilities = workoutService.trainerCapabilities;
    _detectedCapabilities = trainerService.detectedCapabilities;

    // Refresh capabilities to get the latest applied values
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trainer Settings')),
      body: Consumer2<TrainerService, WorkoutService>(
        builder: (context, trainerService, workoutService, child) {
          // Update capabilities when they change
          _currentCapabilities = workoutService.trainerCapabilities;
          _detectedCapabilities = trainerService.detectedCapabilities;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionStatus(trainerService),
                const SizedBox(height: 24),
                if (_detectedCapabilities != null) ...[
                  _buildActiveCapabilitiesSection(),
                  const SizedBox(height: 24),
                ],
                if (FeatureFlags.enableGpxWorkouts) _buildTestSection(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionStatus(TrainerService trainerService) {
    final isConnected = trainerService.isConnected;
    final hasCapabilities = _detectedCapabilities != null;
    final deviceName = trainerService.connectedDeviceName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isConnected && deviceName != null
                        ? deviceName
                        : 'Trainer Connection',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  hasCapabilities ? Icons.analytics : Icons.help_outline,
                  color: hasCapabilities ? Colors.blue : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasCapabilities
                        ? 'Capabilities detected from trainer'
                        : 'No capabilities detected',
                    style: TextStyle(
                      color: hasCapabilities ? Colors.blue : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            if (deviceName == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connect to your trainer to automatically detect its capabilities.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveCapabilitiesSection() {
    if (_currentCapabilities == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Active Trainer Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'These capabilities were automatically detected and applied from your trainer:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _buildCapabilityRow(
              'Maximum Gradient',
              '${_currentCapabilities!.maxGradient.toStringAsFixed(1)}%',
              Colors.red,
            ),
            _buildCapabilityRow(
              'Minimum Gradient',
              '${_currentCapabilities!.minGradient.toStringAsFixed(1)}%',
              Colors.blue,
            ),
            _buildCapabilityRow(
              'Maximum Power',
              '${_currentCapabilities!.maxPower}W',
              Colors.orange,
            ),
            _buildCapabilityRow(
              'Maximum Resistance',
              _currentCapabilities!.maxResistance.toStringAsFixed(1),
              Colors.purple,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These capabilities have been automatically applied to your trainer settings.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilityRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection() {
    if (_currentCapabilities == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_accessibility, color: Colors.purple),
                const SizedBox(width: 8),
                Text(
                  'Gradient Handling',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Gradients will be capped to the trainers maximum',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ...[6.0, 25.0].map((testGradient) {
              final constrained = _currentCapabilities!.constrainGradient(
                testGradient,
              );
              final isModified = constrained != testGradient;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        '${testGradient.toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${constrained.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isModified ? Colors.orange : Colors.green,
                      ),
                    ),
                    if (isModified) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CAPPED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
