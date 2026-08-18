import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fit_tool/fit_tool.dart';
import '../models/workout_models.dart';

class FitFileService {
  /// Creates a FIT file from workout summary data.
  ///
  /// FIT file timing fields:
  /// - totalElapsedTime: Wall-clock time from start to stop (includes pauses)
  /// - totalTimerTime: Actual workout time (excludes pauses)
  ///
  /// This distinction is important for fitness apps that track both moving time
  /// and total session time.
  Future<String> createWorkoutFitFile(WorkoutSummary workoutSummary) async {
    try {
      // Debug: Print the actual startTime value
      debugPrint('WorkoutSummary startTime: ${workoutSummary.startTime}');
      debugPrint(
        'StartTime millisecondsSinceEpoch: ${workoutSummary.startTime.millisecondsSinceEpoch}',
      );
      debugPrint(
        'StartTime in seconds: ${workoutSummary.startTime.millisecondsSinceEpoch ~/ 1000}',
      );

      // Get (and create if needed) the fit_files subdirectory
      final Directory documentsDir = await getApplicationDocumentsDirectory();
      final Directory fitDir = Directory('${documentsDir.path}/fit_files');
      if (!await fitDir.exists()) await fitDir.create(recursive: true);
      final String fitFileName =
          '${_sanitizeFileName(workoutSummary.workoutName)}_${_formatDateForFilename(workoutSummary.startTime)}.fit';
      final String filePath = '${fitDir.path}/$fitFileName';

      // Create FIT file builder
      final builder = FitFileBuilder(autoDefine: true, minStringSize: 50);

      // All date_time fields in fit_tool expect UNIX MILLISECONDS (ms since Jan 1, 1970).
      // The library applies scale=0.001 + offset=-631065600000 internally to produce the
      // correct FIT uint32 (seconds since Dec 31, 1989) in the binary file.
      final endTime = workoutSummary.startTime.add(
        workoutSummary.totalElapsedTime,
      );
      final startTimestamp = workoutSummary.startTime.millisecondsSinceEpoch;
      final endTimestamp = endTime.millisecondsSinceEpoch;

      // Add file id message
      final fileIdMessage = FileIdMessage()
        ..type = FileType.activity
        ..manufacturer = Manufacturer.development.value
        ..product = 1
        ..timeCreated =
            startTimestamp // Unix ms
        ..serialNumber = 12345;

      builder.add(fileIdMessage);

      // Calculate total distance once for consistency
      final totalDistanceMeters = _calculateTotalDistance(
        workoutSummary.powerData,
      );

      debugPrint('=== WORKOUT TIMING DEBUG ===');
      debugPrint('Start: ${workoutSummary.startTime} ($startTimestamp ms)');
      debugPrint('End:   $endTime ($endTimestamp ms)');
      debugPrint(
        'Elapsed: ${workoutSummary.totalElapsedTime.inSeconds}s  Timer: ${workoutSummary.totalDuration.inSeconds}s',
      );
      debugPrint(
        'Distance: ${totalDistanceMeters.toStringAsFixed(2)} m  Records: ${workoutSummary.powerData.length}',
      );
      debugPrint('=========================');

      // Add start event (timer events are best practice for FIT activity files)
      builder.add(
        EventMessage()
          ..timestamp =
              startTimestamp // Unix ms
          ..event = Event.timer
          ..eventType = EventType.start
          ..eventGroup = 0,
      );

      // Add record messages (must come before lap/session/activity)
      debugPrint(
        'Adding ${workoutSummary.powerData.length} record messages...',
      );
      for (int i = 0; i < workoutSummary.powerData.length; i++) {
        final dataPoint = workoutSummary.powerData[i];
        final speedMs = _convertKmhToMs(dataPoint.speed);

        final recordMessage = RecordMessage()
          ..timestamp = dataPoint
              .timestamp
              .millisecondsSinceEpoch // Unix ms
          ..speed =
              speedMs // m/s (library applies scale=1000)
          ..power = dataPoint.power.toInt();

        // Only set distance if non-zero to avoid writing cumulative=0 for all records
        if (dataPoint.distance > 0) {
          recordMessage.distance = dataPoint
              .distance; // cumulative meters (library applies scale=100)
        }

        if (dataPoint.heartRate > 0) {
          recordMessage.heartRate = dataPoint.heartRate;
        }

        // Debug first and last record
        if (i == 0 || i == workoutSummary.powerData.length - 1) {
          debugPrint(
            'Record ${i == 0 ? "FIRST" : "LAST"}: ts=${dataPoint.timestamp.millisecondsSinceEpoch}ms, speed=${dataPoint.speed} km/h = ${speedMs.toStringAsFixed(2)} m/s, power=${dataPoint.power.toInt()}W, dist=${dataPoint.distance.toStringAsFixed(2)}m',
          );
        }

        builder.add(recordMessage);
      }

      // Add stop event (must come before lap/session/activity per FIT spec)
      builder.add(
        EventMessage()
          ..timestamp =
              endTimestamp // Unix ms
          ..event = Event.timer
          ..eventType = EventType.stopAll
          ..eventGroup = 0,
      );

      // Add lap message
      final lapMessage = LapMessage()
        ..timestamp =
            endTimestamp // Unix ms
        ..startTime =
            startTimestamp // Unix ms
        ..totalElapsedTime = workoutSummary.totalElapsedTime.inSeconds
            .toDouble() // seconds
        ..totalTimerTime = workoutSummary.totalDuration.inSeconds
            .toDouble() // seconds
        ..totalDistance =
            totalDistanceMeters // meters (library applies scale=100)
        ..totalWork = workoutSummary.totalEnergy.toInt()
        ..avgPower = workoutSummary.avgPower.toInt()
        ..maxPower = workoutSummary.maxPower.toInt()
        ..avgSpeed =
            _convertKmhToMs(
              workoutSummary.avgSpeed,
            ) // m/s (library applies scale=1000)
        ..sport = Sport.cycling
        ..subSport = SubSport.indoorCycling
        ..lapTrigger = LapTrigger.sessionEnd
        ..event = Event.lap
        ..eventType = EventType.stop;

      if (workoutSummary.avgHeartRate > 0) {
        lapMessage.avgHeartRate = workoutSummary.avgHeartRate;
      }
      if (workoutSummary.maxHeartRate > 0) {
        lapMessage.maxHeartRate = workoutSummary.maxHeartRate;
      }

      builder.add(lapMessage);

      // Add session message
      final sessionMessage = SessionMessage()
        ..timestamp =
            endTimestamp // Unix ms
        ..startTime =
            startTimestamp // Unix ms
        ..totalElapsedTime = workoutSummary.totalElapsedTime.inSeconds
            .toDouble() // seconds
        ..totalTimerTime = workoutSummary.totalDuration.inSeconds
            .toDouble() // seconds
        ..totalDistance =
            totalDistanceMeters // meters
        ..totalWork = workoutSummary.totalEnergy.toInt()
        ..avgPower = workoutSummary.avgPower.toInt()
        ..maxPower = workoutSummary.maxPower.toInt()
        ..avgSpeed =
            _convertKmhToMs(workoutSummary.avgSpeed) // m/s
        ..sport = Sport.cycling
        ..subSport = SubSport.indoorCycling
        ..firstLapIndex = 0
        ..numLaps = 1
        ..trigger = SessionTrigger.activityEnd
        ..event = Event.session
        ..eventType = EventType.stop;

      if (workoutSummary.avgHeartRate > 0) {
        sessionMessage.avgHeartRate = workoutSummary.avgHeartRate;
      }
      if (workoutSummary.maxHeartRate > 0) {
        sessionMessage.maxHeartRate = workoutSummary.maxHeartRate;
      }

      builder.add(sessionMessage);

      // Add activity message
      builder.add(
        ActivityMessage()
          ..timestamp =
              endTimestamp // Unix ms
          ..localTimestamp =
              endTimestamp // Unix ms (UTC; Garmin infers timezone from device)
          ..totalTimerTime = workoutSummary.totalDuration.inSeconds
              .toDouble() // seconds
          ..numSessions = 1
          ..type = Activity
              .manual // 0 = normal single-sport device-recorded activity
          ..event = Event.activity
          ..eventType = EventType.stop,
      );

      // Build and write the FIT file
      final fitFile = builder.build();
      final file = File(filePath);
      await file.writeAsBytes(fitFile.toBytes());

      debugPrint('FIT file created successfully: $filePath');

      return filePath;
    } catch (e) {
      debugPrint('Error creating FIT file: $e');
      rethrow;
    }
  }

