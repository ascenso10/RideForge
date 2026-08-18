import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../services/heart_rate_service.dart';

class HrMonitorScreen extends StatefulWidget {
  const HrMonitorScreen({super.key});

  @override
  State<HrMonitorScreen> createState() => _HrMonitorScreenState();
}

class _HrMonitorScreenState extends State<HrMonitorScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HR Monitor')),
      body: Consumer<HeartRateService>(
        builder: (context, hrService, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildConnectionStatus(hrService),
                const SizedBox(height: 24),
                if (hrService.isConnected) ...[
                  _buildLiveHeartRate(hrService),
                  const SizedBox(height: 24),
                  _buildDisconnectButton(hrService),
                ] else ...[
                  _buildScanSection(hrService),
                  if (hrService.hasLastDevice && !hrService.isScanning) ...[
                    const SizedBox(height: 16),
                    _buildReconnectButton(hrService),
                  ],
                  if (hrService.discoveredDevices.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _buildDeviceList(hrService),
                  ] else if (!hrService.isScanning &&
                      hrService.lastScanFoundNothing) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'No HR devices found. Make sure your device is powered on and try scanning again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionStatus(HeartRateService hrService) {
    final isConnected = hrService.isConnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              isConnected ? Icons.favorite : Icons.heart_broken,
              color: isConnected ? Colors.red : Colors.grey,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected
                        ? hrService.connectedDeviceName ?? 'HR Monitor'
                        : 'No HR Monitor Connected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isConnected ? Colors.red[700] : Colors.grey,
                    ),
                  ),
                  if (isConnected)
                    Text(
                      'Receiving heart rate data',
                      style: TextStyle(color: Colors.green[700], fontSize: 13),
                    )
                  else
                    Text(
                      hrService.connectionStatus,
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveHeartRate(HeartRateService hrService) {
    final hr = hrService.currentHeartRate;

    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
        child: Column(
          children: [
            Icon(
              Icons.favorite,
              color: hr > 0 ? Colors.red : Colors.grey,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              hr > 0 ? '$hr' : '--',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red[800],
              ),
            ),
            Text(
              'BPM',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.red[400]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanSection(HeartRateService hrService) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: hrService.isScanning
            ? null
            : () async {
                final error = await hrService.startScan();
                if (error != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(error),
                      backgroundColor: Colors.orange[800],
                    ),
                  );
                }
              },
        icon: hrService.isScanning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.search),
        label: Text(
          hrService.isScanning ? 'Scanning...' : 'Scan for HR Devices',
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildReconnectButton(HeartRateService hrService) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final success = await hrService.reconnectLastDevice();
          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not reconnect. Try scanning instead.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
        icon: const Icon(Icons.bluetooth_connected),
        label: Text(
          'Reconnect to ${hrService.lastDeviceName ?? "last device"}',
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          foregroundColor: Colors.red[700],
          side: BorderSide(color: Colors.red[300]!),
        ),
      ),
    );
  }

  Widget _buildDeviceList(HeartRateService hrService) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.bluetooth_searching, color: Colors.red[700]),
                const SizedBox(width: 8),
                Text(
                  'Discovered Devices',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: hrService.discoveredDevices.length,
            itemBuilder: (context, index) {
              final result = hrService.discoveredDevices[index];
              final device = result.device;
              final name = device.platformName.isNotEmpty
                  ? device.platformName
                  : 'Unknown HR Device';
              final rssi = result.rssi;

              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.red,
                    size: 20,
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${device.remoteId}  ($rssi dBm)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: ElevatedButton(
                  onPressed: () => _connectToDevice(device, hrService),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('Connect'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectButton(HeartRateService hrService) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => hrService.disconnect(),
        icon: const Icon(Icons.bluetooth_disabled),
        label: const Text('Disconnect'),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: Colors.grey[700],
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Future<void> _connectToDevice(
    BluetoothDevice device,
    HeartRateService hrService,
  ) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting to HR monitor...'),
          ],
        ),
      ),
    );

    final success = await hrService.connectToDevice(device);

    if (mounted) {
      Navigator.of(context).pop(); // Close loading dialog

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to HR device'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
