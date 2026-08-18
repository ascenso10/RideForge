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
}
