import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothService extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  final List<BluetoothDevice> _discoveredDevices = [];
  bool _isScanning = false;
  bool _isConnected = false;
  String _connectionStatus = 'Disconnected';

  BluetoothDevice? get connectedDevice => _connectedDevice;
  List<BluetoothDevice> get discoveredDevices => _discoveredDevices;
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  String get connectionStatus => _connectionStatus;

  Future<bool> initialize() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        _updateConnectionStatus('Bluetooth not supported on this device');
        return false;
      }

      // Request all required permissions
      final permissionResults = await _requestPermissions();
      if (!permissionResults) {
        return false;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _updateConnectionStatus('Please turn on Bluetooth');
        return false;
      }

      _updateConnectionStatus('Ready to scan');
      return true;
    } catch (e) {
      _updateConnectionStatus('Initialization error: $e');
      return false;
    }
  }

  Future<bool> _requestPermissions() async {
    try {
      // For Android 12+ (API 31+), we need specific Bluetooth permissions
      final Map<Permission, PermissionStatus> permissions = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ].request();

      // Check if all required permissions are granted
      final bluetoothScanGranted =
          permissions[Permission.bluetoothScan] == PermissionStatus.granted;
      final bluetoothConnectGranted =
          permissions[Permission.bluetoothConnect] == PermissionStatus.granted;
      final locationGranted =
          permissions[Permission.locationWhenInUse] == PermissionStatus.granted;

      if (!bluetoothScanGranted) {
        _updateConnectionStatus('Bluetooth scan permission denied');
        return false;
      }

      if (!bluetoothConnectGranted) {
        _updateConnectionStatus('Bluetooth connect permission denied');
        return false;
      }

      if (!locationGranted) {
        _updateConnectionStatus(
          'Location permission required for Bluetooth scanning',
        );
        return false;
      }

      return true;
    } catch (e) {
      // Fallback for older Android versions or iOS
      try {
        final bluetoothPermission = await Permission.bluetooth.request();
        final locationPermission = await Permission.locationWhenInUse.request();

        if (bluetoothPermission != PermissionStatus.granted) {
          _updateConnectionStatus('Bluetooth permission denied');
          return false;
        }

        if (locationPermission != PermissionStatus.granted) {
          _updateConnectionStatus(
            'Location permission required for Bluetooth scanning',
          );
          return false;
        }

        return true;
      } catch (fallbackError) {
        _updateConnectionStatus('Permission error: $fallbackError');
        return false;
      }
    }
  }

  /// Returns null on success, or an error message string if scan could not start.
  Future<String?> startScan() async {
    if (_isScanning) return null;

    // Check Bluetooth adapter state before attempting scan
    final adapterState = FlutterBluePlus.adapterStateNow;
    if (adapterState != BluetoothAdapterState.on) {
      _updateConnectionStatus('Bluetooth is off');
      return 'Bluetooth is off. Please enable Bluetooth and try again.';
    }

    try {
      _discoveredDevices.clear();
      _isScanning = true;
      _updateConnectionStatus('Scanning for devices...');

      await FlutterBluePlus.startScan(
        withServices: [
          Guid("00001826-0000-1000-8000-00805f9b34fb"),
        ], // FTMS Service
        timeout: const Duration(seconds: 10),
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            if (!_discoveredDevices.any(
              (device) => device.remoteId == result.device.remoteId,
            )) {
              _discoveredDevices.add(result.device);
              notifyListeners();
            }
          }
        },
        onError: (e) {
          _updateConnectionStatus('Scan error: $e');
          _isScanning = false;
          notifyListeners();
        },
        onDone: () {
          _isScanning = false;
          if (_discoveredDevices.isEmpty) {
            _updateConnectionStatus(
              'No devices found. Make sure your trainer is powered on.',
            );
          }
          notifyListeners();
        },
      );

      await Future.delayed(const Duration(seconds: 10));
      await stopScan();
      return null;
    } catch (e) {
      _updateConnectionStatus('Scan error: $e');
      _isScanning = false;
      notifyListeners();
      return 'Could not start scan. Check Bluetooth permissions and try again.';
    }
  }

  Future<void> stopScan() async {
    if (!_isScanning) return;

    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _isScanning = false;
      if (_discoveredDevices.isEmpty) {
        _updateConnectionStatus(
          'No devices found. Make sure your trainer is powered on.',
        );
      } else {
        _updateConnectionStatus('Scan completed');
      }
      notifyListeners();
    } catch (e) {
      _isScanning = false;
      _updateConnectionStatus('Stop scan error: $e');
      notifyListeners();
    }
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _updateConnectionStatus('Connecting to ${device.platformName}...');

      await device.connect(
        timeout: const Duration(seconds: 15),
        license: License.nonprofit,
      );
      _connectedDevice = device;
      _isConnected = true;

      _connectionSubscription = device.connectionState.listen(
        (state) {
          _isConnected = state == BluetoothConnectionState.connected;
          if (!_isConnected) {
            _connectedDevice = null;
            _updateConnectionStatus('Disconnected');
          } else {
            _updateConnectionStatus('Connected to ${device.platformName}');
          }
          notifyListeners();
        },
        onError: (e) {
          _isConnected = false;
          _connectedDevice = null;
          _updateConnectionStatus('Connection error: $e');
          notifyListeners();
        },
      );

      _updateConnectionStatus('Connected to ${device.platformName}');
      notifyListeners();
      return true;
    } catch (e) {
      _updateConnectionStatus('Connection failed: $e');
      _isConnected = false;
      _connectedDevice = null;
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice == null) return;

    try {
      await _connectedDevice!.disconnect();
      _connectionSubscription?.cancel();
      _connectedDevice = null;
      _isConnected = false;
      _updateConnectionStatus('Disconnected');
      notifyListeners();
    } catch (e) {
      _connectedDevice = null;
      _isConnected = false;
      _updateConnectionStatus('Disconnect error: $e');
      notifyListeners();
    }
  }

  Future<void> openPermissionSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      _updateConnectionStatus('Could not open settings: $e');
    }
  }

  Future<bool> checkPermissions() async {
    try {
      final bluetoothScanStatus = await Permission.bluetoothScan.status;
      final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
      final locationStatus = await Permission.locationWhenInUse.status;

      return bluetoothScanStatus.isGranted &&
          bluetoothConnectStatus.isGranted &&
          locationStatus.isGranted;
    } catch (e) {
      // Fallback check for older versions
      try {
        final bluetoothStatus = await Permission.bluetooth.status;
        final locationStatus = await Permission.locationWhenInUse.status;
        return bluetoothStatus.isGranted && locationStatus.isGranted;
      } catch (fallbackError) {
        return false;
      }
    }
  }

  void _updateConnectionStatus(String status) {
    _connectionStatus = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _connectedDevice?.disconnect().catchError((_) {});
    super.dispose();
  }
}
