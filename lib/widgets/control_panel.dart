import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../services/trainer_service.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  final TextEditingController _powerController = TextEditingController();
  final TextEditingController _slopeController = TextEditingController();
  final TextEditingController _resistanceController = TextEditingController();

  // Debounce timers to prevent command flooding
  Timer? _slopeDebounceTimer;
  Timer? _resistanceDebounceTimer;
  Timer? _powerDebounceTimer;
  double _pendingSlopeValue = 0.0;
  double _pendingResistanceValue = 0.0;
  double _pendingPowerValue = 0.0;

  // Current UI values for immediate feedback
  double _currentSlopeValue = 0.0;
  double _currentResistanceValue = 0.0;
  double _currentPowerValue = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final trainerService = context.read<TrainerService>();
      _powerController.text = trainerService.targetPower.toString();
      _slopeController.text = trainerService.targetSlope.toString();
      _resistanceController.text = trainerService.targetResistance.toString();
      _currentSlopeValue = trainerService.targetSlope;
      _currentResistanceValue = trainerService.targetResistance;
      _currentPowerValue = trainerService.targetPower.toDouble();
    });
  }

  @override
  void dispose() {
    _powerController.dispose();
    _slopeController.dispose();
    _resistanceController.dispose();
    _slopeDebounceTimer?.cancel();
    _resistanceDebounceTimer?.cancel();
    _powerDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trainer Controls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            _buildPowerControl(),
            const SizedBox(height: AppSpacing.md),
            _buildSlopeControl(),
            const SizedBox(height: AppSpacing.md),
            _buildResistanceControl(),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerControl() {
    return Consumer<TrainerService>(
      builder: (context, trainerService, child) {
        final maxPower =
            trainerService.detectedCapabilities?.maxPower.toDouble() ?? 1000.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on, size: 20),
                const SizedBox(width: 8),
                Text('Power: ${_currentPowerValue.toStringAsFixed(0)}W'),
                const Spacer(),
                Text(
                  'Max: ${maxPower.toStringAsFixed(0)}W',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 12.0,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 20.0,
                ),
              ),
              child: Slider(
                value: _currentPowerValue.clamp(0.0, maxPower),
                min: 0.0,
                max: maxPower,
                divisions: (maxPower / 5).round(),
                label: '${_currentPowerValue.toStringAsFixed(0)}W',
                onChanged: (value) {
                  _debouncedSetPower(trainerService, value);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSlopeControl() {
    return Consumer<TrainerService>(
      builder: (context, trainerService, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, size: 20),
                const SizedBox(width: 8),
                Text('Slope: ${_currentSlopeValue.toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 12.0,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 20.0,
                ),
              ),
              child: Slider(
                value: _currentSlopeValue.clamp(0.0, 6.0),
                min: 0.0,
                max: 6.0,
                divisions: 60,
                label: '${_currentSlopeValue.toStringAsFixed(1)}%',
                onChanged: (value) {
                  _debouncedSetSlope(trainerService, value);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResistanceControl() {
    return Consumer<TrainerService>(
      builder: (context, trainerService, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Resistance: ${_currentResistanceValue.toStringAsFixed(1)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6.0,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 12.0,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 20.0,
                ),
              ),
              child: Slider(
                value: _currentResistanceValue.clamp(0.0, 10.0),
                min: 0.0,
                max: 10.0,
                divisions: 100,
                label: _currentResistanceValue.toStringAsFixed(1),
                onChanged: (value) {
                  _debouncedSetResistance(trainerService, value);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _debouncedSetSlope(TrainerService trainerService, double value) {
    setState(() {
      _currentSlopeValue = value;
    });
    _slopeController.text = value.toStringAsFixed(1);
    _pendingSlopeValue = value;

    _slopeDebounceTimer?.cancel();
    _slopeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      trainerService.setSlopeTarget(_pendingSlopeValue);
    });
  }

  void _debouncedSetResistance(TrainerService trainerService, double value) {
    setState(() {
      _currentResistanceValue = value;
    });
    _resistanceController.text = value.toStringAsFixed(1);
    _pendingResistanceValue = value;

    _resistanceDebounceTimer?.cancel();
    _resistanceDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      trainerService.setResistancePercentage(_pendingResistanceValue);
    });
  }

  void _debouncedSetPower(TrainerService trainerService, double value) {
    setState(() {
      _currentPowerValue = value;
    });
    _powerController.text = value.toStringAsFixed(0);
    _pendingPowerValue = value;

    _powerDebounceTimer?.cancel();
    _powerDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      trainerService.setPowerTarget(_pendingPowerValue.round());
    });
  }
}
