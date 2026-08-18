import 'dart:math';
import '../services/gpx_service.dart';

enum IntervalType { warmup, work, rest, cooldown }

enum WorkoutMode { power, slope, resistance }

class PowerRamp {
  final int startPower;
  final int endPower;
  final RampType type;

  PowerRamp({
    required this.startPower,
    required this.endPower,
    this.type = RampType.linear,
  });

  factory PowerRamp.fromJson(Map<String, dynamic> json) {
    return PowerRamp(
      startPower: json['startPower'],
      endPower: json['endPower'],
      type: RampType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RampType.linear,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'startPower': startPower, 'endPower': endPower, 'type': type.name};
  }

  int getPowerAtTime(Duration elapsed, Duration totalDuration) {
    if (totalDuration.inSeconds == 0) return startPower;

    final progress = elapsed.inSeconds / totalDuration.inSeconds;
    final clampedProgress = progress.clamp(0.0, 1.0);

    switch (type) {
      case RampType.linear:
        return (startPower + (endPower - startPower) * clampedProgress).round();
      case RampType.step:
        return clampedProgress < 0.5 ? startPower : endPower;
      case RampType.exponential:
        // Exponential curve for more realistic ramping
        final expProgress = (clampedProgress * clampedProgress);
        return (startPower + (endPower - startPower) * expProgress).round();
    }
  }
}

enum RampType {
  linear, // Steady increase/decrease
  step, // Jump to new power halfway through
  exponential, // Accelerating increase/decrease
}

class WorkoutInterval {
  final String id;
  final String name;
  final Duration duration;
  final IntervalType type;
  final WorkoutMode mode;
  final int? targetPower;
  final double? targetSlope;
  final double? targetResistance; // Now as percentage (0.0 - 100.0)
  final String? description;
  final PowerRamp? powerRamp; // NEW: Optional power ramping

  WorkoutInterval({
    required this.id,
    required this.name,
    required this.duration,
    required this.type,
    required this.mode,
    this.targetPower,
    this.targetSlope,
    this.targetResistance,
    this.description,
    this.powerRamp,
  });

  // Get current power based on elapsed time (supports ramping)
  int getCurrentPower(Duration elapsed) {
    if (powerRamp != null && mode == WorkoutMode.power) {
      return powerRamp!.getPowerAtTime(elapsed, duration);
    }
    return targetPower ?? 0;
  }

  // Check if this interval has power ramping
  bool get hasRamping => powerRamp != null;

  factory WorkoutInterval.fromJson(Map<String, dynamic> json) {
    return WorkoutInterval(
      id: json['id'],
      name: json['name'],
      duration: Duration(seconds: json['duration']),
      type: IntervalType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => IntervalType.work,
      ),
      mode: WorkoutMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => WorkoutMode.power,
      ),
      targetPower: json['targetPower'],
      targetSlope: json['targetSlope']?.toDouble(),
      targetResistance: json['targetResistance']?.toDouble(),
      description: json['description'],
      powerRamp: json['powerRamp'] != null
          ? PowerRamp.fromJson(json['powerRamp'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'duration': duration.inSeconds,
      'type': type.name,
      'mode': mode.name,
      'targetPower': targetPower,
      'targetSlope': targetSlope,
      'targetResistance': targetResistance,
      'description': description,
      'powerRamp': powerRamp?.toJson(),
    };
  }
}

class Workout {
  final String id;
  final String name;
  final String description;
  final List<WorkoutInterval> intervals;
  final Duration totalDuration;

  Workout({
    required this.id,
    required this.name,
    required this.description,
    required this.intervals,
  }) : totalDuration = intervals.fold(
         Duration.zero,
         (total, interval) => total + interval.duration,
       );

  factory Workout.fromJson(Map<String, dynamic> json) {
    return Workout(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      intervals: (json['intervals'] as List)
          .map((interval) => WorkoutInterval.fromJson(interval))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'intervals': intervals.map((interval) => interval.toJson()).toList(),
    };
  }

