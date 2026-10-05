import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/trainer_capabilities.dart';
import '../config/debug_config.dart';

class TrainerData {
  final double speed;
  final double power;
  final double cadence;
  final int heartRate;
  final double distance;
  final DateTime timestamp;

  TrainerData({
    required this.speed,
    required this.power,
    required this.cadence,
    required this.heartRate,
    required this.distance,
    required this.timestamp,
  });
}

class TrainerService extends ChangeNotifier {
  BluetoothCharacteristic? _indoorBikeDataCharacteristic;
  BluetoothCharacteristic? _fitnessMachineControlPointCharacteristic;
  BluetoothCharacteristic? _supportedResistanceLevelRangeCharacteristic;
  BluetoothCharacteristic? _supportedInclinationRangeCharacteristic;
  BluetoothCharacteristic? _supportedPowerRangeCharacteristic;

  StreamSubscription<List<int>>? _dataSubscription;
  StreamSubscription<List<int>>? _controlPointSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  // ignore: unused_field -- kept for future reconnect support
  BluetoothDevice? _connectedBluetoothDevice;

  TrainerData? _currentData;
  final List<TrainerData> _dataHistory = [];
  bool _isConnected = false;
  String _status = 'Disconnected';

  // Control settings
  int _targetPower = 100;
  double _targetSlope = 0.0;
  final double _targetWindSpeed = 0.0; // Wind speed in m/s
  double _targetResistance = 0.0; // Now as resistance level (0.0 - 10.0)

  // Power calibration
  double _powerMultiplier = 1.0;
  double _powerOffset = 0.0;

  // Power smoothing filter
  final List<double> _powerReadings = [];
  static const int _powerSmoothingWindow = 5;

  // Debug data storage
  List<int>? _lastRawData;
  int? _lastFlags;
  Map<String, dynamic>? _lastParsedFields;
  DateTime? _lastDataTimestamp;

  // Detected trainer capabilities
  TrainerCapabilities? _detectedCapabilities;

  // Connected device info
  String? _connectedDeviceName;

  // Debug simulation
  Timer? _debugTimer;

  TrainerData? get currentData => _currentData;
  List<TrainerData> get dataHistory => _dataHistory;
  bool get isConnected => _isConnected || DebugConfig.enableDebugMode;
  String get status => _status;
  int get targetPower => _targetPower;
  double get targetSlope => _targetSlope;
  double get targetWindSpeed => _targetWindSpeed;
  double get targetResistance => _targetResistance;
  TrainerCapabilities? get detectedCapabilities => _detectedCapabilities;
  String? get connectedDeviceName => _connectedDeviceName;

  // Constructor
  TrainerService() {
    if (DebugConfig.enableDebugMode) {
      _initializeDebugMode();
    }
  }

  // FTMS Service and Characteristic UUIDs
  static const String _ftmsServiceUuid = "00001826-0000-1000-8000-00805f9b34fb";
  static const String _indoorBikeDataUuid =
      "00002AD2-0000-1000-8000-00805f9b34fb";
  static const String _fitnessMachineControlPointUuid =
      "00002AD9-0000-1000-8000-00805f9b34fb";
  static const String _supportedResistanceLevelRangeUuid =
      "00002AD6-0000-1000-8000-00805f9b34fb";
  static const String _supportedInclinationRangeUuid =
      "00002AD5-0000-1000-8000-00805f9b34fb";
  static const String _supportedPowerRangeUuid =
      "00002AD8-0000-1000-8000-00805f9b34fb";

