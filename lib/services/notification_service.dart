import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService with WidgetsBindingObserver {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _appInForeground = true;

  static const String _channelId = 'workout_completion';
  static const String _channelName = 'Workout Completion';
  static const int _completionNotificationId = 1001;

  static const String _connectionChannelId = 'device_connection';
  static const String _connectionChannelName = 'Sensor Connection';
  static const int _connectionLostNotificationId = 1002;

  Future<void> init() async {
    if (_initialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _plugin.initialize(settings: settings);

    // Create the high-importance channel for completion popups
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Pop-up notification when a workout finishes',
      importance: Importance.high,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    const AndroidNotificationChannel connectionChannel =
        AndroidNotificationChannel(
          _connectionChannelId,
          _connectionChannelName,
          description: 'Alert when a sensor disconnects during a workout',
          importance: Importance.high,
        );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(connectionChannel);

    // Request POST_NOTIFICATIONS permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    debugPrint('NotificationService initialized');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> showWorkoutCompleteNotification({
    required String workoutName,
    required String duration,
  }) async {
    if (!_initialized) await init();
    if (_appInForeground) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Pop-up notification when a workout finishes',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
          ticker: 'Workout complete',
        );

    await _plugin.show(
      id: _completionNotificationId,
      title: 'Workout Complete!',
      body: '$workoutName  ·  $duration',
      notificationDetails: const NotificationDetails(android: androidDetails),
    );

    debugPrint('Workout complete notification shown');
  }

  /// One notification for every lost sensor; calling again updates it in
  /// place without alerting a second time.
  Future<void> showDeviceConnectionLostNotification({
    required bool trainerLost,
    required bool hrLost,
  }) async {
    if (!_initialized) await init();
    if (_appInForeground) return;

    final String title;
    final String body;
    if (trainerLost && hrLost) {
      title = 'Trainer and heart rate monitor disconnected';
      body = 'Power, speed and heart rate are not being recorded.';
    } else if (trainerLost) {
      title = 'Trainer connection lost';
      body = 'Power and speed are not being recorded.';
    } else {
      title = 'Heart rate monitor disconnected';
      body = 'Heart rate is not being recorded.';
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _connectionChannelId,
          _connectionChannelName,
          channelDescription: 'Alert when a sensor disconnects during a workout',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
          onlyAlertOnce: true,
          ticker: 'Sensor connection lost',
        );

    await _plugin.show(
      id: _connectionLostNotificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );

    debugPrint('Connection lost notification shown: $title');
  }

  Future<void> cancelDeviceConnectionLostNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(id: _connectionLostNotificationId);
  }
}
