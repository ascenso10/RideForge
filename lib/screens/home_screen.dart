import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import '../config/feature_flags.dart';
import '../services/bluetooth_service.dart' as app_bluetooth;
import '../services/trainer_service.dart';
import '../services/heart_rate_service.dart';
import '../services/strava_service.dart';
import 'trainer_control_screen.dart';
import 'workout_screen.dart';
import 'debug_screen.dart';
import 'trainer_settings_screen.dart';
import 'hr_monitor_screen.dart';
import 'strava_settings_screen.dart';
import 'garmin_settings_screen.dart';
import 'gpx_track_list_screen.dart';
import 'workout_history_screen.dart';
import '../widgets/animated_transitions.dart';
import 'help_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _stravaConnected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForUpdate();
      await _checkAndShowDisclaimer();
      if (mounted) {
        context.read<app_bluetooth.BluetoothService>().initialize();
      }
    });
    _loadStravaStatus();
  }

  Future<void> _loadStravaStatus() async {
    await StravaService.instance.loadCredentials();
    if (mounted) {
      setState(() => _stravaConnected = StravaService.instance.isConnected);
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (_) {
      // Not on Play Store (debug/sideload) — silently ignore
    }
  }

  Future<void> _checkAndShowDisclaimer() async {
    final prefs = await SharedPreferences.getInstance();
    final accepted = prefs.getBool('disclaimer_accepted') ?? false;
    if (!accepted && mounted) {
      await _showDisclaimerDialog();
    }
  }

  Future<void> _showDisclaimerDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppColors.warning,
              size: 28,
            ),
            SizedBox(width: 10),
            Text('Important Notice'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Use at Your Own Risk',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              SizedBox(height: 10),
              Text(
                'Ride Forge is provided as-is, without any warranties or guarantees of any kind, express or implied. By using this app you accept full responsibility for your own safety.',
              ),
              SizedBox(height: 12),
              Text(
                'Validated Hardware',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              SizedBox(height: 6),
              Text(
                'This app has developed for the Van Rysel D100 smart trainer. Compatibility with other devices is not guaranteed and may result in unexpected behaviour.',
              ),
              SizedBox(height: 12),
              Text(
                'By tapping "I Understand" you acknowledge that you have read this notice and agree to use the app at your own risk.',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('disclaimer_accepted', true);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('I Understand'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Forge'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const TrainerSettingsScreen(),
              ),
            ),
            icon: const Icon(Icons.settings),
            tooltip: 'Trainer Settings',
          ),
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => const HelpScreen())),
            icon: const Icon(Icons.help_outline),
            tooltip: 'Help & FAQ',
          ),
          if (FeatureFlags.showDebugInfo)
            Consumer<TrainerService>(
              builder: (context, trainerService, child) {
                return IconButton(
                  onPressed: trainerService.isConnected
                      ? () => Navigator.of(context).push(
                          SlidePageRoute(
                            child: const DebugScreen(),
                            beginOffset: const Offset(1.0, 0.0),
                          ),
                        )
                      : null,
                  icon: const Icon(Icons.bug_report),
                  tooltip: 'Debug Data',
                );
              },
            ),
        ],
      ),
      body: Consumer2<app_bluetooth.BluetoothService, TrainerService>(
        builder: (context, bluetoothService, trainerService, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildConnectionStatus(bluetoothService, trainerService),
                const SizedBox(height: 12),
                if (!trainerService.isConnected)
                  _buildScanRow(bluetoothService, trainerService),
                if (_showPermissionHelp(bluetoothService.connectionStatus))
                  _buildPermissionHelp(bluetoothService),
                if (bluetoothService.discoveredDevices.isNotEmpty &&
                    !trainerService.isConnected) ...[
                  const SizedBox(height: 16),
                  _buildDeviceList(bluetoothService, trainerService),
                ],
                const SizedBox(height: 20),
                _buildStartSection(context, trainerService),
                const SizedBox(height: 24),
                _buildQuickActionsGrid(context),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _buildFeedbackButton()),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _buildSupportButton()),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Connection status ─────────────────────────────────────────────────────

  Widget _buildConnectionStatus(
    app_bluetooth.BluetoothService bluetooth,
    TrainerService trainer,
  ) {
    final isConnected = trainer.isConnected;
    final deviceName = trainer.connectedDeviceName;

    return AnimatedDataCard(
      slideDirection: const Offset(0.0, -0.3),
      child: Hero(
        tag: 'connection_status',
        child: Material(
          type: MaterialType.transparency,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppColors.successContainer
                          : AppColors.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isConnected
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth_disabled,
                      color: isConnected
                          ? AppColors.success
                          : AppColors.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isConnected && deviceName != null
                              ? deviceName
                              : 'No Trainer Connected',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: isConnected
                                    ? AppColors.onSurface
                                    : AppColors.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isConnected
                              ? 'Ready for workouts'
                              : bluetooth.connectionStatus,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (isConnected)
                    IconButton(
                      onPressed: () {
                        trainer.disconnect();
                        bluetooth.disconnect();
                      },
                      icon: const Icon(Icons.bluetooth_disabled),
                      tooltip: 'Disconnect',
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.error,
                        backgroundColor: AppColors.error.withValues(
                          alpha: 0.08,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Scan / disconnect row ─────────────────────────────────────────────────

  Widget _buildScanRow(
    app_bluetooth.BluetoothService bluetooth,
    TrainerService trainer,
  ) {
    return AnimatedDataCard(
      slideDirection: const Offset(-0.3, 0.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: bluetooth.isScanning
                  ? null
                  : () => _handleScanPressed(bluetooth),
              icon: bluetooth.isScanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bluetooth_searching),
              label: Text(
                bluetooth.isScanning ? 'Scanning…' : 'Scan for Trainers',
              ),
            ),
          ),
          if (bluetooth.isConnected) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {
                trainer.disconnect();
                bluetooth.disconnect();
              },
              icon: const Icon(Icons.bluetooth_disabled),
              label: const Text('Disconnect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _showPermissionHelp(String status) {
    return status.contains('permission') || status.contains('Permission');
  }

  Widget _buildPermissionHelp(app_bluetooth.BluetoothService bluetooth) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Permission Required',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppColors.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This app needs Bluetooth and Location permissions to scan for and connect to your bike trainer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => bluetooth.openPermissionSettings(),
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Open Settings'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 36),
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ── Device list ───────────────────────────────────────────────────────────

  Future<void> _handleScanPressed(
    app_bluetooth.BluetoothService bluetooth,
  ) async {
    final hasPermissions = await bluetooth.checkPermissions();
    if (!hasPermissions) {
      await bluetooth.initialize();
    } else {
      final error = await bluetooth.startScan();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.orange[800]),
        );
      }
    }
  }

  Future<void> _connectToDevice(
    BluetoothDevice device,
    app_bluetooth.BluetoothService bluetooth,
    TrainerService trainer,
  ) async {
    try {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to trainer…'),
            ],
          ),
        ),
      );

      final bluetoothConnected = await bluetooth.connectToDevice(device);
      if (!bluetoothConnected) {
        if (mounted) {
          Navigator.of(context).pop();
          _showErrorDialog('Failed to connect to Bluetooth device');
        }
        return;
      }

      final trainerConnected = await trainer.connectToTrainer(device);
      if (mounted) {
        Navigator.of(context).pop();
        if (!trainerConnected) {
          _showErrorDialog(
            'Connected but failed to initialise trainer. Make sure this is a compatible FTMS device.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorDialog('Connection error: $e');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: AppColors.error),
            SizedBox(width: 8),
            Text('Connection Failed'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(
    app_bluetooth.BluetoothService bluetooth,
    TrainerService trainer,
  ) {
    return AnimatedDataCard(
      slideDirection: const Offset(0.0, 0.2),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.bluetooth_searching,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Available Trainers',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        'Tap to connect',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: bluetooth.discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = bluetooth.discoveredDevices[index];
                final isConnected =
                    bluetooth.connectedDevice?.remoteId == device.remoteId;

                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isConnected
                          ? AppColors.successContainer
                          : AppColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                      color: isConnected
                          ? AppColors.success
                          : AppColors.primary,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    device.platformName.isNotEmpty
                        ? device.platformName
                        : 'Unknown Device',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    device.remoteId.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: isConnected
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.successContainer,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                          child: Text(
                            'Connected',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success,
                            ),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: () =>
                              _connectToDevice(device, bluetooth, trainer),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Connect'),
                        ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Start training ────────────────────────────────────────────────────────

  Widget _buildStartSection(BuildContext context, TrainerService trainer) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.directions_bike,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Start Training',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Hero(
              tag: 'do_workout_button',
              child: Material(
                type: MaterialType.transparency,
                child: ElevatedButton.icon(
                  onPressed: trainer.isConnected
                      ? () => _showWorkoutTypeDialog(context)
                      : null,
                  icon: const Icon(Icons.play_circle_filled, size: 22),
                  label: const Text('Start Riding'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    backgroundColor: trainer.isConnected
                        ? AppColors.success
                        : null,
                    foregroundColor: Colors.white,
                    textStyle: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            if (!trainer.isConnected) ...[
              const SizedBox(height: 8),
              Text(
                'Connect a trainer above to start a workout',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (trainer.isConnected) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const TrainerControlScreen(),
                  ),
                ),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Manual Control'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Quick actions grid ────────────────────────────────────────────────────

  Widget _buildQuickActionsGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 12),
          child: Text('Manage', style: Theme.of(context).textTheme.titleMedium),
        ),
        Row(
          children: [
            Expanded(
              child: _buildActionTile(
                context: context,
                icon: Icons.directions_bike,
                label: 'Workouts',
                color: AppColors.primary,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WorkoutScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionTile(
                context: context,
                icon: Icons.history,
                label: 'Workout History',
                color: AppColors.cadence,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WorkoutHistoryScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Consumer<HeartRateService>(
                builder: (context, hrService, _) => _buildActionTile(
                  context: context,
                  icon: Icons.favorite,
                  label: 'HR Monitor',
                  color: AppColors.heartRate,
                  connected: hrService.isConnected,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const HrMonitorScreen(),
                    ),
                  ),
                ),
              ),
            ),
            if (StravaService.isAvailable) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  context: context,
                  icon: Icons.directions_bike,
                  label: 'Strava',
                  color: AppColors.accent,
                  connected: _stravaConnected,
                  iconWidget: Image.asset(
                    'assets/icon/strava.png',
                    width: 20,
                    height: 20,
                  ),
                  onTap: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (context) => const StravaSettingsScreen(),
                        ),
                      )
                      .then((_) => _loadStravaStatus()),
                ),
              ),
            ],
          ],
        ),
        // Feature-flagged extras
        if (FeatureFlags.enableGarminUpload ||
            FeatureFlags.enableGpxWorkouts) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (FeatureFlags.enableGarminUpload)
                Expanded(
                  child: _buildActionTile(
                    context: context,
                    icon: Icons.watch,
                    label: 'Garmin',
                    color: AppColors.primary,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const GarminSettingsScreen(),
                      ),
                    ),
                  ),
                ),
              if (FeatureFlags.enableGarminUpload &&
                  FeatureFlags.enableGpxWorkouts)
                const SizedBox(width: 12),
              if (FeatureFlags.enableGpxWorkouts)
                Expanded(
                  child: _buildActionTile(
                    context: context,
                    icon: Icons.terrain,
                    label: 'GPX Routes',
                    color: AppColors.success,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const GpxTrackListScreen(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    String? badge,
    bool connected = false,
    Widget? iconWidget,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: connected
              ? AppColors.success.withValues(alpha: 0.05)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: connected ? AppColors.success : AppColors.outlineVariant,
            width: connected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: iconWidget ?? Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (badge != null) ...[
              const SizedBox(height: 3),
              Text(
                badge,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Feedback button ───────────────────────────────────────────────────────

  Widget _buildFeedbackButton() {
    return _buildSquareOutlinedButton(
      onPressed: _launchFeedbackUrl,
      icon: Icons.feedback_outlined,
      label: 'Send Feedback',
      color: AppColors.primary,
    );
  }

  Future<void> _launchFeedbackUrl() async {
    const email = 'support@ascenso.pt';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=Ride%20Forge%20Feedback',
    );
    bool launched = false;
    try {
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri);
      }
    } catch (_) {}
    if (!launched && mounted) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Send Feedback'),
          content: const Text(
            'No email app found. You can reach us at:\n\n$email',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: email));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email address copied')),
                );
              },
              child: const Text('Copy Email'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  // ── Support button ────────────────────────────────────────────────────────

  Widget _buildSupportButton() {
    return _buildSquareOutlinedButton(
      onPressed: _launchDonateUrl,
      icon: Icons.favorite_outline,
      label: 'Support Development',
      color: AppColors.heartRate,
    );
  }

  Widget _buildSquareOutlinedButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _launchDonateUrl() async {
    const url = 'https://www.paypal.com/donate/?hosted_button_id=J8Y7V6AE3SML2';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open donation page')),
        );
      }
    }
  }

  // ── Workout type dialog ───────────────────────────────────────────────────

  void _showWorkoutTypeDialog(BuildContext context) {
    if (!FeatureFlags.enableGpxWorkouts) {
      Navigator.of(context).push(FadePageRoute(child: const WorkoutScreen()));
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fitness_center, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Choose Workout Type'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(
                    context,
                  ).push(FadePageRoute(child: const WorkoutScreen()));
                },
                icon: const Icon(Icons.pedal_bike),
                label: const Text('Workout Plans'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 50)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const GpxTrackListScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.terrain),
                label: const Text('Follow Track'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
