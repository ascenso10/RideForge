import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../services/workout_service.dart';
import '../services/trainer_service.dart';
import '../models/workout_models.dart';
import 'animated_transitions.dart';
import 'intensity_control.dart';

class WorkoutPlayer extends StatelessWidget {
  const WorkoutPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<WorkoutService, TrainerService>(
      builder: (context, workoutService, trainerService, child) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildWorkoutHeader(context, workoutService),
              const SizedBox(height: 16),
              _buildCurrentInterval(context, workoutService),
              const SizedBox(height: 16),
              _buildProgressIndicators(context, workoutService),
              const SizedBox(height: 16),
              _buildCurrentData(context, trainerService),
              const SizedBox(height: 16),
              _buildControlButtons(context, workoutService),
              const SizedBox(height: 16),
              _buildIntervalsList(context, workoutService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkoutHeader(
    BuildContext context,
    WorkoutService workoutService,
  ) {
    return AnimatedDataCard(
      slideDirection: const Offset(0.0, -0.2),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workoutService.currentWorkout?.name ?? 'Unknown Workout',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    _getStatusText(workoutService.status),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _getStatusColor(workoutService.status),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total Time',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    workoutService.formatDuration(workoutService.elapsedTime),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentInterval(
    BuildContext context,
    WorkoutService workoutService,
  ) {
    // Show completion message when workout is completed
    if (workoutService.status == WorkoutStatus.completed) {
      return Card(
        color: Colors.green.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(Icons.celebration, size: 60, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Workout Complete! 🎉',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Great job! Your workout is finished.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Total Time: ${workoutService.formatDuration(workoutService.elapsedTime)}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    final interval = workoutService.currentInterval;
    if (interval == null) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Interval',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${workoutService.currentIntervalIndex + 1} / ${workoutService.currentWorkout?.intervals.length ?? 0}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              interval.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _getIntervalTypeColor(interval.type),
              ),
            ),
            if (interval.description != null) ...[
              const SizedBox(height: 4),
              Text(
                interval.description!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTargetDisplay(context, workoutService, interval),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Remaining',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      workoutService.formatDuration(
                        workoutService.remainingTime,
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (workoutService.hasPowerIntervals) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              IntensityControl(workoutService: workoutService),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTargetDisplay(
    BuildContext context,
    WorkoutService workoutService,
    WorkoutInterval interval,
  ) {
    String target;
    IconData icon;

    switch (interval.mode) {
      case WorkoutMode.power:
        target = '${workoutService.currentTargetPower ?? 0} W';
        icon = Icons.flash_on;
        break;
      case WorkoutMode.slope:
        target = '${interval.targetSlope}%';
        icon = Icons.trending_up;
        break;
      case WorkoutMode.resistance:
        target = '${interval.targetResistance}%';
        icon = Icons.fitness_center;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Target', style: Theme.of(context).textTheme.bodySmall),
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 4),
            Text(
              target,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgressIndicators(
    BuildContext context,
    WorkoutService workoutService,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Workout Progress'),
                Text(
                  '${(workoutService.workoutProgress * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedProgressBar(
              value: workoutService.workoutProgress,
              color: AppColors.primary,
              showPercentage: false,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Interval Progress'),
                Text(
                  '${(workoutService.intervalProgress * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedProgressBar(
              value: workoutService.intervalProgress,
              color: workoutService.currentInterval != null
                  ? _getIntervalTypeColor(workoutService.currentInterval!.type)
                  : AppColors.primary,
              showPercentage: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentData(
    BuildContext context,
    TrainerService trainerService,
  ) {
    final data = trainerService.currentData;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Performance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDataItem(
                    context,
                    label: 'POWER',
                    value: data?.power.toStringAsFixed(0) ?? '0',
                    unit: 'W',
                    color: AppColors.power,
                  ),
                ),
                Expanded(
                  child: _buildDataItem(
                    context,
                    label: 'SPEED',
                    value: data?.speed.toStringAsFixed(1) ?? '0.0',
                    unit: 'km/h',
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDataItem(
                    context,
                    label: 'CADENCE',
                    value: data?.cadence.toStringAsFixed(0) ?? '0',
                    unit: 'rpm',
                    color: AppColors.cadence,
                  ),
                ),
                Expanded(
                  child: _buildDataItem(
                    context,
                    label: 'HEART RATE',
                    value: '${data?.heartRate ?? 0}',
                    unit: 'bpm',
                    color: AppColors.heartRate,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataItem(
    BuildContext context, {
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1,
          ),
        ),
        Text(
          unit,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons(
    BuildContext context,
    WorkoutService workoutService,
  ) {
    final isGpxWorkout = workoutService.isGpxWorkout;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isGpxWorkout) ...[
              // Regular workout interval controls
              Column(
                children: [
                  // Interval info
                  Text(
                    'Interval ${workoutService.currentIntervalIndex + 1} / ${workoutService.currentWorkout?.intervals.length ?? 0}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (workoutService.currentInterval != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      workoutService.currentInterval!.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _getIntervalTypeColor(
                          workoutService.currentInterval!.type,
                        ),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Navigation buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () =>
                            workoutService.skipToPreviousInterval(),
                        icon: const Icon(Icons.skip_previous),
                        label: const Text('Previous'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => workoutService.skipToNextInterval(),
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Next'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
            ],
            // Common controls for both workout types
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: workoutService.status == WorkoutStatus.running
                        ? () => workoutService.pauseWorkout()
                        : () => workoutService.resumeWorkout(),
                    icon: Icon(
                      workoutService.status == WorkoutStatus.running
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      workoutService.status == WorkoutStatus.running
                          ? 'Pause'
                          : 'Resume',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          workoutService.status == WorkoutStatus.running
                          ? Colors.orange
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showStopDialog(context, workoutService),
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalsList(
    BuildContext context,
    WorkoutService workoutService,
  ) {
    final workout = workoutService.currentWorkout;
    if (workout == null) return const SizedBox();

    return Expanded(
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Workout Intervals',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: workout.intervals.length,
                itemBuilder: (context, index) {
                  final interval = workout.intervals[index];
                  final isCurrent =
                      index == workoutService.currentIntervalIndex;

                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isCurrent
                          ? _getIntervalTypeColor(interval.type)
                          : Colors.grey[300],
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrent ? Colors.white : Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      interval.name,
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent
                            ? _getIntervalTypeColor(interval.type)
                            : null,
                      ),
                    ),
                    subtitle: Text(
                      '${workoutService.formatDuration(interval.duration)} - ${_getIntervalTarget(workoutService, interval)}',
                    ),
                    trailing: isCurrent ? const Icon(Icons.play_arrow) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getIntervalTarget(
    WorkoutService workoutService,
    WorkoutInterval interval,
  ) {
    switch (interval.mode) {
      case WorkoutMode.power:
        return '${workoutService.scaledTargetPower(interval)}W';
      case WorkoutMode.slope:
        return '${interval.targetSlope}%';
      case WorkoutMode.resistance:
        return '${interval.targetResistance}%';
    }
  }

  Color _getIntervalTypeColor(IntervalType type) {
    switch (type) {
      case IntervalType.warmup:
        return Colors.green;
      case IntervalType.work:
        return Colors.red;
      case IntervalType.rest:
        return Colors.blue;
      case IntervalType.cooldown:
        return Colors.orange;
    }
  }

  String _getStatusText(WorkoutStatus status) {
    switch (status) {
      case WorkoutStatus.running:
        return 'Running';
      case WorkoutStatus.paused:
        return 'Paused';
      case WorkoutStatus.completed:
        return 'Completed';
      case WorkoutStatus.stopped:
        return 'Stopped';
    }
  }

  Color _getStatusColor(WorkoutStatus status) {
    switch (status) {
      case WorkoutStatus.running:
        return Colors.green;
      case WorkoutStatus.paused:
        return Colors.orange;
      case WorkoutStatus.completed:
        return Colors.blue;
      case WorkoutStatus.stopped:
        return Colors.grey;
    }
  }

  void _showStopDialog(BuildContext context, WorkoutService workoutService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Stop Workout'),
          content: const Text(
            'Are you sure you want to stop the current workout?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                workoutService.stopWorkout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );
  }
}
