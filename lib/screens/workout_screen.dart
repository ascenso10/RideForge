import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../config/app_theme.dart';
import '../config/feature_flags.dart';
import '../services/workout_service.dart';
import '../services/trainer_service.dart';
import '../models/workout_models.dart';
import '../widgets/workout_player.dart';
import '../widgets/immersive_workout_player.dart';
import '../widgets/animated_transitions.dart';
import '../widgets/fit_validation_popup.dart';
import 'workout_builder_screen.dart';
import 'workout_completion_screen.dart';

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
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
        // If workout is running and immersive mode is enabled, show simple immersive experience
        if (workoutService.status != WorkoutStatus.stopped &&
            _useImmersiveMode) {
          return ImmersiveWorkoutPlayer(
            onExit: () {
              setState(() {
                _useImmersiveMode = false;
              });
            },
          );
        }

        // Otherwise show normal scaffold with app bar
        return Scaffold(
          appBar: AppBar(
            title: const Text('Workouts'),
            actions: [
              if (workoutService.status != WorkoutStatus.stopped)
                IconButton(
                  onPressed: () => _showViewModeDialog(context),
                  icon: const Icon(Icons.visibility),
                  tooltip: 'Change View Mode',
                ),
            ],
          ),
          body: workoutService.status != WorkoutStatus.stopped
              ? const WorkoutPlayer()
              : _buildWorkoutList(workoutService),
          floatingActionButton: workoutService.status == WorkoutStatus.stopped
              ? FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const WorkoutBuilderScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Create'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildWorkoutList(WorkoutService workoutService) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: workoutService.availableWorkouts.length,
              itemBuilder: (context, index) {
                final workout = workoutService.availableWorkouts[index];
                return _buildWorkoutCard(workout, workoutService);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutCard(Workout workout, WorkoutService workoutService) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showWorkoutDetails(workout, workoutService),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      workout.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    workoutService.formatDuration(workout.totalDuration),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                workout.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              _buildIntervalPreview(workout),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${workout.intervals.length} intervals',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _editWorkout(workout),
                        icon: const Icon(Icons.edit),
                        tooltip: 'Edit Workout',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntervalPreview(Workout workout) {
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: workout.intervals.length,
        itemBuilder: (context, index) {
          final interval = workout.intervals[index];
          final width = (interval.duration.inMinutes * 5.0).clamp(24.0, 100.0);
          final color = _getIntervalColor(interval.type);

          return Container(
            width: width,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _getIntervalLabel(interval),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getIntervalColor(IntervalType type) {
    switch (type) {
      case IntervalType.warmup:
        return AppColors.successLight;
      case IntervalType.work:
        return AppColors.errorLight;
      case IntervalType.rest:
        return AppColors.primary;
      case IntervalType.cooldown:
        return AppColors.warning;
    }
  }

  String _getIntervalLabel(WorkoutInterval interval) {
    switch (interval.mode) {
      case WorkoutMode.power:
        if (interval.hasRamping) {
          return '${interval.powerRamp!.startPower}W→${interval.powerRamp!.endPower}W';
        }
        return '${interval.targetPower}W';
      case WorkoutMode.slope:
        return '${interval.targetSlope}%';
      case WorkoutMode.resistance:
        return '${interval.targetResistance}%';
    }
  }

  void _showWorkoutDetails(Workout workout, WorkoutService workoutService) {
    final trainerService = context.read<TrainerService>();
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(workout.name),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(workout.description),
                const SizedBox(height: 16),
                Text(
                  'Intervals:',
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: workout.intervals.length,
                    itemBuilder: (dialogContext, index) {
                      final interval = workout.intervals[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: _getIntervalColor(interval.type),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        title: Text(interval.name),
                        subtitle: Text(
                          '${workoutService.formatDuration(interval.duration)} - ${_getIntervalLabel(interval)}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (!trainerService.isConnected) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Connect a trainer to start a workout'),
                    ),
                  );
                  return;
                }
                workoutService.startWorkout(workout);
              },
              child: const Text('Start Workout'),
            ),
          ],
        );
      },
    );
  }

  void _editWorkout(Workout workout) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WorkoutBuilderScreen(editingWorkout: workout),
      ),
    );
  }

  void _showViewModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Workout View Mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('Immersive Mode'),
                subtitle: const Text(
                  'Full-screen experience with ambient lighting',
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
