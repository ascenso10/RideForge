import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/workout_service.dart';
import '../services/trainer_service.dart';
import '../services/heart_rate_service.dart';
import '../models/workout_models.dart';
import '../widgets/enhanced_elevation_chart.dart';
import '../config/feature_flags.dart';
import '../config/app_theme.dart';
import '../widgets/fit_validation_popup.dart';
import '../screens/workout_completion_screen.dart';
import '../widgets/animated_transitions.dart';

class ImmersiveGpxWorkoutPlayer extends StatefulWidget {
  const ImmersiveGpxWorkoutPlayer({super.key});

  @override
  State<ImmersiveGpxWorkoutPlayer> createState() =>
      _ImmersiveGpxWorkoutPlayerState();
}

class _ImmersiveGpxWorkoutPlayerState extends State<ImmersiveGpxWorkoutPlayer> {
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final workoutService = Provider.of<WorkoutService>(
        context,
        listen: false,
      );
      workoutService.setWorkoutCompletedCallback(_onWorkoutCompleted);
      if (kDebugMode) {
        workoutService.setFitValidatedCallback(_onFitValidated);
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WakelockPlus.disable();
    super.dispose();
  }

  void _onWorkoutCompleted(WorkoutSummary summary) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      FadePageRoute(child: WorkoutCompletionScreen(workoutSummary: summary)),
    );
  }

  void _onFitValidated(FitValidationResult result) {
    if (!mounted) return;
    if (FeatureFlags.enableFitValidation) {
      showFitValidationPopup(context, result);
    }
  }

  String _getSlopeLabel(double slope) {
    if (slope > 12) return 'EXTREME CLIMB';
    if (slope > 8) return 'STEEP CLIMB';
    if (slope > 4) return 'MODERATE CLIMB';
    if (slope > 1) return 'GENTLE CLIMB';
    if (slope > -1) return 'FLAT';
    if (slope > -4) return 'GENTLE DESCENT';
    if (slope > -8) return 'STEEP DESCENT';
    return 'EXTREME DESCENT';
  }

  Color _getSlopeColor(double slope) {
    if (slope > 8) return Colors.red;
    if (slope > 4) return Colors.orange;
    if (slope > 0) return Colors.yellow;
    if (slope < -4) return Colors.green;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer3<WorkoutService, TrainerService, HeartRateService>(
        builder:
            (context, workoutService, trainerService, heartRateService, child) {
              final gpxWorkout = workoutService.currentGpxWorkout;

              return SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildRouteHeader(context, workoutService, gpxWorkout),
                        const SizedBox(height: 16),
                        if (gpxWorkout != null) ...[
                          _buildElevationCard(gpxWorkout, workoutService),
                          const SizedBox(height: 16),
                        ],
                        _buildMetricsCard(
                          context,
                          workoutService,
                          trainerService,
                          heartRateService,
                          gpxWorkout,
                        ),
                        const SizedBox(height: 16),
                        _buildControlButtons(context, workoutService),
                      ],
                    ),
                  ),
                ),
              );
            },
      ),
    );
  }

  Widget _buildRouteHeader(
    BuildContext context,
    WorkoutService workoutService,
    GpxWorkout? gpxWorkout,
  ) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gpxWorkout?.name ?? 'GPX Workout',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontSize: 22,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(workoutService.gpxProgress * 100).toStringAsFixed(0)}% complete',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.primary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
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
    );
  }

  Widget _buildElevationCard(
    GpxWorkout gpxWorkout,
    WorkoutService workoutService,
  ) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ELEVATION',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  '${(workoutService.currentGpxDistance / 1000).toStringAsFixed(1)} / '
                  '${(gpxWorkout.totalDistance / 1000).toStringAsFixed(1)} km',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[400],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            EnhancedElevationChart(
              gpxWorkout: gpxWorkout,
              currentDistance: workoutService.currentGpxDistance,
              isImmersive: true,
              height: 160,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard(
    BuildContext context,
    WorkoutService workoutService,
    TrainerService trainerService,
    HeartRateService heartRateService,
    GpxWorkout? gpxWorkout,
  ) {
    final currentSegment =
        gpxWorkout != null &&
            workoutService.currentGpxSegmentIndex < gpxWorkout.segments.length
        ? gpxWorkout.segments[workoutService.currentGpxSegmentIndex]
        : null;

    final slope = currentSegment?.slope ?? 0.0;
    final slopeColor = _getSlopeColor(slope);
    final data = trainerService.currentData;
    final hr = heartRateService.currentHeartRate;
    final hrConnected = heartRateService.isConnected;

    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          children: [
            // Primary metric: Slope
            _buildPrimaryMetric(
              label: currentSegment != null ? _getSlopeLabel(slope) : 'SLOPE',
              value: currentSegment != null ? slope.toStringAsFixed(1) : '--',
              unit: '%',
              color: slopeColor,
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 16),
            // Secondary metrics row
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _buildSecondaryMetric(
                      label: 'POWER',
                      value: data != null && data.power > 0
                          ? data.power.toStringAsFixed(0)
                          : '--',
                      unit: 'W',
                      color: AppColors.power,
                    ),
                  ),
                  VerticalDivider(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 32,
                  ),
                  Expanded(
                    child: _buildSecondaryMetric(
                      label: 'SPEED',
                      value: workoutService.currentSpeed.toStringAsFixed(1),
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
            const SizedBox(height: 16),
            Divider(color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Route Progress',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                Text(
                  '${(workoutService.gpxProgress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedProgressBar(
              value: workoutService.gpxProgress.clamp(0.0, 1.0),
              color: slopeColor,
              showPercentage: false,
              height: 8,
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
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
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

  void _showStopDialog(BuildContext context, WorkoutService workoutService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Stop Workout',
            style: TextStyle(color: Colors.white),
          ),
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
}