  /// Returns default workouts with power targets scaled to [ftp].
  /// When [ftp] is null or 0 a sensible default of 200 W is used so workouts
  /// always display valid watt values even before the user has completed an
  /// FTP test.
  static List<Workout> getDefaultWorkouts({int? ftp}) {
    final f = (ftp != null && ftp > 0) ? ftp : 200;

    // Helper: watts as a percentage of FTP, minimum 50 W
    int w(double pct) => max(50, (f * pct).round());

    return [
      // ── FTP Ramp Test (no FTP scaling – fixed ramp protocol) ──────────────
      Workout(
        id: 'ftp_ramp_test',
        name: 'FTP Ramp Test',
        description:
            'Ramp test to estimate your Functional Threshold Power. Ride until failure, then skip to cool-down — your FTP is ~75% of the power you were at when you cracked.',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Warm-up',
            duration: const Duration(minutes: 10),
            type: IntervalType.warmup,
            mode: WorkoutMode.power,
            targetPower: 100,
            description: 'Easy warm-up at steady pace',
          ),
          WorkoutInterval(
            id: '2',
            name: 'Ramp',
            duration: const Duration(minutes: 25),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: 100,
            powerRamp: PowerRamp(
              startPower: 100,
              endPower: 600,
              type: RampType.linear,
            ),
            description:
                'Power rises 20 W/min — skip to cool-down when you can no longer hold the target',
          ),
          WorkoutInterval(
            id: '3',
            name: 'Cool-down',
            duration: const Duration(minutes: 5),
            type: IntervalType.cooldown,
            mode: WorkoutMode.power,
            targetPower: 80,
            description: 'Easy spinning to recover',
          ),
        ],
      ),

