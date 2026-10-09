import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_link_state.dart';
import 'reconnect_controller.dart';

class HeartRateService extends ChangeNotifier {
  static const String _hrServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String _hrMeasurementUuid =
      '00002a37-0000-1000-8000-00805f9b34fb';
  static const String _prefLastDeviceId = 'hr_monitor_last_device_id';
  static const String _prefLastDeviceName = 'hr_monitor_last_device_name';

  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<int>>? _hrSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  int _currentHeartRate = 0;
  bool _isConnected = false;
  bool _isScanning = false;
  String? _connectedDeviceName;
  String? _lastDeviceId;
  String? _lastDeviceName;
  List<ScanResult> _discoveredDevices = [];
  bool _autoReconnect = false;
  String _connectionStatus = 'Disconnected';
  bool _lastScanFoundNothing = false;

  // Auto-reconnect during workouts (see TrainerService for the same policy)
  late final ReconnectController _reconnect = ReconnectController(
    label: 'HR monitor',
    attempt: _attemptReconnect,
    onChanged: _notifyIfAlive,
  );
  bool _workoutReconnectEnabled = false;
  Timer? _watchdogTimer;
  DateTime? _lastPacketAt;
  bool _disposed = false;
  // No packets for this long: show no heart rate instead of the last value.
  static const Duration _staleDataThreshold = Duration(seconds: 5);

  // Getters
  int get currentHeartRate => _currentHeartRate;
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  String? get connectedDeviceName => _connectedDeviceName;
  List<ScanResult> get discoveredDevices => _discoveredDevices;
  String? get lastDeviceName => _lastDeviceName;
  bool get hasLastDevice => _lastDeviceId != null;
  String get connectionStatus => _connectionStatus;
  bool get lastScanFoundNothing => _lastScanFoundNothing;
  DeviceLinkState get linkState =>
      _reconnect.phase ??
      (_isConnected ? DeviceLinkState.connected : DeviceLinkState.disconnected);
  bool get isReconnectAttemptInFlight => _reconnect.attemptInFlight;

  void _updateStatus(String status) {
    _connectionStatus = status;
    notifyListeners();
  }

  HeartRateService() {
    _loadLastDevice();
  }

