import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/workout_models.dart';
import '../models/trainer_capabilities.dart';
import 'trainer_service.dart';
import 'heart_rate_service.dart';
import 'gpx_service.dart';
import 'fit_file_service.dart';
import 'foreground_task_service.dart';
import 'notification_service.dart';

enum WorkoutStatus { stopped, running, paused, completed }

class WorkoutService extends ChangeNotifier {
  final TrainerService _trainerService;
  HeartRateService? _heartRateService;
  final FitFileService _fitFileService = FitFileService();
  final ForegroundTaskService _foregroundTaskService = ForegroundTaskService();

  List<Workout> _availableWorkouts = [];
  final List<GpxWorkout> _availableGpxWorkouts = [];
  Workout? _currentWorkout;
  GpxWorkout? _currentGpxWorkout;
  WorkoutInterval? _currentInterval;
  int _currentIntervalIndex = 0;
  int _currentGpxSegmentIndex = 0;
  WorkoutStatus _status = WorkoutStatus.stopped;

  Duration _elapsedTime = Duration.zero;
  Duration _totalElapsedTime =
      Duration.zero; // Total elapsed time including pauses
  double _totalGpxDistance = 0.0; // Total distance covered in meters
  Duration _intervalElapsedTime = Duration.zero;
  Timer? _workoutTimer;
  TrainerCapabilities _trainerCapabilities = TrainerCapabilities.generic;
  // Identity of the last detection we adopted, so the trainer listener only
  // reacts to a genuinely new detection rather than to every data packet.
  TrainerCapabilities? _lastAppliedDetectedCapabilities;

  // Transition ramping for smooth interval changes
  int? _previousIntervalPower;
  static const Duration _transitionDuration = Duration(seconds: 10);

  // Countdown notification for upcoming interval changes
  int? _countdownSeconds;
  WorkoutInterval? _nextInterval;
  static const Duration _countdownWarningTime = Duration(seconds: 10);

  // Workout data collection
  DateTime? _workoutStartTime;
  DateTime? _workoutStopTime;
  DateTime? _lastPauseTime;
  Duration _totalPauseTime = Duration.zero;
  final List<WorkoutDataPoint> _workoutData = [];
  final List<IntervalSummary> _completedIntervals = [];
  double _cumulativeCalculatedDistance =
      0.0; // Speed-based fallback when FTMS doesn't report distance

  WorkoutService(this._trainerService, {HeartRateService? heartRateService})
    : _heartRateService = heartRateService {
    _loadWorkouts();
    _loadTrainerCapabilities();
    _trainerService.addListener(_onTrainerServiceChanged);
  }

  void updateHeartRateService(HeartRateService? heartRateService) {
    _heartRateService = heartRateService;
  }

  // Getters
  List<Workout> get availableWorkouts => _availableWorkouts;
  List<GpxWorkout> get availableGpxWorkouts => _availableGpxWorkouts;
  Workout? get currentWorkout => _currentWorkout;
  GpxWorkout? get currentGpxWorkout => _currentGpxWorkout;
  WorkoutInterval? get currentInterval => _currentInterval;
  int get currentIntervalIndex => _currentIntervalIndex;
  int get currentGpxSegmentIndex => _currentGpxSegmentIndex;
  WorkoutStatus get status => _status;
  Duration get elapsedTime => _elapsedTime;
  Duration get totalElapsedTime => _totalElapsedTime;
  Duration get intervalElapsedTime => _intervalElapsedTime;
  Duration get remainingTime => _currentInterval != null
      ? _currentInterval!.duration - _intervalElapsedTime
      : Duration.zero;

  // Countdown getters
  int? get countdownSeconds => _countdownSeconds;
  WorkoutInterval? get nextInterval => _nextInterval;

  /// Get workout duration (excludes pauses) - same as elapsedTime
  Duration get workoutDuration => _elapsedTime;

  /// Get total pause time during the workout
  Duration get totalPauseTime => _totalPauseTime;

  bool get isGpxWorkout => _currentGpxWorkout != null;
  TrainerCapabilities get trainerCapabilities => _trainerCapabilities;

