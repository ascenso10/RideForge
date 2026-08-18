import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/app_theme.dart';
import '../services/workout_service.dart';
import '../services/trainer_service.dart';
import '../services/heart_rate_service.dart';
import '../models/workout_models.dart';
import 'animated_transitions.dart';

class ImmersiveWorkoutPlayer extends StatefulWidget {
  final VoidCallback? onExit;

  const ImmersiveWorkoutPlayer({super.key, this.onExit});

  @override
  State<ImmersiveWorkoutPlayer> createState() => _ImmersiveWorkoutPlayerState();
}

class _ImmersiveWorkoutPlayerState extends State<ImmersiveWorkoutPlayer> {
  @override
  void initState() {
    super.initState();
    // Keep screen awake during workouts
    WakelockPlus.enable();
    // Force fullscreen mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Set preferred orientations to portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    // Restore system UI and orientation when leaving
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Disable wakelock when leaving workout
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer3<WorkoutService, TrainerService, HeartRateService>(
        builder:
            (context, workoutService, trainerService, heartRateService, child) {
              return SafeArea(
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      child: Padding(
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
                            _buildCurrentData(
                              context,
                              trainerService,
                              heartRateService,
                            ),
                            const SizedBox(height: 16),
                            _buildControlButtons(context, workoutService),
                          ],
                        ),
                      ),
                    ),
                    // Countdown overlay
                    if (workoutService.countdownSeconds != null)
                      _buildCountdownOverlay(context, workoutService),
                  ],
                ),
              );
            },
      ),
    );
  }

  Widget _buildWorkoutHeader(
    BuildContext context,
    WorkoutService workoutService,
  ) {
    return AnimatedDataCard(
      slideDirection: const Offset(0.0, -0.2),
      child: Card(
        color: Colors.grey[900],
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    _getStatusText(workoutService.status),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _getStatusColor(workoutService.status),
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total Time',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    workoutService.formatDuration(workoutService.elapsedTime),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 22,
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
      return SizedBox(
        width: double.infinity,
        child: Card(
          color: Colors.green.withValues(alpha: 0.2),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.grey[300]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Total Time: ${workoutService.formatDuration(workoutService.elapsedTime)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final interval = workoutService.currentInterval;
    if (interval == null) return const SizedBox();

    return Card(
      color: Colors.grey[900],
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
                Text(
                  '${workoutService.currentIntervalIndex + 1} / ${workoutService.currentWorkout?.intervals.length ?? 0}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[400],
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              interval.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _getIntervalTypeColor(interval.type),
                fontSize: 26,
              ),
            ),
            if (interval.description != null) ...[
              const SizedBox(height: 4),
              Text(
                interval.description!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTargetDisplay(context, interval),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Remaining',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      workoutService.formatDuration(
                        workoutService.remainingTime,
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 22,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetDisplay(BuildContext context, WorkoutInterval interval) {
    String target;
    IconData icon;

    switch (interval.mode) {
      case WorkoutMode.power:
        target = '${interval.targetPower} W';
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
        Text(
          'Target',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[400],
            fontSize: 14,
          ),
        ),
        Row(
          children: [
            Icon(icon, size: 24, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              target,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 22,
              ),
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
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Workout Progress',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                Text(
                  '${(workoutService.workoutProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedProgressBar(
              value: workoutService.workoutProgress,
              color: AppColors.primary,
              showPercentage: false,
              height: 8,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Interval Progress',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                Text(
                  '${(workoutService.intervalProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.white, fontSize: 18),
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
              height: 8,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentData(
    BuildContext context,
    TrainerService trainerService,
    HeartRateService heartRateService,
  ) {
    final data = trainerService.currentData;
    final hr = heartRateService.currentHeartRate;
    final hrConnected = heartRateService.isConnected;

    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          children: [
            // ── Primary metric: Power ──────────────────────────────────────
            _buildPrimaryMetric(
              label: 'POWER',
              value: data?.power.toStringAsFixed(0) ?? '0',
              unit: 'W',
              color: AppColors.power,
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 16),
            // ── Secondary metrics row ──────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _buildSecondaryMetric(
                      label: 'SPEED',
                      value: data?.speed.toStringAsFixed(1) ?? '0.0',
                      unit: 'km/h',
                      color: Colors.white,
                    ),
                  ),
                  if (hrConnected) ...[
                    VerticalDivider(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 32,
                    ),
                    Expanded(
                      child: _buildSecondaryMetric(
                        label: 'HEART RATE',
                        value: hr > 0 ? '$hr' : '--',
                        unit: 'bpm',
                        color: AppColors.heartRate,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryMetric({
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.7),
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 72,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                unit,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSecondaryMetric({
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey[500],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1,
          ),
        ),
        Text(
          unit,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[500],
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
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (!isGpxWorkout) ...[
              // Regular workout interval controls
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => workoutService.skipToPreviousInterval(),
                      icon: const Icon(Icons.skip_previous),
                      label: const Text('Previous'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.withValues(alpha: 0.3),
                        foregroundColor: const Color.fromARGB(
                          255,
                          172,
                          209,
                          240,
                        ),
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => workoutService.skipToNextInterval(),
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Next'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.withValues(alpha: 0.3),
                        foregroundColor: const Color.fromARGB(
                          255,
                          172,
                          209,
                          240,
                        ),
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(color: Colors.grey[700]),
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
          backgroundColor: Colors.grey[900],
          title: Text('Stop Workout', style: TextStyle(color: Colors.white)),
          content: Text(
            'Are you sure you want to stop the current workout?',
            style: TextStyle(color: Colors.grey[300]),
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

  Widget _buildCountdownOverlay(
    BuildContext context,
    WorkoutService workoutService,
  ) {
    final countdownSeconds = workoutService.countdownSeconds;
    final nextInterval = workoutService.nextInterval;

    if (countdownSeconds == null || nextInterval == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'NEXT INTERVAL',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.grey[400],
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getIntervalTypeColor(nextInterval.type),
                  width: 6,
                ),
              ),
              child: Center(
                child: Text(
                  '$countdownSeconds',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 72,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              nextInterval.name,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: _getIntervalTypeColor(nextInterval.type),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (nextInterval.mode == WorkoutMode.power &&
                nextInterval.targetPower != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flash_on, color: Colors.white, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    '${nextInterval.targetPower} W',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            if (nextInterval.mode == WorkoutMode.slope &&
                nextInterval.targetSlope != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.trending_up, color: Colors.white, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    '${nextInterval.targetSlope}%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            if (nextInterval.description != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  nextInterval.description!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.grey[300]),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