  /// Creates a FIT file and validates it, returning both the file path and validation result
  Future<MapEntry<String, FitValidationResult>> createAndValidateWorkoutFitFile(
    WorkoutSummary workoutSummary,
  ) async {
    final filePath = await createWorkoutFitFile(workoutSummary);
    final validationResult = await validateFitFileWithSummary(
      filePath,
      workoutSummary,
    );
    return MapEntry(filePath, validationResult);
  }

  // Helper method to get total distance from FTMS data (last data point has cumulative distance)
  double _calculateTotalDistance(List<WorkoutDataPoint> dataPoints) {
    if (dataPoints.isEmpty) return 0.0;
    return dataPoints.last.distance;
  }

  // Convert km/h to m/s
  double _convertKmhToMs(double kmh) {
    return kmh / 3.6;
  }

  // Sanitize filename by removing invalid characters
  String _sanitizeFileName(String fileName) {
    // Remove or replace invalid characters for file names
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(' ', '_')
        .trim();
  }

  // Format date for filename (YYYYMMDD_HHMMSS)
  String _formatDateForFilename(DateTime dateTime) {
    return '${dateTime.year.toString().padLeft(4, '0')}'
        '${dateTime.month.toString().padLeft(2, '0')}'
        '${dateTime.day.toString().padLeft(2, '0')}_'
        '${dateTime.hour.toString().padLeft(2, '0')}'
        '${dateTime.minute.toString().padLeft(2, '0')}'
        '${dateTime.second.toString().padLeft(2, '0')}';
  }