  Future<void> _loadLastDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastDeviceId = prefs.getString(_prefLastDeviceId);
      _lastDeviceName = prefs.getString(_prefLastDeviceName);
    } catch (e) {
      debugPrint('Error loading last HR device: $e');
    }
  }

  Future<void> _saveLastDevice(String deviceId, String deviceName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastDeviceId, deviceId);
      await prefs.setString(_prefLastDeviceName, deviceName);
      _lastDeviceId = deviceId;
      _lastDeviceName = deviceName;
    } catch (e) {
      debugPrint('Error saving last HR device: $e');
    }
  }

  /// Returns null on success, or an error message string if scan could not start.
  Future<String?> startScan() async {
    if (_isScanning) return null;

    // Check Bluetooth adapter state before attempting scan
    final adapterState = FlutterBluePlus.adapterStateNow;
    if (adapterState != BluetoothAdapterState.on) {
      _updateStatus('Bluetooth is off. Please enable Bluetooth.');
      return 'Bluetooth is off. Please enable Bluetooth and try again.';
    }

    _isScanning = true;
    _lastScanFoundNothing = false;
    _discoveredDevices = [];
    _updateStatus('Scanning for HR devices...');

    // Set up isScanning listener BEFORE startScan() to avoid missing the
    // 'false' emission if the scan ends before we subscribe.
    _isScanningSubscription?.cancel();
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _isScanning) {
        _isScanning = false;
        _lastScanFoundNothing = _discoveredDevices.isEmpty;
        _isScanningSubscription?.cancel();
        _isScanningSubscription = null;
        notifyListeners();
      }
    });

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      _discoveredDevices = results.where((r) {
        // Use contains so both short (180d) and full UUID forms are matched
        return r.advertisementData.serviceUuids.any(
          (uuid) => uuid.toString().toLowerCase().contains('180d'),
        );
      }).toList();

      // Also include devices with known HR brand names as fallback
      final namedDevices = results.where((r) {
        final name = r.device.platformName.toLowerCase();
        return name.isNotEmpty &&
            !_discoveredDevices.any(
              (d) => d.device.remoteId == r.device.remoteId,
            ) &&
            (name.contains('hr') ||
                name.contains('heart') ||
                name.contains('garmin') ||
                name.contains('polar') ||
                name.contains('wahoo') ||
                name.contains('tickr') ||
                name.contains('coospo'));
      }).toList();

      _discoveredDevices.addAll(namedDevices);
      notifyListeners();
    });

    bool scanStarted = false;
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(_hrServiceUuid)],
        timeout: const Duration(seconds: 10),
      );
      scanStarted = true;
    } catch (e) {
      debugPrint('Error starting HR scan with filter: $e');
      // Retry without service filter so any BLE device is visible
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
        scanStarted = true;
      } catch (e2) {
        debugPrint('Fallback scan also failed: $e2');
      }
    }

    if (!scanStarted) {
      _isScanning = false;
      _isScanningSubscription?.cancel();
      _isScanningSubscription = null;
      _scanSubscription?.cancel();
      _updateStatus('Could not start scan. Check Bluetooth permissions.');
      return 'Could not start scan. Check Bluetooth permissions and try again.';
    }

    return null;
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _isScanningSubscription = null;
    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connectToDevice(BluetoothDevice device) {
    // A manual connection supersedes any reconnect still in progress.
    _reconnect.cancel();
    return _connect(device);
  }

  /// [isCancelled] is set when called from the reconnect loop so a cancelled
  /// attempt doesn't commit a stale link.
  Future<bool> _connect(
    BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 10),
    bool Function()? isCancelled,
  }) async {
    try {
      debugPrint(
        'Connecting to HR device: ${device.platformName} (${device.remoteId})',
      );
      _updateStatus(
        'Connecting to ${device.platformName.isNotEmpty ? device.platformName : 'HR Monitor'}...',
      );

      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
      );

      // Monitor connection state
      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint('HR device disconnected');
          _onDisconnected();
        }
      });

      // Discover services
      final services = await device.discoverServices();

      BluetoothService? hrService;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == _hrServiceUuid ||
            service.uuid.toString().toLowerCase().contains('180d')) {
          hrService = service;
          break;
        }
      }

      if (hrService == null) {
        debugPrint('HR service not found on device');
        await device.disconnect();
        _updateStatus('Device does not support Heart Rate service');
        return false;
      }

      // Find HR measurement characteristic
      BluetoothCharacteristic? hrCharacteristic;
      for (var char in hrService.characteristics) {
        if (char.uuid.toString().toLowerCase() == _hrMeasurementUuid ||
            char.uuid.toString().toLowerCase().contains('2a37')) {
          hrCharacteristic = char;
          break;
        }
      }

      if (hrCharacteristic == null) {
        debugPrint('HR measurement characteristic not found');
        await device.disconnect();
        _updateStatus('HR measurement characteristic not found');
        return false;
      }

      if (isCancelled?.call() ?? false) {
        _connectionStateSubscription?.cancel();
        _connectionStateSubscription = null;
        await device.disconnect();
        return false;
      }

      // Subscribe to HR notifications
      await hrCharacteristic.setNotifyValue(true);
      _hrSubscription?.cancel();
      _hrSubscription = hrCharacteristic.lastValueStream.listen(_handleHrData);
      _lastPacketAt = DateTime.now();
      _startWatchdog();

      _connectedDevice = device;
      _connectedDeviceName = device.platformName.isNotEmpty
          ? device.platformName
          : 'HR Monitor';
      _isConnected = true;
      _autoReconnect = true;

      // Save for quick reconnection
      await _saveLastDevice(device.remoteId.toString(), _connectedDeviceName!);

      debugPrint('HR device connected successfully: $_connectedDeviceName');
      _updateStatus('Connected to $_connectedDeviceName');
      return true;
    } catch (e) {
      debugPrint('Error connecting to HR device: $e');
      _updateStatus('Connection failed: ${e.toString().split('\n').first}');
      return false;
    }
  }

  /// Try to reconnect to the last used device
  Future<bool> reconnectLastDevice() async {
    if (_lastDeviceId == null) return false;

    try {
      debugPrint(
        'Attempting to reconnect to last HR device: $_lastDeviceName ($_lastDeviceId)',
      );

      final device = BluetoothDevice.fromId(_lastDeviceId!);
      return await connectToDevice(device);
    } catch (e) {
      debugPrint('Failed to reconnect to last HR device: $e');
      return false;
    }
  }

  void _handleHrData(List<int> data) {
    if (data.isEmpty) return;

    try {
      final bytes = Uint8List.fromList(data);
      final flags = bytes[0];

      // BLE Heart Rate Measurement spec:
      // Bit 0 of flags: 0 = HR is uint8 (1 byte), 1 = HR is uint16 (2 bytes)
      int heartRate;
      if (flags & 0x01 == 0) {
        // uint8 format
        if (bytes.length < 2) return;
        heartRate = bytes[1];
      } else {
        // uint16 format
        if (bytes.length < 3) return;
        heartRate = bytes[1] | (bytes[2] << 8);
      }

      _lastPacketAt = DateTime.now();

      // Validate HR range
      if (heartRate > 0 && heartRate <= 250) {
        _currentHeartRate = heartRate;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error parsing HR data: $e');
    }
  }

  void _onDisconnected() {
    // Drops while reconnecting are part of a failed attempt, not a new drop.
    if (_reconnect.isActive) return;

    _isConnected = false;
    _watchdogTimer?.cancel();
    _currentHeartRate = 0;
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    final wasDevice = _connectedDevice;
    _connectedDevice = null;
    _connectedDeviceName = null;
    _connectionStatus = 'Disconnected';

    notifyListeners();

    if (!_autoReconnect || wasDevice == null) return;

    if (_workoutReconnectEnabled) {
      debugPrint('HR link dropped mid-workout - reconnecting');
      _reconnect.start();
      return;
    }

    // Outside workouts, a single quiet attempt
    debugPrint('Attempting auto-reconnect to HR device...');
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected) {
        reconnectLastDevice();
      }
    });
  }

  /// Called by WorkoutService as a workout starts and stops. While [enabled],
  /// a drop triggers silent reconnect attempts before the link is reported
  /// as [DeviceLinkState.lost].
  void configureAutoReconnect({required bool enabled}) {
    _workoutReconnectEnabled = enabled;
    if (!enabled && _reconnect.isActive) {
      // Workout is over; stop chasing the monitor.
      _reconnect.cancel();
      notifyListeners();
    }
  }

  /// Immediate reconnect attempt, for the "Retry now" action on the banner.
  Future<void> retryConnection() => _reconnect.retryNow();

  Future<bool> _attemptReconnect(bool Function() isCancelled) async {
    final deviceId = _lastDeviceId;
    if (deviceId == null) return false;
    return _connect(
      BluetoothDevice.fromId(deviceId),
      timeout: ReconnectController.attemptTimeout,
      isCancelled: isCancelled,
    );
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final lastPacketAt = _lastPacketAt;
      if (!_isConnected || lastPacketAt == null || _currentHeartRate == 0) {
        return;
      }
      if (DateTime.now().difference(lastPacketAt) >= _staleDataThreshold) {
        _currentHeartRate = 0;
        notifyListeners();
      }
    });
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  Future<void> disconnect() async {
    _autoReconnect = false;
    _reconnect.cancel();
    _watchdogTimer?.cancel();
    _hrSubscription?.cancel();
    _hrSubscription = null;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting HR device: $e');
    }

    _connectedDevice = null;
    _connectedDeviceName = null;
    _isConnected = false;
    _currentHeartRate = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autoReconnect = false;
    _reconnect.cancel();
    _watchdogTimer?.cancel();
    _hrSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }
}
