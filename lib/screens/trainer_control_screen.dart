import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../services/trainer_service.dart';
import '../services/heart_rate_service.dart';
import '../widgets/data_chart.dart';
import '../widgets/control_panel.dart';

class TrainerControlScreen extends StatefulWidget {
  const TrainerControlScreen({super.key});

  @override
  State<TrainerControlScreen> createState() => _TrainerControlScreenState();
}

class _TrainerControlScreenState extends State<TrainerControlScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trainer Control')),
      body: Consumer2<TrainerService, HeartRateService>(
        builder: (context, trainerService, hrService, child) {
          if (!trainerService.isConnected) {
            return const Center(child: Text('No trainer connected'));
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                _buildDataDisplay(trainerService, hrService),
                const SizedBox(height: 280, child: DataChart()),
                const ControlPanel(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDataDisplay(
    TrainerService trainerService,
    HeartRateService hrService,
  ) {
    final data = trainerService.currentData;
    final hr = hrService.currentHeartRate;

    return Card(
      margin: const EdgeInsets.all(AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Text(
              'Real-time Data',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDataItem(
                  'Speed',
                  '${data?.speed.toStringAsFixed(1) ?? '0.0'} km/h',
                  Icons.speed,
                  AppColors.primary,
                ),
                _buildDataItem(
                  'Power',
                  '${data?.power.toStringAsFixed(0) ?? '0'} W',
                  Icons.flash_on,
                  AppColors.power,
                ),
                if (hrService.isConnected)
                  _buildDataItem(
                    'Heart Rate',
                    hr > 0 ? '$hr bpm' : '-- bpm',
                    Icons.favorite,
                    AppColors.heartRate,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _buildDataItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
