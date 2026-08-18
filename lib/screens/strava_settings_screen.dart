import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/strava_service.dart';

class StravaSettingsScreen extends StatefulWidget {
  const StravaSettingsScreen({super.key});

  @override
  State<StravaSettingsScreen> createState() => _StravaSettingsScreenState();
}

class _StravaSettingsScreenState extends State<StravaSettingsScreen> {
  bool _isConnected = false;
  String? _athleteName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStravaStatus();
  }

  Future<void> _loadStravaStatus() async {
    await StravaService.instance.loadCredentials();
    if (mounted) {
      setState(() {
        _isConnected = StravaService.instance.isConnected;
        _athleteName = StravaService.instance.athleteName;
        _isLoading = false;
      });
    }
  }

  Future<void> _connectToStrava() async {
    setState(() => _isLoading = true);

    final success = await StravaService.instance.authenticate();

    if (!mounted) return;

    if (success) {
      setState(() {
        _isConnected = StravaService.instance.isConnected;
        _athleteName = StravaService.instance.athleteName;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connected as ${StravaService.instance.athleteName ?? 'Athlete'}',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect to Strava.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _disconnectFromStrava() async {
    await StravaService.instance.disconnect();

    if (!mounted) return;

    setState(() {
      _isConnected = false;
      _athleteName = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disconnected from Strava'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Strava Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConnectionCard(),
                  if (_isConnected) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildSyncInfoCard(),
                  ],
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // Connection card
  // ---------------------------------------------------------------------------

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? AppColors.successContainer
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    _isConnected ? Icons.link : Icons.link_off,
                    color: _isConnected
                        ? AppColors.success
                        : AppColors.onSurfaceVariant,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Strava Connection',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _isConnected && _athleteName != null
                          ? _buildConnectedChip()
                          : Text(
                              'Not connected',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.onSurfaceVariant),
                            ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isConnected
                    ? _disconnectFromStrava
                    : _connectToStrava,
                icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                label: Text(_isConnected ? 'Disconnect' : 'Connect to Strava'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isConnected
                      ? AppColors.error
                      : AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedChip() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 14),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _athleteName!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sync info card (shown only when connected)
  // ---------------------------------------------------------------------------

  Widget _buildSyncInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Sync Settings',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Automatic Upload',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'After each workout you\'ll be offered the option to upload '
                    'to Strava. Only concrete metrics (power, speed, time, '
                    'distance) are included — no personal data.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