  Future<bool> connectToTrainer(BluetoothDevice device) async {
    try {
      // Store the device name
      _connectedDeviceName = device.platformName.isNotEmpty
          ? device.platformName
          : 'Unknown Device';

      _updateStatus('Discovering services...');

      List<BluetoothService> services = await device.discoverServices();

      debugPrint('Found ${services.length} services:');
      for (var service in services) {
        debugPrint('Service: ${service.uuid.toString()}');
      }

      BluetoothService? ftmsService;

      // Try exact FTMS UUID match first
      for (var service in services) {
        String serviceUuid = service.uuid.toString().toLowerCase();
        debugPrint('Checking service: $serviceUuid');
        if (serviceUuid == _ftmsServiceUuid.toLowerCase()) {
          ftmsService = service;
          debugPrint('Found FTMS service with exact UUID match');
          break;
        }
      }

      // Fallback: Look for services with similar UUIDs (some trainers use different formats)
      if (ftmsService == null) {
        for (var service in services) {
          String serviceUuid = service.uuid.toString().toLowerCase();
          // Check for 16-bit UUID format (1826)
          if (serviceUuid.contains('1826')) {
            ftmsService = service;
            debugPrint('Found FTMS service with 16-bit UUID: $serviceUuid');
            break;
          }
        }
      }

      if (ftmsService == null) {
        // List all available services for debugging
        String availableServices = services
            .map((s) => s.uuid.toString())
            .join(', ');
        _updateStatus(
          'FTMS service not found. Available services: $availableServices',
        );
        debugPrint(
          'FTMS service not found. Available services: $availableServices',
        );
        return false;
      }

      _updateStatus('Found FTMS service, discovering characteristics...');

      List<BluetoothCharacteristic> characteristics =
          ftmsService.characteristics;
      debugPrint(
        'Found ${characteristics.length} characteristics in FTMS service:',
      );

      for (var characteristic in characteristics) {
        String charUuid = characteristic.uuid.toString().toLowerCase();
        debugPrint(
          'Characteristic: $charUuid, Properties: ${characteristic.properties}',
        );

        // Indoor Bike Data characteristic
        if (charUuid == _indoorBikeDataUuid.toLowerCase() ||
            charUuid.contains('2ad2')) {
          debugPrint('Found Indoor Bike Data characteristic');
          _indoorBikeDataCharacteristic = characteristic;

          if (characteristic.properties.notify) {
            await characteristic.setNotifyValue(true);
            _dataSubscription = characteristic.lastValueStream.listen(
              _handleTrainerData,
            );
            debugPrint('Successfully subscribed to data notifications');
          } else {
            debugPrint(
              'Warning: Indoor Bike Data characteristic does not support notifications',
            );
          }
        }
        // Fitness Machine Control Point characteristic
        else if (charUuid == _fitnessMachineControlPointUuid.toLowerCase() ||
            charUuid.contains('2ad9')) {
          debugPrint('Found Fitness Machine Control Point characteristic');
          _fitnessMachineControlPointCharacteristic = characteristic;

          // Set up response monitoring if the characteristic supports it
          if (characteristic.properties.indicate ||
              characteristic.properties.notify) {
            try {
              if (characteristic.properties.indicate) {
                await characteristic.setNotifyValue(true);
                debugPrint('Enabled control point indications');
              } else if (characteristic.properties.notify) {
                await characteristic.setNotifyValue(true);
                debugPrint('Enabled control point notifications');
              }
              _controlPointSubscription = characteristic.lastValueStream.listen(
                _handleControlPointResponse,
              );
            } catch (e) {
              debugPrint(
                'Failed to enable control point responses (this is common): $e',
              );
            }
          } else {
            debugPrint(
              'Control point does not support indications/notifications',
            );
          }
        }
        // Supported Power Range characteristic
        else if (charUuid == _supportedPowerRangeUuid.toLowerCase() ||
            charUuid.contains('2ad8')) {
          debugPrint('Found Supported Power Range characteristic');
          _supportedPowerRangeCharacteristic = characteristic;
        }
        // Supported Inclination Range characteristic
        else if (charUuid == _supportedInclinationRangeUuid.toLowerCase() ||
            charUuid.contains('2ad5')) {
          debugPrint('Found Supported Inclination Range characteristic');
          _supportedInclinationRangeCharacteristic = characteristic;
        }
        // Supported Resistance Level Range characteristic
        else if (charUuid == _supportedResistanceLevelRangeUuid.toLowerCase() ||
            charUuid.contains('2ad6')) {
          debugPrint('Found Supported Resistance Level Range characteristic');
          _supportedResistanceLevelRangeCharacteristic = characteristic;
        }
      }

      // Check what we found
      bool hasDataChar = _indoorBikeDataCharacteristic != null;
      bool hasControlChar = _fitnessMachineControlPointCharacteristic != null;

      debugPrint('Connection summary:');
      debugPrint('- Indoor Bike Data: ${hasDataChar ? 'Found' : 'Missing'}');
      debugPrint('- Control Point: ${hasControlChar ? 'Found' : 'Missing'}');

      if (!hasDataChar) {
        String availableChars = characteristics
            .map((c) => c.uuid.toString())
            .join(', ');
        _updateStatus(
          'Indoor bike data characteristic not found. Available: $availableChars',
        );
        return false;
      }

      _isConnected = true;
      _connectedBluetoothDevice = device;

      // Monitor connection state to auto-disconnect when bluetooth disconnects
      _connectionStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          debugPrint(
            'Bluetooth device disconnected - cleaning up trainer service',
          );
          disconnect();
        }
      });

      // Read trainer capabilities if characteristics are available (with delay to avoid connection issues)
      Future.delayed(const Duration(seconds: 2), () {
        if (_isConnected) {
          _readTrainerCapabilities();
        }
      });

      _updateStatus(
        'Connected to trainer (Data: ${hasDataChar ? '✓' : '✗'}, Control: ${hasControlChar ? '✓' : '✗'})',
      );
      return true;
    } catch (e) {
      debugPrint('Trainer connection error: $e');
      _updateStatus('Connection error: $e');
      return false;
    }
  }

  void _handleControlPointResponse(List<int> data) {
    if (data.isEmpty) return;

    try {
      final bytes = Uint8List.fromList(data);
      debugPrint(
        'Control Point Response (${data.length} bytes): ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
      );

      // Handle standard FTMS response (3 bytes: response_code, request_opcode, result_code)
      if (data.length >= 3 && bytes[0] == 0x80) {
        final requestOpCode = bytes[1];
        final resultCode = bytes[2];

        final opCodeNames = {
          0x01: 'Reset',
          0x04: 'Set Target Resistance Level',
          0x05: 'Set Target Power',
          0x07: 'Start or Resume',
          0x08: 'Stop or Pause',
          0x11: 'Set Indoor Bike Simulation Parameters',
        };

        final resultCodeNames = {
          0x01: 'Success',
          0x02: 'OpCode Not Supported',
          0x03: 'Invalid Parameter',
          0x04: 'Operation Failed',
          0x05: 'Control Not Permitted',
        };

        final opName =
            opCodeNames[requestOpCode] ??
            'Unknown (0x${requestOpCode.toRadixString(16)})';
        final resultName =
            resultCodeNames[resultCode] ??
            'Unknown (0x${resultCode.toRadixString(16)})';

        debugPrint('Control Point Response: $opName -> $resultName');

        if (resultCode != 0x01) {
          debugPrint('⚠️  Command failed: $opName returned $resultName');
          if (resultCode == 0x02) {
            debugPrint(
              '💡 Tip: This trainer may not support slope/simulation control',
            );
          } else if (resultCode == 0x05) {
            debugPrint(
              '💡 Tip: Try starting training session first or check trainer mode',
            );
          }
        } else {
          debugPrint('✅ Command successful: $opName');
        }
      }
      // Handle non-standard responses (like the 8-byte response you're seeing)
      else {
        debugPrint(
          'ℹ️  Non-standard control point response - this might be trainer-specific data',
        );
        // Don't treat this as an error, just log it
      }
    } catch (e) {
      debugPrint('Error parsing control point response: $e');
    }
  }

  void _handleTrainerData(List<int> data) {
    if (data.length < 4) {
      debugPrint('Received data too short: ${data.length} bytes');
      return;
    }

    try {
      final bytes = Uint8List.fromList(data);

      // Store raw data for debug screen
      _lastRawData = List<int>.from(data);
      _lastDataTimestamp = DateTime.now();

      // Debug: Print raw data
      //debugPrint('Raw data (${data.length} bytes): ${data.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');

      final flags = bytes[0] | (bytes[1] << 8);
      _lastFlags = flags;
      //debugPrint('Flags: 0x${flags.toRadixString(16).padLeft(4, '0')} (${flags.toRadixString(2).padLeft(16, '0')})');

      int offset = 2;
      double speed = 0.0;
      double power = 0.0;
      double cadence = 0.0;
      int heartRate = 0;

      //debugPrint('FTMS Field parsing (offset starts at $offset):');

      // Parse instantaneous speed (if present) - Flag bit 0
      if (flags & 0x01 != 0 && offset + 1 < bytes.length) {
        int rawSpeed = bytes[offset] | (bytes[offset + 1] << 8);
        speed = rawSpeed / 100.0; // FTMS spec: 0.01 km/h resolution
        //debugPrint('  Speed @ offset $offset: $rawSpeed raw -> $speed km/h');
        offset += 2;
      }

      // Parse average speed (if present) - Flag bit 1
      if (flags & 0x02 != 0 && offset + 1 < bytes.length) {
        //int avgSpeed = bytes[offset] | (bytes[offset + 1] << 8);
        //debugPrint('  Avg Speed @ offset $offset: $avgSpeed (skipping)');
        offset += 2;
      }

      // Parse instantaneous cadence (if present) - Flag bit 2
      if (flags & 0x04 != 0 && offset + 1 < bytes.length) {
        int rawCadence = bytes[offset] | (bytes[offset + 1] << 8);
        cadence = rawCadence / 2.0; // FTMS spec: 0.5 rpm resolution
        //debugPrint('  ★ CADENCE @ offset $offset: $rawCadence raw -> $cadence rpm');
        offset += 2;
      }

      // Parse average cadence (if present) - Flag bit 3
      if (flags & 0x08 != 0 && offset + 1 < bytes.length) {
        //int avgCadence = bytes[offset] | (bytes[offset + 1] << 8);
        //debugPrint('  Avg Cadence @ offset $offset: $avgCadence (skipping)');
        offset += 2;
      }

      // Parse total distance (if present) - Flag bit 4
      // FTMS spec: uint24, 1 meter resolution
      double ftmsDistance = _currentData?.distance ?? 0.0;
      if (flags & 0x10 != 0 && offset + 2 < bytes.length) {
        int distanceRaw =
            bytes[offset] |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16);
        ftmsDistance = distanceRaw.toDouble(); // meters
        offset += 3;
      }

      // Parse resistance level (if present) - Flag bit 5
      if (flags & 0x20 != 0 && offset + 1 < bytes.length) {
        //int resistance = bytes[offset] | (bytes[offset + 1] << 8);
        //debugPrint('  Resistance Level @ offset $offset: $resistance (skipping)');
        offset += 2;
      }

      // Parse instantaneous power from bytes 4-5 (trainer-specific location)
      if (flags & 0x40 != 0 && bytes.length >= 6) {
        int rawPower = bytes[4] | (bytes[5] << 8);

        // Handle signed 16-bit value (power can be negative for some trainers)
        if (rawPower > 32767) {
          rawPower = rawPower - 65536;
        }

        power = rawPower.toDouble();
        //debugPrint('  ★ INSTANTANEOUS POWER @ bytes 4-5: $rawPower raw -> $power watts');
      } else if (flags & 0x40 != 0) {
        //debugPrint('  ★ Power flag set but packet too short (need at least 6 bytes)');
      }

      // Try to extract other common values from known positions
      // Many trainers put additional data in fixed positions regardless of flags

      if (bytes.length >= 4) {
        // Check for speed in bytes 2-3
        int possibleSpeed = bytes[2] | (bytes[3] << 8);
        if (possibleSpeed > 0 && possibleSpeed < 10000) {
          // 0-100 km/h in 0.01 resolution
          double speedKmh = possibleSpeed / 100.0;
          if (speedKmh <= 100.0) {
            // Reasonable cycling speed
            speed = speedKmh;
            //debugPrint('  ☆ POSSIBLE SPEED @ bytes 2-3: $possibleSpeed raw -> $speed km/h');
          }
        }
      }

      if (bytes.length >= 12) {
        // Check for heart rate in various positions
        for (int hrPos = 10; hrPos < bytes.length && hrPos < 14; hrPos++) {
          int possibleHR = bytes[hrPos];
          if (possibleHR >= 40 && possibleHR <= 220) {
            // Reasonable HR range
            heartRate = possibleHR;
            debugPrint('  ☆ POSSIBLE HEART RATE @ byte $hrPos: $heartRate bpm');
            break; // Take the first reasonable HR value found
          }
        }
      }

      // Look for distance/time data in remaining bytes
      if (bytes.length >= 16) {
        // Check for larger values that might be time or distance
        for (int pos = 12; pos < bytes.length - 3; pos += 2) {
          int value32 = bytes[pos] | (bytes[pos + 1] << 8);
          if (pos + 3 < bytes.length) {
            int value32Extended =
                value32 | (bytes[pos + 2] << 16) | (bytes[pos + 3] << 24);
            if (value32Extended > 1000 && value32Extended < 1000000) {
              debugPrint(
                '  ☆ LARGE VALUE @ bytes $pos-${pos + 3}: $value32Extended (possible time/distance)',
              );
            }
          }
        }
      }

      // Parse average power (if present) - Flag bit 7
      if (flags & 0x80 != 0 && offset + 1 < bytes.length) {
        // Skip average power for now
        offset += 2;
      }

      // Parse expended energy (if present) - Flag bit 8
      if (flags & 0x100 != 0 && offset + 3 < bytes.length) {
        // Skip expended energy (4 bytes total)
        offset += 4;
      }

      // Parse heart rate (if present) - Flag bit 9
      if (flags & 0x200 != 0 && offset < bytes.length) {
        heartRate = bytes[offset]; // FTMS spec: 1 bpm resolution
        debugPrint('Heart Rate: $heartRate bpm');
        offset += 1;
      }

      // Apply reasonable bounds checking
      if (power < 0) power = 0;
      if (power > 2000) {
        debugPrint(
          'Warning: Power value seems too high: $power watts, capping at 2000W',
        );
        power = 2000;
      }

      // Apply power calibration
      if (power > 0) {
        power = (power * _powerMultiplier) + _powerOffset;
        debugPrint(
          'Calibrated power: ${power}W (multiplier: $_powerMultiplier, offset: $_powerOffset)',
        );
      }

      // Apply power smoothing filter
      if (power > 0) {
        _powerReadings.add(power);
        if (_powerReadings.length > _powerSmoothingWindow) {
          _powerReadings.removeAt(0);
        }

        // Calculate moving average for smoother power readings
        double smoothedPower =
            _powerReadings.reduce((a, b) => a + b) / _powerReadings.length;

        // Only use smoothing if we have enough readings
        if (_powerReadings.length >= 3) {
          power = smoothedPower;
        }
      }

      if (speed < 0) speed = 0;
      if (speed > 100) {
        debugPrint(
          'Warning: Speed value seems too high: $speed km/h, capping at 100 km/h',
        );
        speed = 100;
      }

      if (cadence < 0) cadence = 0;
      if (cadence > 300) {
        debugPrint(
          'Warning: Cadence value seems too high: $cadence rpm, capping at 300 rpm',
        );
        cadence = 300;
      }

      final newData = TrainerData(
        speed: speed,
        power: power,
        cadence: cadence,
        heartRate: heartRate,
        distance: ftmsDistance,
        timestamp: DateTime.now(),
      );

      //debugPrint('Parsed data - Power: ${power}W, Speed: ${speed}km/h, Cadence: ${cadence}rpm, HR: ${heartRate}bpm');

      // Store parsed fields for debug screen
      _lastParsedFields = {
        'speed': speed,
        'power': power,
        'cadence': cadence,
        'heartRate': heartRate,
        'powerBeforeCalibration':
            power / (_powerMultiplier == 0 ? 1 : _powerMultiplier) -
            _powerOffset,
      };

      _currentData = newData;
      _dataHistory.add(newData);

      // Keep only last 1000 data points
      if (_dataHistory.length > 1000) {
        _dataHistory.removeAt(0);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error parsing trainer data: $e');
    }
  }

  Future<bool> setPowerTarget(int watts) async {
    if (_fitnessMachineControlPointCharacteristic == null) return false;

    try {
      _targetPower = watts;

      // FTMS Control Point command: Set Target Power (0x05)
      final command = Uint8List(5);
      command[0] = 0x05; // Set Target Power opcode
      command[1] = watts & 0xFF;
      command[2] = (watts >> 8) & 0xFF;
      command[3] = 0x00;
      command[4] = 0x00;

      await _fitnessMachineControlPointCharacteristic!.write(command);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error setting power target: $e');
      return false;
    }
  }

  /// Set slope target with optional gradient compensation
  Future<bool> setSlopeTargetWithCompensation(
    double originalSlope,
    TrainerCapabilities capabilities,
  ) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'Error: Control point characteristic not available for slope setting',
      );
      return false;
    }

    try {
      // Calculate compensation for the original gradient
      final compensation = capabilities.calculateCompensation(originalSlope);

      debugPrint(
        'Original gradient: ${originalSlope.toStringAsFixed(1)}% -> $compensation',
      );

      // Convert slope % to 0.1% units (signed 16-bit)
      int slopeInt = (compensation.adjustedGradient * 10).round().clamp(
        -32768,
        32767,
      );

      // Create FTMS command with compensation parameters
      final command = _encodeSimulationParams(
        slopeInt,
        rollingResistance: compensation.rollingResistance,
      );

      debugPrint(
        'Setting compensated slope: ${compensation.adjustedGradient.toStringAsFixed(1)}% + compensation',
      );
      debugPrint(
        'Indoor simulation command bytes: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);

      // Handle direct resistance compensation separately if needed
      if (compensation.additionalResistance > 0) {
        debugPrint(
          'Applying additional resistance: ${compensation.additionalResistance.toStringAsFixed(1)}%',
        );
        await setResistancePercentage(compensation.additionalResistance);
      }

      _targetSlope = compensation.adjustedGradient;
      debugPrint('Gradient compensation applied successfully');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error setting compensated slope target: $e');
      return false;
    }
  }

  Future<bool> setSlopeTarget(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'Error: Control point characteristic not available for slope setting',
      );
      return false;
    }

    try {
      _targetSlope = slope;

      // Trainer doesn't follow FTMS spec - slope control is in bytes 3,4 (wind speed position)
      int slopeInt = (slope * 100).round().clamp(-32768, 32767);

      // Create FTMS command - trainer expects slope in bytes 3,4 instead of 1,2
      final command = Uint8List(8);
      command[0] = 0x11; // Set Indoor Bike Simulation Parameters opcode

      // Standard slope position (16-bit signed, 0.1% resolution) - bytes 1,2 - trainer ignores
      command[1] = 0;
      command[2] = 0;

      // Slope control (trainer expects slope here instead of wind speed) - bytes 3,4
      command[3] = slopeInt & 0xFF;
      command[4] = (slopeInt >> 8) & 0xFF;

      // Rolling resistance (16-bit unsigned, 0.0001 resolution) - bytes 5,6 set to zero
      command[5] = 0;
      command[6] = 0;

      // Wind direction - byte 7 set to zero
      command[7] = 0;

      debugPrint(
        'Setting slope target: $slope% -> $slopeInt (in bytes 3,4 due to non-standard trainer)',
      );
      debugPrint(
        'Indoor simulation command bytes: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope command sent successfully');

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error setting slope target: $e');
      return false;
    }
  }

  Future<bool> setResistancePercentage(double level) async {
    if (_fitnessMachineControlPointCharacteristic == null) return false;

    try {
      // Clamp resistance level to 0.0-10.0
      level = level.clamp(0.0, 10.0);
      _targetResistance = level;

      // Convert resistance level to FTMS format (0.1 resolution)
      int resistanceLevel = (level * 10).round(); // 0-100 range (0.0-10.0 * 10)

      debugPrint(
        'Setting resistance: $level -> level $resistanceLevel (0.1 units)',
      );

      // FTMS Control Point command: Set Target Resistance Level (0x04)
      final command = Uint8List(3);
      command[0] = 0x04; // Set Target Resistance Level opcode
      command[1] = resistanceLevel & 0xFF;
      command[2] = (resistanceLevel >> 8) & 0xFF;

      await _fitnessMachineControlPointCharacteristic!.write(command);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error setting resistance level: $e');
      return false;
    }
  }

  // Legacy method for backwards compatibility
  Future<bool> setResistanceLevel(int level) async {
    // Convert level (0-100) to resistance level (0.0-10.0)
    double resistanceLevel = (level / 10.0).clamp(0.0, 10.0);
    return setResistancePercentage(resistanceLevel);
  }

  Future<bool> startTraining() async {
    if (_fitnessMachineControlPointCharacteristic == null) return false;

    try {
      // FTMS Control Point command: Start or Resume (0x07)
      final command = Uint8List(1);
      command[0] = 0x07;

      await _fitnessMachineControlPointCharacteristic!.write(command);
      return true;
    } catch (e) {
      debugPrint('Error starting training: $e');
      return false;
    }
  }

  Future<bool> stopTraining() async {
    if (_fitnessMachineControlPointCharacteristic == null) return false;

    try {
      // FTMS Control Point command: Stop or Pause (0x08)
      final command = Uint8List(1);
      command[0] = 0x08;

      await _fitnessMachineControlPointCharacteristic!.write(command);
      return true;
    } catch (e) {
      debugPrint('Error stopping training: $e');
      return false;
    }
  }

  Future<void> _readTrainerCapabilities() async {
    try {
      debugPrint('Reading trainer capabilities...');

      double maxGradient = 6.0; // Conservative default
      double minGradient = 0.0; // Conservative default (no negative)
      int maxPower = 600; // Conservative default
      double maxResistance = 10.0; // Default fallback
      bool foundInclinationRange = false;
      bool foundPowerRange = false;

      // Read supported inclination range (gradient) with timeout
      if (_supportedInclinationRangeCharacteristic != null) {
        try {
          debugPrint('Attempting to read inclination range characteristic...');
          final inclinationData =
              await _supportedInclinationRangeCharacteristic!.read().timeout(
                const Duration(seconds: 3),
              );

          debugPrint(
            'Inclination data received (${inclinationData.length} bytes): ${inclinationData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
          );

          if (inclinationData.length >= 6) {
            // FTMS specification: 2 bytes each for min, max, increment (in 0.1% resolution)
            // Values are signed 16-bit integers
            int minInclinationRaw =
                (inclinationData[1] << 8) | inclinationData[0];
            int maxInclinationRaw =
                (inclinationData[3] << 8) | inclinationData[2];

            // Handle signed values
            if (minInclinationRaw > 32767) minInclinationRaw -= 65536;
            if (maxInclinationRaw > 32767) maxInclinationRaw -= 65536;

            final minInclination = minInclinationRaw / 10.0;
            final maxInclination = maxInclinationRaw / 10.0;

            // Validate the values are reasonable
            if (maxInclination > 0 && maxInclination <= 30) {
              minGradient = minInclination;
              maxGradient = maxInclination;
              foundInclinationRange = true;
              debugPrint(
                '✓ Successfully read inclination range: $minGradient% to $maxGradient%',
              );
            } else {
              debugPrint('⚠ Inclination values out of range, using defaults');
            }
          }
        } catch (e) {
          debugPrint('Failed to read inclination range: $e');
        }
      } else {
        debugPrint('Inclination range characteristic not available');
      }

      // Read supported power range with timeout
      if (_supportedPowerRangeCharacteristic != null) {
        try {
          debugPrint('Attempting to read power range characteristic...');
          final powerData = await _supportedPowerRangeCharacteristic!
              .read()
              .timeout(const Duration(seconds: 3));

          debugPrint(
            'Power data received (${powerData.length} bytes): ${powerData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
          );

          if (powerData.length >= 6) {
            // FTMS specification: 2 bytes each for min, max, increment (in 1W resolution)
            final minPower = (powerData[1] << 8) | powerData[0];
            final maxPowerRead = (powerData[3] << 8) | powerData[2];

            // Validate the values are reasonable
            if (maxPowerRead > 0 && maxPowerRead <= 3000) {
              maxPower = maxPowerRead;
              foundPowerRange = true;
              debugPrint(
                '✓ Successfully read power range: $minPower to $maxPower W',
              );
            } else {
              debugPrint('⚠ Power value out of range, using default');
            }
          }
        } catch (e) {
          debugPrint('Failed to read power range: $e');
        }
      } else {
        debugPrint('Power range characteristic not available');
      }

      // Read supported resistance level range with timeout
      if (_supportedResistanceLevelRangeCharacteristic != null) {
        try {
          debugPrint('Attempting to read resistance range characteristic...');
          final resistanceData =
              await _supportedResistanceLevelRangeCharacteristic!
                  .read()
                  .timeout(const Duration(seconds: 3));

          debugPrint(
            'Resistance data received (${resistanceData.length} bytes): ${resistanceData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}',
          );

          if (resistanceData.length >= 6) {
            // FTMS specification: 2 bytes each for min, max, increment (in 0.1 resistance level resolution)
            final minResistance =
                ((resistanceData[1] << 8) | resistanceData[0]) / 10.0;
            final maxResistanceRead =
                ((resistanceData[3] << 8) | resistanceData[2]) / 10.0;

            if (maxResistanceRead > 0 && maxResistanceRead <= 20) {
              maxResistance = maxResistanceRead;
              debugPrint(
                '✓ Successfully read resistance range: $minResistance to $maxResistance',
              );
            } else {
              debugPrint('⚠ Resistance value out of range, using default');
            }
          }
        } catch (e) {
          debugPrint('Failed to read resistance range: $e');
        }
      } else {
        debugPrint('Resistance range characteristic not available');
      }

      // Create detected capabilities
      _detectedCapabilities = TrainerCapabilities(
        maxGradient: maxGradient.clamp(0.0, 30.0),
        minGradient: minGradient.clamp(-15.0, 0.0),
        maxPower: maxPower,
        maxResistance: maxResistance.clamp(1.0, 20.0).round(),
        gradientMode: GradientHandlingMode.clamp, // Default to clamp mode
      );

      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('DETECTED TRAINER CAPABILITIES:');
      debugPrint(
        '  Gradient: ${_detectedCapabilities!.minGradient}% to ${_detectedCapabilities!.maxGradient}%',
      );
      debugPrint('  Power: ${_detectedCapabilities!.maxPower}W');
      debugPrint('  Resistance: ${_detectedCapabilities!.maxResistance}');
      debugPrint(
        '  Inclination data: ${foundInclinationRange ? "✓ Read from trainer" : "✗ Using defaults"}',
      );
      debugPrint(
        '  Power data: ${foundPowerRange ? "✓ Read from trainer" : "✗ Using defaults"}',
      );
      debugPrint('═══════════════════════════════════════════════════');

      // WorkoutService listens for this and adopts + persists the detection.
      notifyListeners();
    } catch (e) {
      debugPrint('Error reading trainer capabilities: $e');
      // Set conservative capabilities as fallback
      _detectedCapabilities = TrainerCapabilities(
        maxGradient: 6.0,
        minGradient: 0.0,
        maxPower: 600,
        maxResistance: 10,
        gradientMode: GradientHandlingMode.clamp,
      );
    }
  }

  void disconnect() {
    _dataSubscription?.cancel();
    _controlPointSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _debugTimer?.cancel();
    _indoorBikeDataCharacteristic = null;
    _fitnessMachineControlPointCharacteristic = null;
    _supportedResistanceLevelRangeCharacteristic = null;
    _supportedInclinationRangeCharacteristic = null;
    _supportedPowerRangeCharacteristic = null;
    _detectedCapabilities = null;
    _connectedDeviceName = null;
    _connectedBluetoothDevice = null;
    _isConnected = false;
    _updateStatus('Disconnected');
    notifyListeners();
  }

  void calibratePower({double? multiplier, double? offset}) {
    if (multiplier != null) _powerMultiplier = multiplier;
    if (offset != null) _powerOffset = offset;
    debugPrint(
      'Power calibration updated: multiplier=$_powerMultiplier, offset=$_powerOffset',
    );
    notifyListeners();
  }

  void resetPowerCalibration() {
    _powerMultiplier = 1.0;
    _powerOffset = 0.0;
    debugPrint('Power calibration reset to defaults');
    notifyListeners();
  }

  double get powerMultiplier => _powerMultiplier;
  double get powerOffset => _powerOffset;

  // Debug data getters
  List<int>? get lastRawData => _lastRawData;
  int? get lastFlags => _lastFlags;
  Map<String, dynamic>? get lastParsedFields => _lastParsedFields;
  DateTime? get lastDataTimestamp => _lastDataTimestamp;

  /// Encode FTMS "Set Indoor Bike Simulation Parameters" command
  /// Supports slope, wind speed, and rolling resistance parameters
  Uint8List _encodeSimulationParams(
    int slope, {
    double rollingResistance = 0.0,
  }) {
    final command = Uint8List(8);
    command[0] = 0x11; // Set Indoor Bike Simulation Parameters opcode

    // Slope (16-bit signed, 0.01% resolution)
    command[1] = slope & 0xFF;
    command[2] = (slope >> 8) & 0xFF;

    // Wind speed (16-bit signed, 0.01 m/s resolution) - bytes 3,4 control wind speed
    // To use: final windSpeedInt = (windSpeed * 100).round().clamp(-32768, 32767);
    // command[3] = windSpeedInt & 0xFF; command[4] = (windSpeedInt >> 8) & 0xFF;
    command[3] = 0;
    command[4] = 0;

    // Rolling resistance coefficient (16-bit unsigned, 0.0001 resolution)
    final rollingResistanceInt = (rollingResistance * 10000).round().clamp(
      0,
      65535,
    );
    command[5] = rollingResistanceInt & 0xFF;
    command[6] = (rollingResistanceInt >> 8) & 0xFF;

    // Wind direction remains zero (not used in our implementation)
    command[7] = 0;

    return command;
  }

  /// Initialize trainer for control operations
  /// This ensures the trainer is in the right state to accept commands
  // ignore: unused_element -- kept for future use
  Future<bool> _initializeTrainerForControl() async {
    if (_fitnessMachineControlPointCharacteristic == null) return false;

    try {
      debugPrint('Initializing trainer for control operations...');

      // Step 1: Start training session
      await startTraining();
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 2: Reset any previous settings with a known good command
      await _sendResetCommand();
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 3: Enable simulation mode if needed
      await _enableSimulationMode();
      await Future.delayed(const Duration(milliseconds: 200));

      debugPrint('Trainer initialization complete');
      return true;
    } catch (e) {
      debugPrint('Error initializing trainer for control: $e');
      return false;
    }
  }

  /// Send a reset command to clear any previous settings
  Future<bool> _sendResetCommand() async {
    if (_fitnessMachineControlPointCharacteristic == null) return false;

    try {
      // FTMS Control Point command: Reset (0x01)
      final command = Uint8List(1);
      command[0] = 0x01;

      debugPrint('Sending reset command to trainer...');
      await _fitnessMachineControlPointCharacteristic!.write(command);
      return true;
    } catch (e) {
      debugPrint('Error sending reset command: $e');
      return false;
    }
  }

  /// Enable simulation mode on the trainer
  Future<bool> _enableSimulationMode() async {
    if (_fitnessMachineControlPointCharacteristic == null) return false;

    try {
      // Send a neutral slope command to initialize simulation mode
      final command = _encodeSimulationParams(0); // 0% slope
      debugPrint('Enabling simulation mode with neutral slope...');
      await _fitnessMachineControlPointCharacteristic!.write(command);
      return true;
    } catch (e) {
      debugPrint('Error enabling simulation mode: $e');
      return false;
    }
  }

  /// Verify that a command was accepted by checking trainer response
  // ignore: unused_element -- kept for future use
  Future<void> _verifyCommandAcceptance(
    String commandType,
    double value,
  ) async {
    try {
      debugPrint('Verifying $commandType command acceptance...');

      // For now, we'll just log the attempt
      // In a full implementation, we'd listen to control point responses
      debugPrint(
        '$commandType set to $value - verification not implemented yet',
      );

      // TODO: Implement proper response monitoring when control point notifications are available
    } catch (e) {
      debugPrint('Error verifying command acceptance: $e');
    }
  }

  void _updateStatus(String status) {
    _status = status;
    notifyListeners();
  }

  void _initializeDebugMode() {
    _connectedDeviceName = 'Debug Trainer (Simulated)';
    _updateStatus('Debug Mode - Simulated Connection');

    if (DebugConfig.simulateTrainerData) {
      _startDebugDataSimulation();
    }
  }

  void _startDebugDataSimulation() {
    _debugTimer?.cancel();
    _debugTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Add some variation to make it realistic
      final variation =
          (DateTime.now().millisecondsSinceEpoch % 1000) / 1000 * 0.2 - 0.1;

      _currentData = TrainerData(
        speed: DebugConfig.simulatedSpeed + (variation * 5),
        power: DebugConfig.simulatedPower + (variation * 20),
        cadence: DebugConfig.simulatedCadence + (variation * 10),
        heartRate: DebugConfig.simulatedHeartRate + (variation * 10).round(),
        distance:
            (_currentData?.distance ?? 0) +
            (DebugConfig.simulatedSpeed / 3600), // km
        timestamp: DateTime.now(),
      );

      _dataHistory.add(_currentData!);
      if (_dataHistory.length > 1000) {
        _dataHistory.removeAt(0);
      }

      notifyListeners();
    });
  }

  // Experimental slope testing methods for debugging
  Future<bool> testSlopeMethod1(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 1: Standard FTMS Indoor Bike Simulation (current method)
      int slopeInt = (slope * 10).round().clamp(-32768, 32767);
      final command = _encodeSimulationParams(slopeInt);

      debugPrint(
        'Testing Slope Method 1 (Standard FTMS): $slope% -> $slopeInt (0.1% units)',
      );
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 1: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 1: $e');
      return false;
    }
  }

  Future<bool> testSlopeMethod2(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 2: Try as resistance level instead
      double resistanceLevel = (slope.abs() / 2.0).clamp(
        0.0,
        10.0,
      ); // Convert slope to resistance
      int resistanceInt = (resistanceLevel * 10).round();

      final command = Uint8List(3);
      command[0] = 0x04; // Set Target Resistance Level opcode
      command[1] = resistanceInt & 0xFF;
      command[2] = (resistanceInt >> 8) & 0xFF;

      debugPrint(
        'Testing Slope Method 2 (As Resistance): $slope% -> $resistanceLevel resistance -> $resistanceInt',
      );
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 2: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 2: $e');
      return false;
    }
  }

  Future<bool> testSlopeMethod3(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 3: Different scaling (0.1% instead of 0.01%)
      int slopeInt = (slope * 10).round().clamp(-3276, 3276);

      final command = Uint8List(8);
      command[0] = 0x11; // Set Indoor Bike Simulation Parameters opcode
      command[1] = slopeInt & 0xFF;
      command[2] = (slopeInt >> 8) & 0xFF;
      command[3] = 0; // Wind speed
      command[4] = 0;
      command[5] = 0; // Rolling resistance
      command[6] = 0;
      command[7] = 0; // Wind direction

      debugPrint(
        'Testing Slope Method 3 (0.1% scaling): $slope% -> $slopeInt (0.1% units)',
      );
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 3: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 3: $e');
      return false;
    }
  }

  Future<bool> testSlopeMethod4(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 4: Big endian byte order
      int slopeInt = (slope * 10).round().clamp(-32768, 32767);

      final command = Uint8List(8);
      command[0] = 0x11; // Set Indoor Bike Simulation Parameters opcode
      command[1] = (slopeInt >> 8) & 0xFF; // High byte first (big endian)
      command[2] = slopeInt & 0xFF; // Low byte second
      command[3] = 0; // Wind speed
      command[4] = 0;
      command[5] = 0; // Rolling resistance
      command[6] = 0;
      command[7] = 0; // Wind direction

      debugPrint(
        'Testing Slope Method 4 (Big Endian): $slope% -> $slopeInt (big endian)',
      );
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 4: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 4: $e');
      return false;
    }
  }

  Future<bool> testSlopeMethod5(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 5: Different opcode (0x05 for Set Target Power, but with slope data)
      int slopeInt = (slope * 10).round().clamp(-32768, 32767);

      final command = Uint8List(5);
      command[0] = 0x05; // Set Target Power opcode (experimental)
      command[1] = slopeInt & 0xFF;
      command[2] = (slopeInt >> 8) & 0xFF;
      command[3] = 0x00;
      command[4] = 0x00;

      debugPrint('Testing Slope Method 5 (Power opcode): $slope% -> $slopeInt');
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 5: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 5: $e');
      return false;
    }
  }

  Future<bool> testSlopeMethod6(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 6: Single byte slope (0-255 range)
      int slopeByte = ((slope + 25) * 5).round().clamp(
        0,
        255,
      ); // Map -5% to +5% -> 0 to 255

      final command = Uint8List(2);
      command[0] = 0x04; // Resistance opcode
      command[1] = slopeByte;

      debugPrint('Testing Slope Method 6 (Single byte): $slope% -> $slopeByte');
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 6: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 6: $e');
      return false;
    }
  }

  Future<bool> testSlopeMethod7(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 7: Custom opcode with 1% scaling
      int slopeInt = slope.round().clamp(-127, 127);

      final command = Uint8List(3);
      command[0] = 0x12; // Custom opcode (might work for some trainers)
      command[1] = slopeInt & 0xFF;
      command[2] = 0x00;

      debugPrint(
        'Testing Slope Method 7 (Custom opcode 0x12): $slope% -> $slopeInt',
      );
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 7: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 7: $e');
      return false;
    }
  }

  Future<bool> testSlopeMethod8(double slope) async {
    if (_fitnessMachineControlPointCharacteristic == null) {
      debugPrint(
        'ERROR: Control Point characteristic is NULL - trainer may not be properly connected',
      );
      debugPrint(
        'Connection status: isConnected=$_isConnected, status=$_status',
      );
      return false;
    }

    try {
      // Method 8: Try slope in bytes 3-4 instead of 1-2
      int slopeInt = (slope * 10).round().clamp(-32768, 32767);

      final command = Uint8List(8);
      command[0] = 0x11; // Set Indoor Bike Simulation Parameters opcode
      command[1] = slopeInt & 0xFF; // Put slope in correct slope position
      command[2] = (slopeInt >> 8) & 0xFF;
      command[3] = 0; // Wind speed low byte
      command[4] = 0; // Wind speed high byte
      command[5] = 0; // Rolling resistance
      command[6] = 0;
      command[7] = 0; // Wind direction

      debugPrint(
        'Testing Slope Method 8 (Slope in wind position): $slope% -> $slopeInt',
      );
      debugPrint(
        'Command: [${command.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}]',
      );

      await _fitnessMachineControlPointCharacteristic!.write(command);
      debugPrint('Slope Method 8: Command sent successfully');
      return true;
    } catch (e) {
      debugPrint('Error in slope method 8: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _debugTimer?.cancel();
    disconnect();
    super.dispose();
  }
}
