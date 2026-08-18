import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Service to manage foreground task for background workout tracking
class ForegroundTaskService {
  static final ForegroundTaskService _instance =
      ForegroundTaskService._internal();
  factory ForegroundTaskService() => _instance;
  ForegroundTaskService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Initialize the foreground task service
  Future<void> init() async {
    if (_isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'workout_channel',
        channelName: 'Workout Tracking',
        channelDescription: 'Notification for active workout tracking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
      ),
    );

    _isInitialized = true;
  }

  /// Start the foreground task when a workout begins
  Future<void> startWorkoutTask({required String workoutName}) async {
    if (_isRunning) return;

    await init();

    await FlutterForegroundTask.startService(
      notificationTitle: 'Workout Active',
      notificationText: workoutName,
      notificationIcon: null,
      notificationButtons: [
        const NotificationButton(id: 'open', text: 'Open App'),
      ],
      callback: null,
    );

    _isRunning = true;
  }

  /// Update the notification text (e.g., with elapsed time)
  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!_isRunning) return;

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  /// Stop the foreground task when workout ends
  Future<void> stopWorkoutTask() async {
    if (!_isRunning) return;

    await FlutterForegroundTask.stopService();
    _isRunning = false;
  }

  /// Request to ignore battery optimizations (for better background performance)
  Future<bool> requestBatteryOptimizationExemption() async {
    return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }

  /// Check if battery optimization is disabled for this app
  Future<bool> isBatteryOptimizationDisabled() async {
    return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
  }
}