  // Get list of saved FIT files
  Future<List<FileSystemEntity>> getSavedFitFiles() async {
    try {
      final Directory documentsDir = await getApplicationDocumentsDirectory();
      final Directory fitDir = Directory('${documentsDir.path}/fit_files');
      if (!await fitDir.exists()) return [];

      final List<FileSystemEntity> files = fitDir
          .listSync()
          .where((file) => file.path.endsWith('.fit'))
          .toList();

      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      return files;
    } catch (e) {
      debugPrint('Error getting saved FIT files: $e');
      return [];
    }
  }

  /// Validates a FIT file with original WorkoutSummary data for comparison
  Future<FitValidationResult> validateFitFileWithSummary(
    String filePath,
    WorkoutSummary workoutSummary,
  ) async {
    try {
      debugPrint('=== FIT FILE VALIDATION WITH SUMMARY START ===');
      debugPrint('Validating FIT file: $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('ERROR: FIT file does not exist at path: $filePath');
        return FitValidationResult(
          filePath: filePath,
          fileSize: 0,
          messageCount: 0,
          isValid: false,
          error: 'File does not exist',
          recordCount: 0,
        );
      }

      final fileBytes = await file.readAsBytes();
      debugPrint('FIT file size: ${fileBytes.length} bytes');

      try {
        // Try to parse the FIT file to verify it's valid
        final fitFile = FitFile.fromBytes(fileBytes);
        debugPrint('FIT file parsed successfully');

        // Create validation result using the original WorkoutSummary data
        final result = FitValidationResult(
          filePath: filePath,
          fileSize: fileBytes.length,
          messageCount:
              6 +
              workoutSummary
                  .powerData
                  .length, // FileId + StartEvent + StopEvent + Activity + Session + Lap + Records
          isValid: true,
          fileType: 'Activity',
          manufacturer: 255, // Development (as set in createWorkoutFitFile)
          product: 1,
          timeCreated: DateTime.now(), // Current time when FIT file was created
          workoutStartTime:
              workoutSummary.startTime, // Original workout start time
          // Use original WorkoutSummary data to show what should be in the FIT file
          sessionTotalElapsedTime:
              workoutSummary.totalElapsedTime.inMilliseconds,
          sessionTotalTimerTime: workoutSummary.totalDuration.inMilliseconds,
          sessionTotalDistance: _calculateTotalDistance(
            workoutSummary.powerData,
          ),
          sessionAvgPower: workoutSummary.avgPower.toInt(),
          sessionMaxPower: workoutSummary.maxPower.toInt(),
          sessionAvgSpeed: _convertKmhToMs(workoutSummary.avgSpeed),
          activityTotalTimerTime: workoutSummary.totalDuration.inMilliseconds,
          recordCount: workoutSummary.powerData.length,
          firstRecordInfo: workoutSummary.powerData.isNotEmpty
              ? 'Power: ${workoutSummary.powerData.first.power.toInt()}W, Speed: ${workoutSummary.powerData.first.speed.toStringAsFixed(1)} km/h'
              : null,
          lastRecordInfo: workoutSummary.powerData.isNotEmpty
              ? 'Power: ${workoutSummary.powerData.last.power.toInt()}W, Speed: ${workoutSummary.powerData.last.speed.toStringAsFixed(1)} km/h'
              : null,
        );

        // Log validation results for console debugging
        _logValidationResults(result);

        debugPrint('=== FIT FILE VALIDATION WITH SUMMARY END ===');
        return result;
      } catch (parseError) {
        debugPrint('ERROR parsing FIT file: $parseError');
        return FitValidationResult(
          filePath: filePath,
          fileSize: fileBytes.length,
          messageCount: 0,
          isValid: false,
          error: 'FIT file parsing failed: $parseError',
          recordCount: 0,
        );
      }
    } catch (e) {
      debugPrint('ERROR validating FIT file: $e');
      debugPrint('=== FIT FILE VALIDATION FAILED ===');
      return FitValidationResult(
        filePath: filePath,
        fileSize: 0,
        messageCount: 0,
        isValid: false,
        error: e.toString(),
        recordCount: 0,
      );
    }
  }

  /// Log validation results summary
  void _logValidationResults(FitValidationResult result) {
    debugPrint('--- Validation Summary ---');
    debugPrint('File Size: ${result.fileSize} bytes');
    debugPrint('Messages: ${result.messageCount}');
    debugPrint('Records: ${result.recordCount}');
    if (result.workoutStartTime != null) {
      debugPrint('Workout Start Time: ${result.workoutStartTime}');
    }
    if (result.timeCreated != null) {
      debugPrint('FIT File Created: ${result.timeCreated}');
    }
    if (result.sessionTotalElapsedTime != null &&
        result.sessionTotalTimerTime != null) {
      debugPrint(
        'Total Elapsed Time: ${result.formatDuration(result.sessionElapsedDuration)}',
      );
      debugPrint(
        'Total Timer Time: ${result.formatDuration(result.sessionTimerDuration)}',
      );
      debugPrint('Pause Time: ${result.formatDuration(result.pauseTime)}');
    }
    if (result.sessionAvgPower != null) {
      debugPrint('Avg Power: ${result.sessionAvgPower}W');
    }
    if (result.sessionMaxPower != null) {
      debugPrint('Max Power: ${result.sessionMaxPower}W');
    }
  }
}