  double get workoutProgress =>
      _currentWorkout != null && _currentWorkout!.totalDuration.inSeconds > 0
      ? _elapsedTime.inSeconds / _currentWorkout!.totalDuration.inSeconds
      : 0.0;

  double get intervalProgress =>
      _currentInterval != null && _currentInterval!.duration.inSeconds > 0
      ? _intervalElapsedTime.inSeconds / _currentInterval!.duration.inSeconds
      : 0.0;

  Future<void> _loadWorkouts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workoutStrings = prefs.getStringList('custom_workouts') ?? [];
      final gpxWorkoutStrings = prefs.getStringList('gpx_workouts') ?? [];

      final currentFtp = prefs.getInt('current_ftp');
      _availableWorkouts = Workout.getDefaultWorkouts(ftp: currentFtp);
      _availableGpxWorkouts.clear();

      for (final workoutString in workoutStrings) {
        try {
          final workoutJson = jsonDecode(workoutString);
          final custom = Workout.fromJson(workoutJson);
          // Replace default with custom override if IDs match, otherwise append
          final existingIndex = _availableWorkouts.indexWhere(
            (w) => w.id == custom.id,
          );
          if (existingIndex >= 0) {
            _availableWorkouts[existingIndex] = custom;
          } else {
            _availableWorkouts.add(custom);
          }
        } catch (e) {
          debugPrint('Error loading custom workout: $e');
        }
      }

      for (final gpxWorkoutString in gpxWorkoutStrings) {
        try {
          final gpxWorkoutJson = jsonDecode(gpxWorkoutString);
          _availableGpxWorkouts.add(GpxWorkout.fromJson(gpxWorkoutJson));
        } catch (e) {
          debugPrint('Error loading GPX workout: $e');
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading workouts: $e');
      _availableWorkouts = Workout.getDefaultWorkouts();
      _availableGpxWorkouts.clear();
      notifyListeners();
    }
  }

