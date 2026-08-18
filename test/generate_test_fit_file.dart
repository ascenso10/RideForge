// ignore_for_file: avoid_print
/// Standalone script to generate a test FIT file
/// Run with: dart run test/generate_test_fit_file.dart
///
/// This script creates a FIT file with dummy workout data
/// to verify the FIT file generation is working correctly.
library;

import 'dart:io';
import 'package:fit_tool/fit_tool.dart';

void main() async {
  print('=== FIT File Generation Test ===\n');

  // Create output directory
  final outputDir = Directory('test_output');
  if (!await outputDir.exists()) {
    await outputDir.create();
  }

  // Test 1: Basic workout
  print('Test 1: Basic 10-minute workout');
  await generateTestFitFile(
    outputPath: '${outputDir.path}/test_basic_workout.fit',
    durationMinutes: 10,
    avgPower: 180,
    avgSpeedKmh: 28,
  );

  // Test 2: Short workout
  print('\nTest 2: Short 2-minute workout');
  await generateTestFitFile(
    outputPath: '${outputDir.path}/test_short_workout.fit',
    durationMinutes: 2,
    avgPower: 150,
    avgSpeedKmh: 25,
  );

  // Test 3: Interval workout
  print('\nTest 3: Interval workout');
  await generateIntervalTestFitFile(
    outputPath: '${outputDir.path}/test_interval_workout.fit',
  );

  print('\n=== All tests completed ===');
  print('Output files are in: ${outputDir.absolute.path}');
  print(
    '\nYou can upload these files to Garmin Connect to verify they are valid.',
  );
}

/// Generate a basic test FIT file
Future<void> generateTestFitFile({
  required String outputPath,
  required int durationMinutes,
  required double avgPower,
  required double avgSpeedKmh,
}) async {
  try {
    final builder = FitFileBuilder(autoDefine: true, minStringSize: 50);

    final startTime = DateTime.now().subtract(
      Duration(minutes: durationMinutes),
    );
    final endTime = DateTime.now();

    final startTimestamp = toSecondsSince1989Epoch(
      startTime.millisecondsSinceEpoch,
    );
    final endTimestamp = toSecondsSince1989Epoch(
      endTime.millisecondsSinceEpoch,
    );

    // 1. File ID message
    final fileIdMessage = FileIdMessage()
      ..type = FileType.activity
      ..manufacturer = Manufacturer.development.value
      ..product = 1
      ..timeCreated = startTimestamp
      ..serialNumber = 12345;
    builder.add(fileIdMessage);

    // 2. Start event
    final startEvent = EventMessage()
      ..timestamp = startTimestamp
      ..event = Event.timer
      ..eventType = EventType.start
      ..eventGroup = 0;
    builder.add(startEvent);

    // 3. Record messages (one per second)
    print('  Adding ${durationMinutes * 60} record messages...');
    double cumulativeDistance = 0.0;
    final avgSpeedMs = avgSpeedKmh / 3.6;

    for (int i = 0; i < durationMinutes * 60; i++) {
      final recordTimestamp = toSecondsSince1989Epoch(
        startTime.add(Duration(seconds: i)).millisecondsSinceEpoch,
      );

      // Add variation
      final powerVariation = (i % 10 - 5) * 2;
      final speedVariation = (i % 10 - 5) * 0.1;
      final currentPower = avgPower + powerVariation;
      final currentSpeedMs = avgSpeedMs + speedVariation;

      // Update cumulative distance
      if (i > 0) {
        cumulativeDistance += currentSpeedMs; // 1 second interval
      }

      final recordMessage = RecordMessage()
        ..timestamp = recordTimestamp
        ..power = currentPower.toInt()
        ..speed = currentSpeedMs
        ..distance = cumulativeDistance;

      builder.add(recordMessage);
    }

    // 4. Lap message
    final lapMessage = LapMessage()
      ..timestamp = endTimestamp
      ..startTime = startTimestamp
      ..totalElapsedTime = (durationMinutes * 60).toDouble()
      ..totalTimerTime = (durationMinutes * 60).toDouble()
      ..totalDistance = cumulativeDistance
      ..avgPower = avgPower.toInt()
      ..maxPower = (avgPower + 10).toInt()
      ..avgSpeed = avgSpeedMs
      ..sport = Sport.cycling
      ..subSport = SubSport.generic
      ..lapTrigger = LapTrigger.sessionEnd
      ..event = Event.lap
      ..eventType = EventType.stop;
    builder.add(lapMessage);

    // 5. Session message
    final sessionMessage = SessionMessage()
      ..timestamp = endTimestamp
      ..startTime = startTimestamp
      ..totalElapsedTime = (durationMinutes * 60).toDouble()
      ..totalTimerTime = (durationMinutes * 60).toDouble()
      ..totalDistance = cumulativeDistance
      ..avgPower = avgPower.toInt()
      ..maxPower = (avgPower + 10).toInt()
      ..avgSpeed = avgSpeedMs
      ..sport = Sport.cycling
      ..subSport = SubSport.generic
      ..firstLapIndex = 0
      ..numLaps = 1
      ..trigger = SessionTrigger.activityEnd
      ..event = Event.session
      ..eventType = EventType.stop;
    builder.add(sessionMessage);

    // 6. Activity message
    final activityMessage = ActivityMessage()
      ..timestamp = endTimestamp
      ..localTimestamp = endTimestamp
      ..totalTimerTime = (durationMinutes * 60).toDouble()
      ..numSessions = 1
      ..type = Activity.manual
      ..event = Event.activity
      ..eventType = EventType.stop;
    builder.add(activityMessage);

    // 7. Stop event
    final stopEvent = EventMessage()
      ..timestamp = endTimestamp
      ..event = Event.timer
      ..eventType = EventType.stopAll
      ..eventGroup = 0;
    builder.add(stopEvent);

    // Build and write file
    final fitFile = builder.build();
    final file = File(outputPath);
    await file.writeAsBytes(fitFile.toBytes());

    final fileSize = await file.length();
    print('  Created: $outputPath ($fileSize bytes)');
    print('  Duration: $durationMinutes minutes');
    print('  Avg Power: ${avgPower.toInt()}W');
    print('  Avg Speed: ${avgSpeedKmh.toStringAsFixed(1)} km/h');
    print('  Distance: ${(cumulativeDistance / 1000).toStringAsFixed(2)} km');

    // Validate the file
    await validateFitFile(outputPath);
  } catch (e, stackTrace) {
    print('  ERROR: $e');
    print('  Stack trace: $stackTrace');
  }
}