      // ── Recovery Session (<55% FTP, 45 min) ───────────────────────────────
      Workout(
        id: 'recovery_session',
        name: 'Recovery Session',
        description:
            'Active recovery at very easy effort. Keeps the legs moving without adding fatigue.',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Recovery Ride',
            duration: const Duration(minutes: 45),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP — spin easy and breathe',
          ),
        ],
      ),

      // ── Steady Endurance (Zone 2) ─────────────────────────────────────────
      Workout(
        id: 'steady_endurance',
        name: 'Steady Endurance',
        description:
            'Classic Zone 2 aerobic base builder. Gradually ramp into a long steady effort.',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Warm-up',
            duration: const Duration(minutes: 12),
            type: IntervalType.warmup,
            mode: WorkoutMode.power,
            targetPower: w(0.55),
            powerRamp: PowerRamp(
              startPower: w(0.55),
              endPower: w(0.70),
              type: RampType.linear,
            ),
            description: 'Gradually ramp from 55% up to 70% FTP',
          ),
          WorkoutInterval(
            id: '2',
            name: 'Main Set',
            duration: const Duration(minutes: 60),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.70),
            description: '70% FTP — steady aerobic effort',
          ),
          WorkoutInterval(
            id: '3',
            name: 'Cool-down',
            duration: const Duration(minutes: 5),
            type: IntervalType.cooldown,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP — easy spin out',
          ),
        ],
      ),

      // ── Tempo Session (Zone 3) ────────────────────────────────────────────
      Workout(
        id: 'tempo_session',
        name: 'Tempo Session',
        description:
            'Zone 3 muscular endurance. "Comfortably hard" — you can\'t talk easily, but you aren\'t gasping.',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Warm-up',
            duration: const Duration(minutes: 10),
            type: IntervalType.warmup,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            powerRamp: PowerRamp(
              startPower: w(0.50),
              endPower: w(0.65),
              type: RampType.linear,
            ),
            description: 'Ramp from 50% FTP',
          ),
          WorkoutInterval(
            id: '2',
            name: 'Tempo 1',
            duration: const Duration(minutes: 15),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.80),
            description: '80% FTP',
          ),
          WorkoutInterval(
            id: '3',
            name: 'Recovery',
            duration: const Duration(minutes: 5),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP',
          ),
          WorkoutInterval(
            id: '4',
            name: 'Tempo 2',
            duration: const Duration(minutes: 15),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.80),
            description: '80% FTP',
          ),
          WorkoutInterval(
            id: '5',
            name: 'Recovery',
            duration: const Duration(minutes: 5),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP',
          ),
          WorkoutInterval(
            id: '6',
            name: 'Tempo 3',
            duration: const Duration(minutes: 15),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.80),
            description: '80% FTP',
          ),
          WorkoutInterval(
            id: '7',
            name: 'Cool-down',
            duration: const Duration(minutes: 5),
            type: IntervalType.cooldown,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP',
          ),
        ],
      ),

      // ── Sweet Spot Session ────────────────────────────────────────────────
      Workout(
        id: 'sweet_spot',
        name: 'Sweet Spot',
        description:
            'The biggest bang for your buck. 88–93% FTP sits at the top of Zone 3 / bottom of Zone 4 — high training stimulus without full threshold fatigue.',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Warm-up',
            duration: const Duration(minutes: 7),
            type: IntervalType.warmup,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: 'Easy warm-up',
          ),
          WorkoutInterval(
            id: '2',
            name: 'Primer',
            duration: const Duration(minutes: 3),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.85),
            description: '85% FTP primer to open the legs',
          ),
          WorkoutInterval(
            id: '3',
            name: 'Easy',
            duration: const Duration(minutes: 2),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: 'Easy before main set',
          ),
          WorkoutInterval(
            id: '4',
            name: 'Sweet Spot 1',
            duration: const Duration(minutes: 20),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.90),
            description: 'Sweet Spot — 90% FTP (Z3/Z4 boundary)',
          ),
          WorkoutInterval(
            id: '5',
            name: 'Recovery',
            duration: const Duration(minutes: 5),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP',
          ),
          WorkoutInterval(
            id: '6',
            name: 'Sweet Spot 2',
            duration: const Duration(minutes: 20),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.90),
            description: 'Sweet Spot — 90% FTP (Z3/Z4 boundary)',
          ),
          WorkoutInterval(
            id: '7',
            name: 'Cool-down',
            duration: const Duration(minutes: 10),
            type: IntervalType.cooldown,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP',
          ),
        ],
      ),

      // ── Threshold Session (Zone 4) ────────────────────────────────────────
      Workout(
        id: 'threshold_session',
        name: 'Threshold Session',
        description:
            'Zone 4 — increases your actual FTP. These are limit sessions that require significant mental effort.',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Warm-up',
            duration: const Duration(minutes: 11),
            type: IntervalType.warmup,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: 'Easy warm-up',
          ),
          WorkoutInterval(
            id: '2',
            name: 'Primer 1',
            duration: const Duration(minutes: 2),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.95),
            description: '95% FTP — open the lungs',
          ),
          WorkoutInterval(
            id: '3',
            name: 'Easy',
            duration: const Duration(minutes: 2),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: 'Easy',
          ),
          WorkoutInterval(
            id: '4',
            name: 'Primer 2',
            duration: const Duration(minutes: 2),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(0.95),
            description: '95% FTP',
          ),
          WorkoutInterval(
            id: '5',
            name: 'Easy',
            duration: const Duration(minutes: 2),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: 'Easy',
          ),
          WorkoutInterval(
            id: '6',
            name: 'Threshold 1',
            duration: const Duration(minutes: 8),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(1.00),
            description: '100% FTP',
          ),
          WorkoutInterval(
            id: '7',
            name: 'Recovery',
            duration: const Duration(minutes: 8),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.48),
            description: '<50% FTP',
          ),
          WorkoutInterval(
            id: '8',
            name: 'Threshold 2',
            duration: const Duration(minutes: 8),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(1.00),
            description: '100% FTP',
          ),
          WorkoutInterval(
            id: '9',
            name: 'Recovery',
            duration: const Duration(minutes: 8),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.48),
            description: '<50% FTP',
          ),
          WorkoutInterval(
            id: '10',
            name: 'Threshold 3',
            duration: const Duration(minutes: 8),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(1.00),
            description: '100% FTP',
          ),
          WorkoutInterval(
            id: '11',
            name: 'Recovery',
            duration: const Duration(minutes: 8),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.48),
            description: '<50% FTP',
          ),
          WorkoutInterval(
            id: '12',
            name: 'Threshold 4',
            duration: const Duration(minutes: 8),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(1.00),
            description: '100% FTP',
          ),
          WorkoutInterval(
            id: '13',
            name: 'Cool-down',
            duration: const Duration(minutes: 12),
            type: IntervalType.cooldown,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: '<55% FTP',
          ),
        ],
      ),

      // ── Interval Training ─────────────────────────────────────────────────
      Workout(
        id: 'interval_training',
        name: 'Interval Training',
        description:
            'Zone 5 VO₂ Max intervals — 4-minute efforts at 120% FTP to raise your aerobic ceiling.',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Warm-up',
            duration: const Duration(minutes: 15),
            type: IntervalType.warmup,
            mode: WorkoutMode.power,
            targetPower: w(0.60),
            description: 'Progressive warm-up',
          ),
          WorkoutInterval(
            id: '2',
            name: 'Work Interval 1',
            duration: const Duration(minutes: 4),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(1.20),
            description: 'Zone 5 VO₂ Max — 120% FTP',
          ),
          WorkoutInterval(
            id: '3',
            name: 'Recovery 1',
            duration: const Duration(minutes: 2),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: 'Active recovery',
          ),
          WorkoutInterval(
            id: '4',
            name: 'Work Interval 2',
            duration: const Duration(minutes: 4),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(1.20),
            description: 'Zone 5 VO₂ Max — 120% FTP',
          ),
          WorkoutInterval(
            id: '5',
            name: 'Recovery 2',
            duration: const Duration(minutes: 2),
            type: IntervalType.rest,
            mode: WorkoutMode.power,
            targetPower: w(0.50),
            description: 'Active recovery',
          ),
          WorkoutInterval(
            id: '6',
            name: 'Work Interval 3',
            duration: const Duration(minutes: 4),
            type: IntervalType.work,
            mode: WorkoutMode.power,
            targetPower: w(1.20),
            description: 'Zone 5 VO₂ Max — 120% FTP',
          ),
          WorkoutInterval(
            id: '7',
            name: 'Cool-down',
            duration: const Duration(minutes: 10),
            type: IntervalType.cooldown,
            mode: WorkoutMode.power,
            targetPower: w(0.40),
            description: 'Easy spinning',
          ),
        ],
      ),

      // ── Hill Climbing (slope-based, no FTP dependency) ────────────────────
      Workout(
        id: 'hill_climbing',
        name: 'Hill Climbing',
        description: 'Simulate various hill gradients',
        intervals: [
          WorkoutInterval(
            id: '1',
            name: 'Warm-up',
            duration: const Duration(minutes: 10),
            type: IntervalType.warmup,
            mode: WorkoutMode.slope,
            targetSlope: 0.0,
            description: 'Flat warm-up',
          ),
          WorkoutInterval(
            id: '2',
            name: 'Gentle Hill',
            duration: const Duration(minutes: 8),
            type: IntervalType.work,
            mode: WorkoutMode.slope,
            targetSlope: 3.0,
            description: '3% gradient',
          ),
          WorkoutInterval(
            id: '3',
            name: 'Recovery',
            duration: const Duration(minutes: 3),
            type: IntervalType.rest,
            mode: WorkoutMode.slope,
            targetSlope: 0.0,
            description: 'Flat recovery',
          ),
          WorkoutInterval(
            id: '4',
            name: 'Moderate Hill',
            duration: const Duration(minutes: 6),
            type: IntervalType.work,
            mode: WorkoutMode.slope,
            targetSlope: 5.0,
            description: '5% gradient',
          ),
          WorkoutInterval(
            id: '5',
            name: 'Recovery',
            duration: const Duration(minutes: 4),
            type: IntervalType.rest,
            mode: WorkoutMode.slope,
            targetSlope: 0.0,
            description: 'Flat recovery',
          ),
          WorkoutInterval(
            id: '6',
            name: 'Steep Hill',
            duration: const Duration(minutes: 10),
            type: IntervalType.work,
            mode: WorkoutMode.slope,
            targetSlope: 6.0,
            description: '6% gradient',
          ),
          WorkoutInterval(
            id: '7',
            name: 'Cool-down',
            duration: const Duration(minutes: 10),
            type: IntervalType.cooldown,
            mode: WorkoutMode.slope,
            targetSlope: 0.0,
            description: 'Flat cool-down',
          ),
        ],
      ),
    ];
  }
}