  /// Persists [ftp] as the active FTP and reloads all default workouts so
  /// their power targets reflect the new value.
  Future<void> applyFtpToWorkouts(int ftp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('current_ftp', ftp);
    } catch (e) {
      debugPrint('Error saving current FTP: $e');
    }
    await _loadWorkouts();
  }

  Future<void> saveCustomWorkout(Workout workout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingWorkouts = prefs.getStringList('custom_workouts') ?? [];

      // Remove existing workout with same ID if it exists
      existingWorkouts.removeWhere((workoutString) {
        try {
          final workoutJson = jsonDecode(workoutString);
          return workoutJson['id'] == workout.id;
        } catch (e) {
          return false;
        }
      });

      // Add the new/updated workout
      existingWorkouts.add(jsonEncode(workout.toJson()));
      await prefs.setStringList('custom_workouts', existingWorkouts);

      // Reload workouts
      await _loadWorkouts();
    } catch (e) {
      debugPrint('Error saving custom workout: $e');
    }
  }

  Future<void> deleteCustomWorkout(String workoutId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingWorkouts = prefs.getStringList('custom_workouts') ?? [];

      // Remove workout with the specified ID
      existingWorkouts.removeWhere((workoutString) {
        try {
          final workoutJson = jsonDecode(workoutString);
          return workoutJson['id'] == workoutId;
        } catch (e) {
          return false;
        }
      });

      await prefs.setStringList('custom_workouts', existingWorkouts);

      // Reload workouts
      await _loadWorkouts();
    } catch (e) {
      debugPrint('Error deleting custom workout: $e');
    }
  }

  Future<void> saveGpxWorkout(GpxWorkout gpxWorkout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingGpxWorkouts = prefs.getStringList('gpx_workouts') ?? [];

      // Remove existing GPX workout with same ID if it exists
      existingGpxWorkouts.removeWhere((gpxWorkoutString) {
        try {
          final gpxWorkoutJson = jsonDecode(gpxWorkoutString);
          return gpxWorkoutJson['id'] == gpxWorkout.id;
        } catch (e) {
          return false;
        }
      });

      // Add the new/updated GPX workout
      existingGpxWorkouts.add(jsonEncode(gpxWorkout.toJson()));
      await prefs.setStringList('gpx_workouts', existingGpxWorkouts);

      // Reload workouts
      await _loadWorkouts();
    } catch (e) {
      debugPrint('Error saving GPX workout: $e');
    }
  }

  void startWorkout(Workout workout) {
    if (_status == WorkoutStatus.running) {
      stopWorkout();
    }

    _currentWorkout = workout;
    _currentIntervalIndex = 0;
    _currentInterval = workout.intervals.first;
    _elapsedTime = Duration.zero;
    _totalElapsedTime = Duration.zero;
    _intervalElapsedTime = Duration.zero;
    _status = WorkoutStatus.running;

    // Initialize workout data collection
    _workoutStartTime = DateTime.now();
    _workoutStopTime = null;
    _lastPauseTime = null;
    _totalPauseTime = Duration.zero;
    _workoutData.clear();
    _completedIntervals.clear();
    _cumulativeCalculatedDistance = 0.0;

    // Reset transition tracking
    _previousIntervalPower = null;
    _countdownSeconds = null;
    _nextInterval = null;

    _applyIntervalSettings();
    _startTimer();

    // Start foreground task for background execution
    _foregroundTaskService.startWorkoutTask(workoutName: workout.name);

    notifyListeners();
  }

  void pauseWorkout() {
    if (_status != WorkoutStatus.running) return;

    _workoutTimer?.cancel();
    _lastPauseTime = DateTime.now();
    _status = WorkoutStatus.paused;

    // Update foreground notification
    _foregroundTaskService.updateNotification(
      title: 'Workout Paused',
      text:
          '${_currentWorkout?.name ?? _currentGpxWorkout?.name ?? "Workout"} - ${formatDuration(_elapsedTime)}',
    );

    notifyListeners();
  }

  void resumeWorkout() {
    if (_status != WorkoutStatus.paused) return;

    // Accumulate pause time
    if (_lastPauseTime != null) {
      _totalPauseTime += DateTime.now().difference(_lastPauseTime!);
      _lastPauseTime = null;
    }

    _status = WorkoutStatus.running;
    if (_currentGpxWorkout != null) {
      _startGpxTimer();
    } else {
      _startTimer();
    }

    // Update foreground notification
    _foregroundTaskService.updateNotification(
      title: 'Workout Active',
      text: _currentWorkout?.name ?? _currentGpxWorkout?.name ?? "Workout",
    );

    notifyListeners();
  }

  void stopWorkout() {
    _workoutTimer?.cancel();

    // Stop foreground task
    _foregroundTaskService.stopWorkoutTask();

    // Set stop time and calculate total elapsed time if workout was running
    if (_status == WorkoutStatus.running || _status == WorkoutStatus.paused) {
      _workoutStopTime = DateTime.now();

      // If we were paused, add the current pause time to total pause time
      if (_status == WorkoutStatus.paused && _lastPauseTime != null) {
        _totalPauseTime += _workoutStopTime!.difference(_lastPauseTime!);
      }

      // Calculate total elapsed time (wall clock time)
      if (_workoutStartTime != null) {
        _totalElapsedTime = _workoutStopTime!.difference(_workoutStartTime!);
      }

      if (_currentGpxWorkout != null && _workoutData.isNotEmpty) {
        _showGpxWorkoutCompletion(immediate: true);
      } else if (_currentWorkout != null && _workoutStartTime != null) {
        // Show completion screen for regular workouts too (even if minimal data)
        _showWorkoutCompletionOnStop();
      }
    }

    // Clear workout state after showing completion
    Timer(const Duration(milliseconds: 200), () {
      _currentWorkout = null;
      _currentGpxWorkout = null;
      _currentInterval = null;
      _currentIntervalIndex = 0;
      _currentGpxSegmentIndex = 0;
      _elapsedTime = Duration.zero;
      _totalElapsedTime = Duration.zero;
      _intervalElapsedTime = Duration.zero;
      _totalGpxDistance = 0.0;
      _status = WorkoutStatus.stopped;

      // Clear workout data and timing
      _workoutStartTime = null;
      _workoutStopTime = null;
      _lastPauseTime = null;
      _totalPauseTime = Duration.zero;
      _workoutData.clear();
      _completedIntervals.clear();
      _cumulativeCalculatedDistance = 0.0;

      notifyListeners();
    });
  }

  Future<void> loadGpxWorkoutFromBytes(
    List<int> bytes,
    String fileName,
    String name,
    String description, {
    bool disableProcessing = false,
  }) async {
    try {
      final gpxService = GpxService();
      final trackPoints = await gpxService.loadGpxFromBytes(bytes);
      final segments = gpxService.computeSlopes(
        trackPoints,
        disableProcessing: disableProcessing,
      );

      final gpxWorkout = GpxWorkout(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        description: description,
        filePath: fileName, // Store filename instead of path for display
        trackPoints: trackPoints,
        segments: segments,
      );

      _availableGpxWorkouts.add(gpxWorkout);
      await saveGpxWorkout(gpxWorkout);
    } catch (e) {
      debugPrint('Error loading GPX workout from bytes: $e');
      rethrow;
    }
  }

  void startGpxWorkout(GpxWorkout gpxWorkout) {
    if (_status == WorkoutStatus.running) {
      stopWorkout();
    }

    _currentGpxWorkout = gpxWorkout;
    _currentWorkout = null;
    _currentInterval = null;
    _currentIntervalIndex = 0;
    _currentGpxSegmentIndex = 0;
    _elapsedTime = Duration.zero;
    _totalElapsedTime = Duration.zero;
    _intervalElapsedTime = Duration.zero;
    _totalGpxDistance = 0.0;
    _status = WorkoutStatus.running;

    // Set workout start time and clear data collections
    _workoutStartTime = DateTime.now();
    _workoutStopTime = null;
    _lastPauseTime = null;
    _totalPauseTime = Duration.zero;
    _workoutData.clear();
    _completedIntervals.clear();
    _cumulativeCalculatedDistance = 0.0;

    // GPX playback will use trainer service methods directly

    _startGpxTimer();

    // Start foreground task for background execution
    _foregroundTaskService.startWorkoutTask(workoutName: gpxWorkout.name);

    notifyListeners();
  }

  void _startGpxTimer() {
    _workoutTimer?.cancel();
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), _onGpxTimerTick);
  }

  void _onGpxTimerTick(Timer timer) {
    if (_currentGpxWorkout == null) return;

    _elapsedTime += const Duration(seconds: 1);

    // Collect workout data for completion screen
    _collectWorkoutData();

    // Get current speed from trainer (km/h)
    final currentSpeed = _trainerService.currentData?.speed ?? 0.0;

    // Convert speed to meters per second and calculate distance covered in this second
    final speedMs = currentSpeed / 3.6; // km/h to m/s
    final distanceCoveredThisSecond = speedMs; // meters in 1 second

    // Only advance if bike is moving (speed > 0.1 km/h to account for sensor noise)
    if (currentSpeed > 0.1) {
      _totalGpxDistance += distanceCoveredThisSecond;
    }

    // Apply current segment slope to trainer (with capability constraints)
    if (_currentGpxSegmentIndex < _currentGpxWorkout!.segments.length) {
      final currentSegment =
          _currentGpxWorkout!.segments[_currentGpxSegmentIndex];
      final constrainedSlope = _trainerCapabilities.constrainGradient(
        currentSegment.slope,
      );

      if (_trainerService.isConnected) {
        _trainerService.setSlopeTarget(constrainedSlope);
      }

      // Calculate segment distance and check if we should move to next segment
      final segmentDistance = GpxService().haversine(
        currentSegment.start.lat,
        currentSegment.start.lon,
        currentSegment.end.lat,
        currentSegment.end.lon,
      );

      // Calculate distance from start of route to end of current segment
      double distanceToEndOfCurrentSegment = 0.0;
      for (int i = 0; i <= _currentGpxSegmentIndex; i++) {
        final segment = _currentGpxWorkout!.segments[i];
        distanceToEndOfCurrentSegment += GpxService().haversine(
          segment.start.lat,
          segment.start.lon,
          segment.end.lat,
          segment.end.lon,
        );
      }

      // Move to next segment if we've covered enough distance
      if (_totalGpxDistance >= distanceToEndOfCurrentSegment &&
          _currentGpxSegmentIndex < _currentGpxWorkout!.segments.length - 1) {
        _currentGpxSegmentIndex++;
      }
    }

    // Check if workout is complete (reached the end of the route)
    if (_currentGpxSegmentIndex >= _currentGpxWorkout!.segments.length - 1) {
      final totalRouteDistance = _currentGpxWorkout!.totalDistance;
      if (_totalGpxDistance >= totalRouteDistance * 0.95) {
        // 95% completion threshold
        _workoutTimer?.cancel();
        _status = WorkoutStatus.completed;

        // Generate and show completion screen
        _showGpxWorkoutCompletion();

        // Auto-stop after showing completion for 3 seconds
        Timer(const Duration(seconds: 3), () {
          if (_status == WorkoutStatus.completed) {
            stopWorkout();
          }
        });
      }
    }

    notifyListeners();
  }

  double get gpxProgress {
    if (_currentGpxWorkout == null || _currentGpxWorkout!.totalDistance <= 0) {
      return 0.0;
    }
    return (_totalGpxDistance / _currentGpxWorkout!.totalDistance).clamp(
      0.0,
      1.0,
    );
  }

  double get currentGpxDistance {
    if (_currentGpxWorkout == null) {
      return 0.0;
    }
    return _totalGpxDistance;
  }

  double get currentSpeed {
    return _trainerService.currentData?.speed ?? 0.0;
  }

  // Trainer capabilities management

  /// Adopts capabilities the moment [TrainerService] detects them.
  ///
  /// Without this, capabilities were only read from preferences in the
  /// constructor, so a trainer connected during the session had its real
  /// gradient/power limits ignored until the next app launch.
  void _onTrainerServiceChanged() {
    final detected = _trainerService.detectedCapabilities;

    // TrainerService notifies on every data packet; only react to a new
    // detection. Identity is the right test because _detectedCapabilities is
    // only reassigned when capabilities are actually re-read from the trainer.
    if (detected == null ||
        identical(detected, _lastAppliedDetectedCapabilities)) {
      return;
    }

    _lastAppliedDetectedCapabilities = detected;
    setTrainerCapabilities(detected);
  }

  Future<void> setTrainerCapabilities(TrainerCapabilities capabilities) async {
    _trainerCapabilities = capabilities;

    // Notify before persisting so gradient handling and the settings screen
    // pick up the new limits without waiting on disk I/O.
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'trainer_capabilities',
        jsonEncode(capabilities.toJson()),
      );
    } catch (e) {
      debugPrint('Error saving trainer capabilities: $e');
    }
  }

  Future<void> _loadTrainerCapabilities() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final capabilitiesString = prefs.getString('trainer_capabilities');

      if (capabilitiesString != null) {
        final capabilitiesJson = jsonDecode(capabilitiesString);
        _trainerCapabilities = TrainerCapabilities.fromJson(capabilitiesJson);
      }
    } catch (e) {
      debugPrint('Error loading trainer capabilities: $e');
      _trainerCapabilities = TrainerCapabilities.generic;
    }
  }

  RouteCompatibility analyzeGpxCompatibility(GpxWorkout gpxWorkout) {
    final gradients = gpxWorkout.segments.map((s) => s.slope).toList();
    return _trainerCapabilities.analyzeRoute(gradients);
  }

  void skipToNextInterval() {
    if (_currentWorkout == null || _status != WorkoutStatus.running) return;

    _moveToNextInterval();
  }

  void skipToPreviousInterval() {
    if (_currentWorkout == null || _status != WorkoutStatus.running) return;

    if (_currentIntervalIndex > 0) {
      // Track current power for smooth transition
      if (_currentInterval?.mode == WorkoutMode.power) {
        _previousIntervalPower = _currentInterval!.getCurrentPower(
          _intervalElapsedTime,
        );
      }

      _currentIntervalIndex--;
      _currentInterval = _currentWorkout!.intervals[_currentIntervalIndex];
      _intervalElapsedTime = Duration.zero;
      _applyIntervalSettings();
      notifyListeners();
    }
  }

  void _startTimer() {
    _workoutTimer?.cancel();
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), _onTimerTick);
  }

  void _onTimerTick(Timer timer) {
    _elapsedTime += const Duration(seconds: 1);
    _intervalElapsedTime += const Duration(seconds: 1);

    // Update trainer settings (important for ramped intervals)
    _applyIntervalSettings();

    // Collect workout data if we have trainer data
    _collectWorkoutData();

    // Check if we should show countdown for next interval
    _updateCountdown();

    if (_intervalElapsedTime >= _currentInterval!.duration) {
      _moveToNextInterval();
    } else {
      notifyListeners();
    }
  }

  void _updateCountdown() {
    if (_currentWorkout == null || _currentInterval == null) return;

    final timeRemaining = _currentInterval!.duration - _intervalElapsedTime;

    // Check if we're within countdown warning time and not on the last interval
    if (timeRemaining <= _countdownWarningTime &&
        timeRemaining > Duration.zero &&
        _currentIntervalIndex < _currentWorkout!.intervals.length - 1) {
      _countdownSeconds = timeRemaining.inSeconds;
      _nextInterval = _currentWorkout!.intervals[_currentIntervalIndex + 1];
    } else {
      _countdownSeconds = null;
      _nextInterval = null;
    }
  }

  void _moveToNextInterval() {
    if (_currentWorkout == null) return;

    // Save completed interval summary and track its ending power
    if (_currentInterval != null) {
      _saveCompletedInterval();

      // Store the ending power of the current interval for smooth transitions
      if (_currentInterval!.mode == WorkoutMode.power) {
        _previousIntervalPower = _currentInterval!.getCurrentPower(
          _currentInterval!.duration,
        );
      }
    }

    _currentIntervalIndex++;

    if (_currentIntervalIndex >= _currentWorkout!.intervals.length) {
      // Workout completed
      _workoutTimer?.cancel();
      _status = WorkoutStatus.completed;
      notifyListeners();

      // Show completion screen with workout summary
      _showCompletionScreen();
      return;
    }

    _currentInterval = _currentWorkout!.intervals[_currentIntervalIndex];
    _intervalElapsedTime = Duration.zero;
    _applyIntervalSettings();
    notifyListeners();
  }

  void _applyIntervalSettings() {
    if (_currentInterval == null || !_trainerService.isConnected) return;

    switch (_currentInterval!.mode) {
      case WorkoutMode.power:
        // Get the target power for this interval
        final targetPower = _currentInterval!.getCurrentPower(
          _intervalElapsedTime,
        );

        // Apply smooth transition ramping at the start of new intervals
        int powerToApply = targetPower;

        // If we're in the transition period and have a previous power value
        if (_previousIntervalPower != null &&
            _intervalElapsedTime < _transitionDuration &&
            _previousIntervalPower != targetPower) {
          // Calculate transition progress (0.0 to 1.0)
          final transitionProgress =
              _intervalElapsedTime.inSeconds / _transitionDuration.inSeconds;

          // Linear ramp from previous power to target power
          powerToApply =
              (_previousIntervalPower! +
                      (targetPower - _previousIntervalPower!) *
                          transitionProgress)
                  .round();
        }

        _trainerService.setPowerTarget(powerToApply);
        break;
      case WorkoutMode.slope:
        if (_currentInterval!.targetSlope != null) {
          _trainerService.setSlopeTarget(_currentInterval!.targetSlope!);
        }
        break;
      case WorkoutMode.resistance:
        if (_currentInterval!.targetResistance != null) {
          _trainerService.setResistancePercentage(
            _currentInterval!.targetResistance!,
          );
        }
        break;
    }
  }

  void _collectWorkoutData() {
    if (_workoutStartTime == null) return;

    final currentData = _trainerService.currentData;
    if (currentData == null) return;

    // Accumulate distance from speed (m/s * 1s = meters per tick).
    // This is the fallback when the FTMS trainer doesn't report cumulative distance
    // (flag bit 4 is optional per FTMS spec and most trainers omit it).
    final speedMs = currentData.speed / 3.6; // km/h → m/s
    _cumulativeCalculatedDistance += speedMs;

    // Prefer FTMS cumulative distance when the trainer reports it (non-zero),
    // otherwise use the speed-based accumulation.
    final distance = currentData.distance > 0
        ? currentData.distance
        : _cumulativeCalculatedDistance;

    final hr = _heartRateService?.currentHeartRate ?? 0;

    final dataPoint = WorkoutDataPoint(
      timestamp: DateTime.now(),
      power: currentData.power,
      speed: currentData.speed,
      distance: distance,
      heartRate: hr,
    );

    _workoutData.add(dataPoint);

    // Keep up to 3 hours of 1-per-second samples.
    // Removing the oldest point (as was done with 1800) creates a timestamp gap
    // between session.startTime and the first record, which breaks Garmin/Strava charts.
    if (_workoutData.length > 10800) {
      _workoutData.removeAt(0);
    }
  }

  void _saveCompletedInterval() {
    if (_currentInterval == null || _workoutData.isEmpty) return;

    // Get data points for this interval
    final intervalStart = _workoutStartTime!.add(
      _elapsedTime - _intervalElapsedTime,
    );
    final intervalData = _workoutData
        .where(
          (point) =>
              point.timestamp.isAfter(intervalStart) ||
              point.timestamp.isAtSameMomentAs(intervalStart),
        )
        .toList();

    if (intervalData.isNotEmpty) {
      final avgPower =
          intervalData.map((d) => d.power).reduce((a, b) => a + b) /
          intervalData.length;
      final maxPower = intervalData
          .map((d) => d.power)
          .reduce((a, b) => a > b ? a : b);

      final intervalSummary = IntervalSummary(
        name: _currentInterval!.name,
        type: _currentInterval!.type,
        duration: _currentInterval!.duration,
        avgPower: avgPower,
        maxPower: maxPower,
      );

      _completedIntervals.add(intervalSummary);
    }
  }

  void _showCompletionScreen() {
    if (_currentWorkout == null || _workoutStartTime == null) {
      // Fallback to simple completion
      Timer(const Duration(seconds: 3), () {
        if (_status == WorkoutStatus.completed) {
          stopWorkout();
        }
      });
      return;
    }

    // Create workout summary
    final workoutSummary = WorkoutSummary.fromWorkoutData(
      workoutName: _currentWorkout!.name,
      startTime: _workoutStartTime!,
      totalDuration: _elapsedTime,
      totalElapsedTime: _totalElapsedTime,
      dataPoints: _workoutData,
      intervalSummaries: _completedIntervals,
    );

    // Save FIT file automatically
    _saveFitFile(workoutSummary);

    // Fire heads-up notification so user is alerted even when away from the app
    NotificationService().showWorkoutCompleteNotification(
      workoutName: _currentWorkout!.name,
      duration: formatDuration(_elapsedTime),
    );

    // Show completion screen after a brief delay
    Timer(const Duration(seconds: 2), () {
      if (_status == WorkoutStatus.completed) {
        // Navigate to completion screen
        // This will be handled by the UI layer through a callback
        _onWorkoutCompleted?.call(workoutSummary);

        // Auto-stop after 30 seconds if user doesn't interact
        Timer(const Duration(seconds: 30), () {
          if (_status == WorkoutStatus.completed) {
            stopWorkout();
          }
        });
      }
    });
  }

  void _showWorkoutCompletionOnStop() {
    if (_currentWorkout == null || _workoutStartTime == null) return;

    // Store current workout data before clearing
    final currentWorkout = _currentWorkout!;
    final startTime = _workoutStartTime!;
    final elapsedTime = _elapsedTime;
    final workoutData = List<WorkoutDataPoint>.from(_workoutData);
    final completedIntervals = List<IntervalSummary>.from(_completedIntervals);

    // Create workout summary for manually stopped workout
    final workoutSummary = WorkoutSummary.fromWorkoutData(
      workoutName: currentWorkout.name,
      startTime: startTime,
      totalDuration: elapsedTime,
      totalElapsedTime: _totalElapsedTime,
      dataPoints: workoutData,
      intervalSummaries: completedIntervals,
    );

    // Save FIT file automatically for manual stops too
    _saveFitFile(workoutSummary);

    // Show completion screen immediately for manual stops
    Timer(const Duration(milliseconds: 100), () {
      _onWorkoutCompleted?.call(workoutSummary);
    });
  }

  void _showGpxWorkoutCompletion({bool immediate = false}) {
    if (_workoutData.isEmpty || _currentGpxWorkout == null) return;

    // Create workout summary for GPX workouts
    final gpxWorkoutSummary = WorkoutSummary.fromWorkoutData(
      workoutName: '${_currentGpxWorkout!.name} (GPX Route)',
      startTime: _workoutStartTime ?? DateTime.now().subtract(_elapsedTime),
      totalDuration: _elapsedTime,
      totalElapsedTime: _totalElapsedTime,
      dataPoints: _workoutData,
      intervalSummaries: [], // GPX workouts don't have structured intervals
    );

    // Save FIT file automatically for GPX workouts too
    _saveFitFile(gpxWorkoutSummary);

    // Fire heads-up notification so user is alerted even when away from the app
    NotificationService().showWorkoutCompleteNotification(
      workoutName: _currentGpxWorkout!.name,
      duration: formatDuration(_elapsedTime),
    );

    if (immediate) {
      // Show completion screen immediately for manual stops
      _onWorkoutCompleted?.call(gpxWorkoutSummary);
    } else {
      // Show completion screen after a brief delay for automatic completion
      Timer(const Duration(seconds: 2), () {
        if (_status == WorkoutStatus.completed) {
          _onWorkoutCompleted?.call(gpxWorkoutSummary);

          // Auto-stop after 30 seconds if user doesn't interact
          Timer(const Duration(seconds: 30), () {
            if (_status == WorkoutStatus.completed) {
              stopWorkout();
            }
          });
        }
      });
    }
  }

  // Callback for workout completion
  Function(WorkoutSummary)? _onWorkoutCompleted;

  // Callback for FIT validation popup (debug only)
  Function(FitValidationResult)? _onFitValidated;

  void setWorkoutCompletedCallback(Function(WorkoutSummary) callback) {
    _onWorkoutCompleted = callback;
  }

  void setFitValidatedCallback(Function(FitValidationResult) callback) {
    _onFitValidated = callback;
  }

  // Save FIT file automatically after workout completion
  Future<void> _saveFitFile(WorkoutSummary workoutSummary) async {
    try {
      // Only save FIT file if we have meaningful workout data
      if (workoutSummary.powerData.isEmpty ||
          workoutSummary.totalDuration.inSeconds < 10) {
        debugPrint('Skipping FIT file generation - insufficient workout data');
        return;
      }

      debugPrint(
        'Generating FIT file for workout: ${workoutSummary.workoutName}',
      );

      // Create and validate FIT file using fit_tool package
      if (kDebugMode && _onFitValidated != null) {
        final result = await _fitFileService.createAndValidateWorkoutFitFile(
          workoutSummary,
        );
        debugPrint('FIT file generated successfully: ${result.key}');

        // Show validation popup in debug mode
        _onFitValidated!(result.value);
      } else {
        // Just create the file without validation in release mode
        await _fitFileService.createWorkoutFitFile(workoutSummary);
        debugPrint('FIT file generated successfully');
      }
    } catch (e) {
      debugPrint('Error saving FIT file: $e');
      // Don't throw error - FIT file generation failure shouldn't prevent workout completion
    }
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    } else {
      return "$twoDigitMinutes:$twoDigitSeconds";
    }
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _trainerService.removeListener(_onTrainerServiceChanged);
    super.dispose();
  }
}
