import 'package:flutter/material.dart';
import '../services/garmin_service.dart';

class GarminSettingsScreen extends StatefulWidget {
  const GarminSettingsScreen({super.key});

  @override
  State<GarminSettingsScreen> createState() => _GarminSettingsScreenState();
}

class _GarminSettingsScreenState extends State<GarminSettingsScreen> {
  final GarminService _garminService = GarminService();
  bool _isConnected = false;
  String? _userName;
  String? _userId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGarminStatus();
  }

  Future<void> _loadGarminStatus() async {
    final isConnected = await _garminService.isConnected();
    final userInfo = await _garminService.getUserInfo();

    setState(() {
      _isConnected = isConnected;
      _userName = userInfo['userName'];
      _userId = userInfo['userId'];
      _isLoading = false;
    });
  }

  /// OAuth 1.0a, 2-step OOB flow:
  ///   1. Get request token → open Garmin auth page in browser.
  ///   2. User authorizes & receives a PIN → user pastes it here.
  ///   3. Exchange PIN for permanent access tokens.
  Future<void> _connectToGarmin() async {
    setState(() => _isLoading = true);

    String authUrl;
    try {
      authUrl = await _garminService.startAuthentication();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start authentication: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    // Open the browser for the user to authorize
    try {
      await _garminService.launchAuthorizationUrl(authUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open browser: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = false);

    // Ask the user to paste the PIN shown on Garmin's page
    if (!mounted) return;
    final verifier = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinEntryDialog(),
    );

    if (verifier == null || verifier.trim().isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await _garminService.completeAuthentication(verifier);
      await _loadGarminStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to Garmin successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _disconnectFromGarmin() async {
    await _garminService.disconnect();

    setState(() {
      _isConnected = false;
      _userName = null;
      _userId = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Disconnected from Garmin'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _openDeveloperPortal() async {
    try {
      await _garminService.openDeveloperPortal();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open developer portal: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Garmin Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConnectionStatusCard(),
                  const SizedBox(height: 24),
                  if (!_isConnected) _buildSetupInstructions(),
                  if (_isConnected) _buildWorkoutSyncSettings(),
                ],
              ),
            ),
    );
  }

  Widget _buildConnectionStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isConnected ? Icons.link : Icons.link_off,
                  color: _isConnected ? Colors.blue : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Garmin Connect',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isConnected && _userName != null
                            ? 'Connected as $_userName'
                            : _isConnected
                            ? 'Connected (User ID: $_userId)'
                            : 'Not connected',
                        style: TextStyle(
                          color: _isConnected ? Colors.blue : Colors.grey[600],
                          fontWeight: _isConnected ? FontWeight.w500 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isConnected
                    ? _disconnectFromGarmin
                    : _connectToGarmin,
                icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                label: Text(_isConnected ? 'Disconnect' : 'Connect to Garmin'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: _isConnected ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupInstructions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Setup Instructions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Developer Credentials Required',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'To use Garmin Connect integration:\n\n'
                    '1. Register as a Garmin Developer\n'
                    '2. Create an app in the Developer Portal\n'
                    '3. Get your OAuth Consumer Key & Secret\n'
                    '4. Set them in garmin_service.dart\n\n'
                    'Then tap "Connect to Garmin" — your browser will open '
                    'for authorization and you\'ll receive a PIN to paste back here.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openDeveloperPortal,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Garmin Developer Portal'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.code, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'API Details',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Auth: OAuth 1.0a (HMAC-SHA1)\n'
                    'File format: FIT\n'
                    'Upload: /wellness-api/rest/backfill/activity/{userId}',
                    style: TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutSyncSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Sync Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Configure how your workouts are uploaded to Garmin Connect:',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Upload Options',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'After each workout, you\'ll be able to:\n'
                    '• Upload FIT files directly to Garmin Connect\n'
                    '• View your activities in the Garmin Connect app\n'
                    '• Track training progress and metrics\n\n'
                    'Power, speed, cadence, and heart rate data are all included.',
                    style: TextStyle(fontSize: 13),
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

/// Dialog that prompts the user to enter the PIN/verifier shown by Garmin
/// after authorizing the app in the browser.
class _PinEntryDialog extends StatefulWidget {
  const _PinEntryDialog();

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Garmin PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'After authorizing the app in your browser, Garmin will display a PIN.\n\n'
            'Paste or type the PIN below:',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PIN / Verifier code',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.pin),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Confirm')),
      ],
    );
  }

  void _submit() {
    final pin = _controller.text.trim();
    Navigator.of(context).pop(pin.isEmpty ? null : pin);
  }
}