class FtpEntry {
  final int ftp;
  final DateTime date;

  FtpEntry({required this.ftp, required this.date});

  Map<String, dynamic> toJson() => {'ftp': ftp, 'date': date.toIso8601String()};

  factory FtpEntry.fromJson(Map<String, dynamic> json) =>
      FtpEntry(ftp: json['ftp'], date: DateTime.parse(json['date']));
}

class WorkoutSample {
  DateTime timestamp;
  int power; // watts
  double speed; // m/s
  double distance; // m

  WorkoutSample(this.timestamp, this.power, this.speed, this.distance);
}

class GpxWorkout {
  final String id;
  final String name;
  final String description;
  final String filePath;
  final List<GpxPoint> trackPoints;
  final List<GpxSegment> segments;
  final double totalDistance; // in meters
  final double totalElevationGain; // in meters
  final double maxElevation; // in meters
  final double minElevation; // in meters
  final Duration? totalTime; // if GPX has timestamps

  GpxWorkout({
    required this.id,
    required this.name,
    required this.description,
    required this.filePath,
    required this.trackPoints,
    required this.segments,
  }) : totalDistance = _calculateTotalDistance(segments),
       totalElevationGain = _calculateElevationGain(trackPoints),
       maxElevation = _calculateMaxElevation(trackPoints),
       minElevation = _calculateMinElevation(trackPoints),
       totalTime = _calculateTotalTime(trackPoints);

