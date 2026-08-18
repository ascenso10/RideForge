import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/workout_models.dart';
import '../widgets/altitude_profile_chart.dart';
import '../widgets/immersive_gpx_workout_player.dart';
import '../widgets/animated_transitions.dart';
import '../config/feature_flags.dart';
import '../widgets/fit_validation_popup.dart';
import '../services/workout_service.dart';
import '../services/trainer_service.dart';
import 'trainer_settings_screen.dart';
import 'workout_completion_screen.dart';

class GpxWorkoutScreen extends StatefulWidget {
  final GpxWorkout gpxWorkout;

  const GpxWorkoutScreen({super.key, required this.gpxWorkout});

  @override
  State<GpxWorkoutScreen> createState() => _GpxWorkoutScreenState();
}

class _GpxWorkoutScreenState extends State<GpxWorkoutScreen> {
  double? currentDistance;
  bool isPlaying = false;
  bool _useImmersiveMode = true;
  bool _wakelockEnabled = false;

  @override
  void initState() {
    super.initState();

    // Set workout completion callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final workoutService = context.read<WorkoutService>();
      workoutService.setWorkoutCompletedCallback(_onWorkoutCompleted);

      // Set FIT validation callback for debug mode
      if (kDebugMode) {
        workoutService.setFitValidatedCallback(_onFitValidated);
      }

      // Listen for workout status changes to manage wakelock
      workoutService.addListener(_onWorkoutStatusChanged);
      _updateWakelock(workoutService.status);
    });
  }

  @override
  void dispose() {
    // Disable wakelock when leaving the screen
    if (_wakelockEnabled) {
      WakelockPlus.disable();
    }
    super.dispose();
  }

  void _onWorkoutStatusChanged() {
    final workoutService = context.read<WorkoutService>();
    _updateWakelock(workoutService.status);
  }

  void _updateWakelock(WorkoutStatus status) {
    final shouldEnable =
        status == WorkoutStatus.running || status == WorkoutStatus.paused;

    if (shouldEnable && !_wakelockEnabled) {
      WakelockPlus.enable();
      _wakelockEnabled = true;
    } else if (!shouldEnable && _wakelockEnabled) {
      WakelockPlus.disable();
      _wakelockEnabled = false;
    }
  }

  void _onWorkoutCompleted(WorkoutSummary summary) {
    if (!mounted) return;

    Navigator.of(context).push(
      FadePageRoute(child: WorkoutCompletionScreen(workoutSummary: summary)),
    );
  }

  void _onFitValidated(FitValidationResult result) {
    if (!mounted) return;
    if (FeatureFlags.enableFitValidation) {
      showFitValidationPopup(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorkoutService>(
      builder: (context, workoutService, child) {
        // If this GPX workout is running and immersive mode is enabled
        if (workoutService.isGpxWorkout &&
            workoutService.currentGpxWorkout?.id == widget.gpxWorkout.id &&
            workoutService.status != WorkoutStatus.stopped &&
            _useImmersiveMode) {
          return const ImmersiveGpxWorkoutPlayer();
        }

        // Otherwise show normal scaffold with app bar
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.gpxWorkout.name),
            actions: [
              if (workoutService.isGpxWorkout &&
                  workoutService.currentGpxWorkout?.id ==
                      widget.gpxWorkout.id &&
                  workoutService.status != WorkoutStatus.stopped)
                IconButton(
                  onPressed: () => _showViewModeDialog(context),
                  icon: const Icon(Icons.visibility),
                  tooltip: 'Change View Mode',
                ),
              IconButton(
                onPressed: () => _showRouteInfo(),
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ElevationStatsCard(gpxWorkout: widget.gpxWorkout),
                      const SizedBox(height: 16),
                      Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.show_chart,
                                    color: Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Altitude Profile',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Consumer<WorkoutService>(
                              builder: (context, workoutService, child) {
                                double? currentDist;
                                if (workoutService.isGpxWorkout &&
                                    workoutService.currentGpxWorkout?.id ==
                                        widget.gpxWorkout.id) {
                                  currentDist =
                                      workoutService.currentGpxDistance;
                                }
                                return AltitudeProfileChart(
                                  gpxWorkout: widget.gpxWorkout,
                                  currentDistance: currentDist,
                                  height: 250,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Consumer<WorkoutService>(
                        builder: (context, workoutService, child) {
                          return _buildTrainerCompatibility(workoutService);
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildRouteDetails(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              Consumer2<TrainerService, WorkoutService>(
                builder: (context, trainerService, workoutService, child) {
                  final bool canStart =
                      trainerService.isConnected &&
                      workoutService.status == WorkoutStatus.stopped;
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: canStart
                              ? () => _startGpxWorkout(workoutService)
                              : null,
                          icon: const Icon(Icons.play_arrow, size: 24),
                          label: Text(
                            trainerService.isConnected
                                ? 'Start Route'
                                : 'Connect a Trainer to Start',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 56),
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTrainerCompatibility(WorkoutService workoutService) {
    final compatibility = workoutService.analyzeGpxCompatibility(
      widget.gpxWorkout,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings_applications,
                  color: compatibility.compatibilityColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Trainer Compatibility',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: compatibility.compatibilityColor.withValues(
                      alpha: 0.2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: compatibility.compatibilityColor),
                  ),
                  child: Text(
                    compatibility.compatibilityLabel,
                    style: TextStyle(
                      color: compatibility.compatibilityColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Analysis based on current trainer settings',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildCompatibilityItem(
                    'Route Max',
                    '${compatibility.maxOriginalGradient.toStringAsFixed(1)}%',
                    Icons.trending_up,
                    compatibility.maxOriginalGradient <=
                            workoutService.trainerCapabilities.maxGradient
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildCompatibilityItem(
                    'Trainer Max',
                    '${compatibility.maxTrainerGradient.toStringAsFixed(1)}%',
                    Icons.settings,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCompatibilityItem(
                    'Supported',
                    '${compatibility.totalSegments - compatibility.cappedSegments}/${compatibility.totalSegments}',
                    Icons.check_circle,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildCompatibilityItem(
                    'Will be Capped',
                    '${compatibility.cappedSegments}',
                    compatibility.cappedSegments > 0
                        ? Icons.warning
                        : Icons.check,
                    compatibility.cappedSegments > 0
                        ? Colors.orange
                        : Colors.green,
                  ),
                ),
              ],
            ),
            if (compatibility.cappedSegments > 0) ...[
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
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${compatibility.cappedSegments} segments exceed trainer limits and will be capped to ${compatibility.maxTrainerGradient.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const TrainerSettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.settings),
                    label: const Text('Trainer Settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
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

  Widget _buildCompatibilityItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteDetails() {
    final segments = widget.gpxWorkout.segments;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route Details',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              widget.gpxWorkout.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'Track Points',
                    '${widget.gpxWorkout.trackPoints.length}',
                    Icons.location_on,
                  ),
                ),
                Expanded(
                  child: _buildDetailItem(
                    'Segments',
                    '${segments.length}',
                    Icons.timeline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem(
                    'Avg Grade',
                    '${_calculateAverageGrade().toStringAsFixed(1)}%',
                    Icons.trending_up,
                  ),
                ),
                Expanded(
                  child: _buildDetailItem(
                    'Max Grade',
                    '${_calculateMaxGrade().toStringAsFixed(1)}%',
                    Icons.keyboard_double_arrow_up,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }

  double _calculateAverageGrade() {
    final segments = widget.gpxWorkout.segments;
    if (segments.isEmpty) return 0.0;

    final totalGrade = segments.fold(
      0.0,
      (sum, segment) => sum + segment.slope.abs(),
    );
    return totalGrade / segments.length;
  }

  double _calculateMaxGrade() {
    final segments = widget.gpxWorkout.segments;
    if (segments.isEmpty) return 0.0;

    return segments.map((s) => s.slope.abs()).reduce((a, b) => a > b ? a : b);
  }

  void _startGpxWorkout(WorkoutService workoutService) {
    workoutService.startGpxWorkout(widget.gpxWorkout);
  }

  void _showRouteInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.gpxWorkout.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${widget.gpxWorkout.filePath.split('/').last}'),
            const SizedBox(height: 8),
            Text('Track Points: ${widget.gpxWorkout.trackPoints.length}'),
            const SizedBox(height: 8),
            Text(
              'Distance: ${(widget.gpxWorkout.totalDistance / 1000).toStringAsFixed(2)} km',
            ),
            const SizedBox(height: 8),
            Text(
              'Elevation: ${widget.gpxWorkout.minElevation.toInt()}m - ${widget.gpxWorkout.maxElevation.toInt()}m',
            ),
            const SizedBox(height: 8),
            Text(
              'Total Climb: ${widget.gpxWorkout.totalElevationGain.toInt()}m',
            ),
            if (widget.gpxWorkout.totalTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'Duration: ${_formatDuration(widget.gpxWorkout.totalTime!)}',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }

  void _showViewModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('GPX Workout View Mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('Immersive Mode'),
                subtitle: const Text(
                  'Full-screen experience with elevation profile',
                ),
                trailing: _useImmersiveMode ? const Icon(Icons.check) : null,
                onTap: () {
                  setState(() {
                    _useImmersiveMode = true;
                  });
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.view_list),
                title: const Text('Standard Mode'),
                subtitle: const Text('Traditional workout interface'),
                trailing: !_useImmersiveMode ? const Icon(Icons.check) : null,
                onTap: () {
                  setState(() {
                    _useImmersiveMode = false;
                  });
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }
}
