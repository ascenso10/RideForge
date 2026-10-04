import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/app_theme.dart';
import 'services/bluetooth_service.dart' as app_bluetooth;
import 'services/trainer_service.dart';
import 'services/heart_rate_service.dart';
import 'services/notification_service.dart';
import 'services/workout_service.dart';
import 'screens/home_screen.dart';
import 'widgets/connection_lost_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const RideForgeApp());
}

class RideForgeApp extends StatelessWidget {
  const RideForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => app_bluetooth.BluetoothService()),
        ChangeNotifierProvider(create: (_) => TrainerService()),
        ChangeNotifierProvider(create: (_) => HeartRateService()),
        ChangeNotifierProxyProvider2<
          TrainerService,
          HeartRateService,
          WorkoutService
        >(
          create: (context) => WorkoutService(
            context.read<TrainerService>(),
            heartRateService: context.read<HeartRateService>(),
          ),
          update: (context, trainerService, heartRateService, workoutService) {
            workoutService?.updateHeartRateService(heartRateService);
            return workoutService ??
                WorkoutService(
                  trainerService,
                  heartRateService: heartRateService,
                );
          },
        ),
      ],
      child: MaterialApp(
        title: 'Ride Forge',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const HomeScreen(),
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ConnectionLostBanner(),
            ),
          ],
        ),
      ),
    );
  }
}