  static double _calculateTotalDistance(List<GpxSegment> segments) {
    return segments.fold(0.0, (sum, segment) {
      return sum +
          _haversine(
            segment.start.lat,
            segment.start.lon,
            segment.end.lat,
            segment.end.lon,
          );
    });
  }

  static double _calculateElevationGain(List<GpxPoint> points) {
    double gain = 0.0;
    for (int i = 1; i < points.length; i++) {
      final diff = points[i].ele - points[i - 1].ele;
      if (diff > 0) gain += diff;
    }
    return gain;
  }

  static double _calculateMaxElevation(List<GpxPoint> points) {
    return points.isEmpty
        ? 0.0
        : points.map((p) => p.ele).reduce((a, b) => a > b ? a : b);
  }

  static double _calculateMinElevation(List<GpxPoint> points) {
    return points.isEmpty
        ? 0.0
        : points.map((p) => p.ele).reduce((a, b) => a < b ? a : b);
  }

  static Duration? _calculateTotalTime(List<GpxPoint> points) {
    if (points.isEmpty ||
        points.first.time == null ||
        points.last.time == null) {
      return null;
    }
    return points.last.time!.difference(points.first.time!);
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000; // Earth radius in meters
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  factory GpxWorkout.fromJson(Map<String, dynamic> json) {
    return GpxWorkout(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      filePath: json['filePath'],
      trackPoints: (json['trackPoints'] as List)
          .map((point) => GpxPoint.fromJson(point))
          .toList(),
      segments: (json['segments'] as List)
          .map((segment) => GpxSegment.fromJson(segment))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'filePath': filePath,
      'trackPoints': trackPoints.map((point) => point.toJson()).toList(),
      'segments': segments.map((segment) => segment.toJson()).toList(),
    };
  }

  List<ElevationPoint> getElevationProfile() {
    if (trackPoints.isEmpty) return [];

    double currentDistance = 0.0;
    final List<ElevationPoint> profile = [
      ElevationPoint(distance: 0.0, elevation: trackPoints.first.ele),
    ];

    for (int i = 1; i < trackPoints.length; i++) {
      final segmentDistance = _haversine(
        trackPoints[i - 1].lat,
        trackPoints[i - 1].lon,
        trackPoints[i].lat,
        trackPoints[i].lon,
      );
      currentDistance += segmentDistance;
      profile.add(
        ElevationPoint(
          distance: currentDistance,
          elevation: trackPoints[i].ele,
        ),
      );
    }

    return profile;
  }
}

class ElevationPoint {
  final double distance; // cumulative distance in meters
  final double elevation; // elevation in meters

  ElevationPoint({required this.distance, required this.elevation});
}

class WorkoutDataPoint {
  final DateTime timestamp;
  final double power;
  final double speed;
  final double distance; // cumulative distance in meters from FTMS
  final int heartRate; // bpm from BLE HR monitor