/// Generate an interval workout FIT file
Future<void> generateIntervalTestFitFile({required String outputPath}) async {
  try {
    final builder = FitFileBuilder(autoDefine: true, minStringSize: 50);

    // 20-minute interval workout
    final totalDurationSeconds = 20 * 60;
    final startTime = DateTime.now().subtract(const Duration(minutes: 20));
    final endTime = DateTime.now();

    final startTimestamp = toSecondsSince1989Epoch(
      startTime.millisecondsSinceEpoch,
    );
    final endTimestamp = toSecondsSince1989Epoch(
      endTime.millisecondsSinceEpoch,
    );

    // Define intervals: [startSec, endSec, power, speedKmh]
    final intervals = [
      [0, 300, 120.0, 22.0], // Warmup: 5 min at 120W
      [300, 480, 250.0, 32.0], // Work 1: 3 min at 250W
      [480, 600, 100.0, 20.0], // Recovery: 2 min at 100W
      [600, 780, 260.0, 33.0], // Work 2: 3 min at 260W
      [780, 900, 100.0, 20.0], // Recovery: 2 min at 100W
      [900, 1200, 100.0, 22.0], // Cooldown: 5 min at 100W
    ];

    // 1. File ID
    final fileIdMessage = FileIdMessage()
      ..type = FileType.activity
      ..manufacturer = Manufacturer.development.value
      ..product = 1
      ..timeCreated = startTimestamp
      ..serialNumber = 12345;
    builder.add(fileIdMessage);

    // 2. Start event
    final startEvent = EventMessage()
      ..timestamp = startTimestamp
      ..event = Event.timer
      ..eventType = EventType.start
      ..eventGroup = 0;
    builder.add(startEvent);

    // 3. Record messages
    print('  Adding $totalDurationSeconds record messages...');
    double cumulativeDistance = 0.0;
    double totalPower = 0.0;
    double maxPower = 0.0;

    for (int sec = 0; sec < totalDurationSeconds; sec++) {
      // Find current interval
      double basePower = 100;
      double baseSpeedKmh = 20;

      for (final interval in intervals) {
        if (sec >= interval[0] && sec < interval[1]) {
          basePower = interval[2] as double;
          baseSpeedKmh = interval[3] as double;
          break;
        }
      }

      // Add variation
      final variation = (sec % 10 - 5);
      final currentPower = basePower + variation * 2;
      final currentSpeedMs = (baseSpeedKmh + variation * 0.1) / 3.6;

      totalPower += currentPower;
      if (currentPower > maxPower) maxPower = currentPower;

      if (sec > 0) {
        cumulativeDistance += currentSpeedMs;
      }

      final recordTimestamp = toSecondsSince1989Epoch(
        startTime.add(Duration(seconds: sec)).millisecondsSinceEpoch,
      );

      final recordMessage = RecordMessage()
        ..timestamp = recordTimestamp
        ..power = currentPower.toInt()
        ..speed = currentSpeedMs
        ..distance = cumulativeDistance;

      builder.add(recordMessage);
    }

    final avgPower = totalPower / totalDurationSeconds;
    final avgSpeedMs = cumulativeDistance / totalDurationSeconds;

    // 4. Lap message
    final lapMessage = LapMessage()
      ..timestamp = endTimestamp
      ..startTime = startTimestamp
      ..totalElapsedTime = totalDurationSeconds.toDouble()
      ..totalTimerTime = totalDurationSeconds.toDouble()
      ..totalDistance = cumulativeDistance
      ..avgPower = avgPower.toInt()
      ..maxPower = maxPower.toInt()
      ..avgSpeed = avgSpeedMs
      ..sport = Sport.cycling
      ..subSport = SubSport.generic
      ..lapTrigger = LapTrigger.sessionEnd
      ..event = Event.lap
      ..eventType = EventType.stop;
    builder.add(lapMessage);

    // 5. Session message
    final sessionMessage = SessionMessage()
      ..timestamp = endTimestamp
      ..startTime = startTimestamp
      ..totalElapsedTime = totalDurationSeconds.toDouble()
      ..totalTimerTime = totalDurationSeconds.toDouble()
      ..totalDistance = cumulativeDistance
      ..avgPower = avgPower.toInt()
      ..maxPower = maxPower.toInt()
      ..avgSpeed = avgSpeedMs
      ..sport = Sport.cycling
      ..subSport = SubSport.generic
      ..firstLapIndex = 0
      ..numLaps = 1
      ..trigger = SessionTrigger.activityEnd
      ..event = Event.session
      ..eventType = EventType.stop;
    builder.add(sessionMessage);

    // 6. Activity message
    final activityMessage = ActivityMessage()
      ..timestamp = endTimestamp
      ..localTimestamp = endTimestamp
      ..totalTimerTime = totalDurationSeconds.toDouble()
      ..numSessions = 1
      ..type = Activity.manual
      ..event = Event.activity
      ..eventType = EventType.stop;
    builder.add(activityMessage);

    // 7. Stop event
    final stopEvent = EventMessage()
      ..timestamp = endTimestamp
      ..event = Event.timer
      ..eventType = EventType.stopAll
      ..eventGroup = 0;
    builder.add(stopEvent);

    // Build and write file
    final fitFile = builder.build();
    final file = File(outputPath);
    await file.writeAsBytes(fitFile.toBytes());

    final fileSize = await file.length();
    print('  Created: $outputPath ($fileSize bytes)');
    print('  Duration: 20 minutes (interval workout)');
    print('  Avg Power: ${avgPower.toInt()}W');
    print('  Max Power: ${maxPower.toInt()}W');
    print('  Distance: ${(cumulativeDistance / 1000).toStringAsFixed(2)} km');

    // Validate the file
    await validateFitFile(outputPath);
  } catch (e, stackTrace) {
    print('  ERROR: $e');
    print('  Stack trace: $stackTrace');
  }
}

/// Validate a FIT file by reading it back
Future<void> validateFitFile(String filePath) async {
  try {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    // Try to parse the FIT file
    final fitFile = FitFile.fromBytes(bytes);
    print('  Validation: PASSED (file parsed successfully)');
  } catch (e) {
    print('  Validation: FAILED - $e');
  }
}
