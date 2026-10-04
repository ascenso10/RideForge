import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/device_link_state.dart';
import '../services/heart_rate_service.dart';
import '../services/trainer_service.dart';
import '../services/workout_service.dart';

/// Warning shown over any screen when the trainer and/or heart rate monitor
/// drop during a workout and the silent auto-reconnect attempts have failed.
///
/// Both sensors usually drop together, so they share this one banner rather
/// than stacking separate pop-ups. Mounted once above the navigator (see
/// `MaterialApp.builder` in main.dart), so it appears in every workout view.
class ConnectionLostBanner extends StatefulWidget {
  const ConnectionLostBanner({super.key});

  @override
  State<ConnectionLostBanner> createState() => _ConnectionLostBannerState();
}

class _ConnectionLostBannerState extends State<ConnectionLostBanner> {
  bool _wasVisible = false;
  // Last lost combination, kept while the card slides out so it doesn't
  // collapse mid-animation.
  bool _shownTrainerLost = false;
  bool _shownHrLost = false;

  @override
  Widget build(BuildContext context) {
    return Consumer3<TrainerService, HeartRateService, WorkoutService>(
      builder: (context, trainer, heartRate, workout, child) {
        final workoutActive =
            workout.status == WorkoutStatus.running ||
            workout.status == WorkoutStatus.paused;
        final trainerLost = trainer.linkState == DeviceLinkState.lost;
        final hrLost = heartRate.linkState == DeviceLinkState.lost;
        final visible = workoutActive && (trainerLost || hrLost);

        if (visible && !_wasVisible) {
          // Grab attention: the rider is usually looking at the bike, not
          // the screen.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => HapticFeedback.heavyImpact(),
          );
        }
        _wasVisible = visible;
        if (visible) {
          _shownTrainerLost = trainerLost;
          _shownHrLost = hrLost;
        }

        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, -1.2),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _buildCard(
                    context,
                    trainer: trainer,
                    heartRate: heartRate,
                    workout: workout,
                    trainerLost: _shownTrainerLost,
                    hrLost: _shownHrLost,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required TrainerService trainer,
    required HeartRateService heartRate,
    required WorkoutService workout,
    required bool trainerLost,
    required bool hrLost,
  }) {
    final trainerName = trainer.connectedDeviceName ?? 'your trainer';
    final hrName = heartRate.lastDeviceName ?? 'your heart rate monitor';
    final retrying =
        (trainerLost && trainer.isReconnectAttemptInFlight) ||
        (hrLost && heartRate.isReconnectAttemptInFlight);
    final textTheme = Theme.of(context).textTheme;

    final String title;
    final String notRecorded;
    final String devices;
    if (trainerLost && hrLost) {
      title = 'Trainer and heart rate monitor disconnected';
      notRecorded = 'Power, speed and heart rate are';
      devices = '$trainerName and $hrName are';
    } else if (trainerLost) {
      title = 'Trainer connection lost';
      notRecorded = 'Power and speed are';
      devices = '$trainerName is';
    } else {
      title = 'Heart rate monitor disconnected';
      notRecorded = 'Heart rate is';
      devices = '$hrName is';
    }

    return Material(
      // Losing the trainer stops the ride data; losing HR alone is milder.
      color: trainerLost ? AppColors.error : AppColors.warning,
      elevation: 8,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  trainerLost ? Icons.bluetooth_disabled : Icons.heart_broken,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        retrying
                            ? 'Trying to reconnect…'
                            : '$notRecorded not being recorded. Make sure '
                                  '$devices powered on and nearby.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (trainerLost && workout.status == WorkoutStatus.running)
                  TextButton(
                    onPressed: workout.pauseWorkout,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Pause workout'),
                  ),
                TextButton.icon(
                  onPressed: retrying
                      ? null
                      : () {
                          if (trainerLost) trainer.retryConnection();
                          if (hrLost) heartRate.retryConnection();
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: 0.7,
                    ),
                  ),
                  icon: retrying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