  WorkoutDataPoint({
    required this.timestamp,
    required this.power,
    required this.speed,
    this.distance = 0.0,
    this.heartRate = 0,
  });
}

class IntervalSummary {
  final String name;
  final IntervalType type;
  final Duration duration;
  final double avgPower;
  final double maxPower;

  IntervalSummary({
    required this.name,
    required this.type,
    required this.duration,
    required this.avgPower,
    required this.maxPower,
  });
}

class WorkoutSummary {
  final String workoutName;
  final DateTime startTime;
  final Duration totalDuration; // workout duration (excluding pauses)
  final Duration totalElapsedTime; // total elapsed time (including pauses)
  final List<WorkoutDataPoint> powerData;
  final List<IntervalSummary> intervalSummaries;
  final double avgPower;
  final double maxPower;
  final double avgSpeed;
  final double totalEnergy; // in joules
  final int avgHeartRate;
  final int maxHeartRate;

  WorkoutSummary({
    required this.workoutName,
    required this.startTime,
    required this.totalDuration,
    required this.totalElapsedTime,
    required this.powerData,
    required this.intervalSummaries,
    required this.avgPower,
    required this.maxPower,
    required this.avgSpeed,
    required this.totalEnergy,
    this.avgHeartRate = 0,
    this.maxHeartRate = 0,
  });

  factory WorkoutSummary.fromWorkoutData({
    required String workoutName,
    required DateTime startTime,
    required Duration totalDuration,
    required Duration totalElapsedTime,
    required List<WorkoutDataPoint> dataPoints,
    required List<IntervalSummary> intervalSummaries,
  }) {
    if (dataPoints.isEmpty) {
      return WorkoutSummary(
        workoutName: workoutName,
        startTime: startTime,
        totalDuration: totalDuration,
        totalElapsedTime: totalElapsedTime,
        powerData: [],
        intervalSummaries: intervalSummaries,
        avgPower: 0,
        maxPower: 0,
        avgSpeed: 0,
        totalEnergy: 0,
      );
    }

    final avgPower =
        dataPoints.map((d) => d.power).reduce((a, b) => a + b) /
        dataPoints.length;
    final maxPower = dataPoints
        .map((d) => d.power)
        .reduce((a, b) => a > b ? a : b);
    final avgSpeed =
        dataPoints.map((d) => d.speed).reduce((a, b) => a + b) /
        dataPoints.length;

    // Calculate total energy (joules) = average power * time in seconds
    final totalEnergy = avgPower * totalDuration.inSeconds;

    // Calculate heart rate stats (only from points with HR data)
    final hrPoints = dataPoints.where((d) => d.heartRate > 0).toList();
    final avgHr = hrPoints.isNotEmpty
        ? (hrPoints.map((d) => d.heartRate).reduce((a, b) => a + b) /
                  hrPoints.length)
              .round()
        : 0;
    final maxHr = hrPoints.isNotEmpty
        ? hrPoints.map((d) => d.heartRate).reduce((a, b) => a > b ? a : b)
        : 0;

    return WorkoutSummary(
      workoutName: workoutName,
      startTime: startTime,
      totalDuration: totalDuration,
      totalElapsedTime: totalElapsedTime,
      powerData: dataPoints,
      intervalSummaries: intervalSummaries,
      avgPower: avgPower,
      maxPower: maxPower,
      avgSpeed: avgSpeed,
      totalEnergy: totalEnergy,
      avgHeartRate: avgHr,
      maxHeartRate: maxHr,
    );
  }

  factory WorkoutSummary.fromJson(Map<String, dynamic> json) {
    return WorkoutSummary(
      workoutName: json['workoutName'],
      startTime: DateTime.parse(json['startTime']),
      totalDuration: Duration(seconds: json['totalDuration']),
      totalElapsedTime: Duration(
        seconds: json['totalElapsedTime'] ?? json['totalDuration'],
      ), // fallback for backward compatibility
      powerData:
          (json['powerData'] as List?)
              ?.map(
                (data) => WorkoutDataPoint(
                  timestamp: DateTime.parse(data['timestamp']),
                  power: data['power'].toDouble(),
                  speed: data['speed'].toDouble(),
                  heartRate: data['heartRate'] ?? 0,
                ),
              )
              .toList() ??
          [],
      intervalSummaries:
          (json['intervalSummaries'] as List?)
              ?.map(
                (summary) => IntervalSummary(
                  name: summary['name'],
                  type: IntervalType.values.firstWhere(
                    (e) => e.name == summary['type'],
                    orElse: () => IntervalType.work,
                  ),
                  duration: Duration(seconds: summary['duration']),
                  avgPower: summary['avgPower'].toDouble(),
                  maxPower: summary['maxPower'].toDouble(),
                ),
              )
              .toList() ??
          [],
      avgPower: json['avgPower'].toDouble(),
      maxPower: json['maxPower'].toDouble(),
      avgSpeed: json['avgSpeed'].toDouble(),
      totalEnergy: json['totalEnergy'].toDouble(),
      avgHeartRate: json['avgHeartRate'] ?? 0,
      maxHeartRate: json['maxHeartRate'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'workoutName': workoutName,
      'startTime': startTime.toIso8601String(),
      'totalDuration': totalDuration.inSeconds,
      'totalElapsedTime': totalElapsedTime.inSeconds,
      'powerData': powerData
          .map(
            (data) => {
              'timestamp': data.timestamp.toIso8601String(),
              'power': data.power,
              'speed': data.speed,
              'heartRate': data.heartRate,
            },
          )
          .toList(),
      'intervalSummaries': intervalSummaries
          .map(
            (summary) => {
              'name': summary.name,
              'type': summary.type.name,
              'duration': summary.duration.inSeconds,
              'avgPower': summary.avgPower,
              'maxPower': summary.maxPower,
            },
          )
          .toList(),
      'avgPower': avgPower,
      'maxPower': maxPower,
      'avgSpeed': avgSpeed,
      'totalEnergy': totalEnergy,
      'avgHeartRate': avgHeartRate,
      'maxHeartRate': maxHeartRate,
    };
  }

  // Add a getter for backward compatibility
  List<WorkoutDataPoint> get dataPoints => powerData;
}

class FitValidationResult {
  final String filePath;
  final int fileSize;
  final int messageCount;
  final bool isValid;
  final String? error;

  // File ID info
  final String? fileType;
  final int? manufacturer;
  final int? product;
  final DateTime? timeCreated; // When FIT file was created

  // Timing info
  final DateTime? workoutStartTime; // Original workout start time
  final int? sessionTotalElapsedTime; // ms
  final int? sessionTotalTimerTime; // ms

  // Session info (most important)
  final double? sessionTotalDistance; // m
  final int? sessionAvgPower; // W
  final int? sessionMaxPower; // W
  final double? sessionAvgSpeed; // m/s

  // Activity info
  final int? activityTotalTimerTime; // ms

  // Record info
  final int recordCount;
  final String? firstRecordInfo;
  final String? lastRecordInfo;

  FitValidationResult({
    required this.filePath,
    required this.fileSize,
    required this.messageCount,
    required this.isValid,
    this.error,
    this.fileType,
    this.manufacturer,
    this.product,
    this.timeCreated,
    this.workoutStartTime,
    this.sessionTotalElapsedTime,
    this.sessionTotalTimerTime,
    this.sessionTotalDistance,
    this.sessionAvgPower,
    this.sessionMaxPower,
    this.sessionAvgSpeed,
    this.activityTotalTimerTime,
    required this.recordCount,
    this.firstRecordInfo,
    this.lastRecordInfo,
  });

  Duration? get sessionElapsedDuration => sessionTotalElapsedTime != null
      ? Duration(milliseconds: sessionTotalElapsedTime!)
      : null;

  Duration? get sessionTimerDuration => sessionTotalTimerTime != null
      ? Duration(milliseconds: sessionTotalTimerTime!)
      : null;

  Duration? get pauseTime =>
      sessionTotalElapsedTime != null && sessionTotalTimerTime != null
      ? Duration(
          milliseconds: sessionTotalElapsedTime! - sessionTotalTimerTime!,
        )
      : null;

  String formatDuration(Duration? duration) {
    if (duration == null) return 'N/A';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return "${duration.inHours}:$twoDigitMinutes:$twoDigitSeconds";
    } else {
      return "$twoDigitMinutes:$twoDigitSeconds";
    }
  }
}
