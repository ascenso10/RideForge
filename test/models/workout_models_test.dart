import 'package:flutter_test/flutter_test.dart';
import 'package:rideForge/models/workout_models.dart';

WorkoutInterval _interval({
  String id = '1',
  Duration duration = const Duration(minutes: 5),
  IntervalType type = IntervalType.work,
  WorkoutMode mode = WorkoutMode.power,
  int? targetPower = 200,
  PowerRamp? ramp,
}) => WorkoutInterval(
  id: id,
  name: 'Interval $id',
  duration: duration,
  type: type,
  mode: mode,
  targetPower: targetPower,
  powerRamp: ramp,
);

void main() {
  group('PowerRamp.getPowerAtTime', () {
    const total = Duration(minutes: 10);

    test('linear ramp interpolates between start and end', () {
      final ramp = PowerRamp(startPower: 100, endPower: 300);
      expect(ramp.getPowerAtTime(Duration.zero, total), 100);
      expect(ramp.getPowerAtTime(const Duration(minutes: 5), total), 200);
      expect(ramp.getPowerAtTime(total, total), 300);
    });

    test('descending linear ramp works', () {
      final ramp = PowerRamp(startPower: 300, endPower: 100);
      expect(ramp.getPowerAtTime(const Duration(minutes: 5), total), 200);
    });

    test('step ramp jumps at the halfway point', () {
      final ramp = PowerRamp(
        startPower: 100,
        endPower: 300,
        type: RampType.step,
      );
      expect(ramp.getPowerAtTime(const Duration(minutes: 4), total), 100);
      expect(ramp.getPowerAtTime(const Duration(minutes: 5), total), 300);
    });

    test('exponential ramp lags a linear ramp at the midpoint', () {
      final ramp = PowerRamp(
        startPower: 100,
        endPower: 300,
        type: RampType.exponential,
      );
      // progress 0.5 -> 0.25 of the range
      expect(ramp.getPowerAtTime(const Duration(minutes: 5), total), 150);
      expect(ramp.getPowerAtTime(total, total), 300);
    });

    test('elapsed beyond duration is clamped to end power', () {
      final ramp = PowerRamp(startPower: 100, endPower: 300);
      expect(ramp.getPowerAtTime(const Duration(minutes: 20), total), 300);
    });

    test('zero total duration returns start power', () {
      final ramp = PowerRamp(startPower: 100, endPower: 300);
      expect(ramp.getPowerAtTime(Duration.zero, Duration.zero), 100);
    });

    test('JSON round trip preserves all fields', () {
      final ramp = PowerRamp(
        startPower: 120,
        endPower: 280,
        type: RampType.exponential,
      );
      final copy = PowerRamp.fromJson(ramp.toJson());
      expect(copy.startPower, 120);
      expect(copy.endPower, 280);
      expect(copy.type, RampType.exponential);
    });

    test('unknown ramp type falls back to linear', () {
      final copy = PowerRamp.fromJson({
        'startPower': 100,
        'endPower': 200,
        'type': 'bogus',
      });
      expect(copy.type, RampType.linear);
    });
  });

  group('WorkoutInterval', () {
    test('getCurrentPower returns target power without a ramp', () {
      expect(_interval(targetPower: 250).getCurrentPower(Duration.zero), 250);
    });

    test('getCurrentPower returns 0 when no target is set', () {
      expect(_interval(targetPower: null).getCurrentPower(Duration.zero), 0);
    });

    test('getCurrentPower follows the ramp in power mode', () {
      final interval = _interval(
        duration: const Duration(minutes: 10),
        ramp: PowerRamp(startPower: 100, endPower: 300),
      );
      expect(interval.hasRamping, isTrue);
      expect(interval.getCurrentPower(const Duration(minutes: 5)), 200);
    });

    test('ramp is ignored outside power mode', () {
      final interval = _interval(
        mode: WorkoutMode.slope,
        targetPower: null,
        ramp: PowerRamp(startPower: 100, endPower: 300),
      );
      expect(interval.getCurrentPower(const Duration(minutes: 5)), 0);
    });

    test('JSON round trip preserves all fields', () {
      final interval = WorkoutInterval(
        id: 'x',
        name: 'Climb',
        duration: const Duration(seconds: 90),
        type: IntervalType.cooldown,
        mode: WorkoutMode.slope,
        targetSlope: 4.5,
        targetResistance: 30,
        description: 'steady',
        powerRamp: PowerRamp(startPower: 100, endPower: 150),
      );
      final copy = WorkoutInterval.fromJson(interval.toJson());
      expect(copy.id, 'x');
      expect(copy.name, 'Climb');
      expect(copy.duration, const Duration(seconds: 90));
      expect(copy.type, IntervalType.cooldown);
      expect(copy.mode, WorkoutMode.slope);
      expect(copy.targetSlope, 4.5);
      expect(copy.targetResistance, 30);
      expect(copy.description, 'steady');
      expect(copy.powerRamp?.endPower, 150);
    });

    test('unknown type and mode fall back to work and power', () {
      final copy = WorkoutInterval.fromJson({
        'id': '1',
        'name': 'n',
        'duration': 60,
        'type': 'nope',
        'mode': 'nope',
      });
      expect(copy.type, IntervalType.work);
      expect(copy.mode, WorkoutMode.power);
    });

    test('integer slope in JSON is read as a double', () {
      final copy = WorkoutInterval.fromJson({
        'id': '1',
        'name': 'n',
        'duration': 60,
        'type': 'work',
        'mode': 'slope',
        'targetSlope': 3,
      });
      expect(copy.targetSlope, 3.0);
    });
  });

  group('Workout', () {
    test('totalDuration is the sum of interval durations', () {
      final workout = Workout(
        id: 'w',
        name: 'W',
        description: 'd',
        intervals: [
          _interval(id: '1', duration: const Duration(minutes: 5)),
          _interval(id: '2', duration: const Duration(minutes: 7)),
        ],
      );
      expect(workout.totalDuration, const Duration(minutes: 12));
    });

    test('empty workout has zero duration', () {
      final workout = Workout(
        id: 'w',
        name: 'W',
        description: 'd',
        intervals: [],
      );
      expect(workout.totalDuration, Duration.zero);
    });

    test('JSON round trip preserves intervals', () {
      final workout = Workout(
        id: 'w',
        name: 'W',
        description: 'd',
        intervals: [_interval(id: '1'), _interval(id: '2', targetPower: 300)],
      );
      final copy = Workout.fromJson(workout.toJson());
      expect(copy.id, 'w');
      expect(copy.name, 'W');
      expect(copy.description, 'd');
      expect(copy.intervals.map((i) => i.id), ['1', '2']);
      expect(copy.intervals[1].targetPower, 300);
      expect(copy.totalDuration, workout.totalDuration);
    });
  });

  group('Workout.getDefaultWorkouts', () {
    test('returns uniquely identified, non-empty workouts', () {
      final workouts = Workout.getDefaultWorkouts(ftp: 250);
      expect(workouts, isNotEmpty);
      expect(workouts.map((w) => w.id).toSet().length, workouts.length);
      for (final w in workouts) {
        expect(w.intervals, isNotEmpty, reason: w.name);
        expect(w.totalDuration, greaterThan(Duration.zero), reason: w.name);
      }
    });

    test('includes the FTP ramp test', () {
      final ids = Workout.getDefaultWorkouts().map((w) => w.id);
      expect(ids, contains('ftp_ramp_test'));
    });

    test('every power interval has a sane target (>= 50 W)', () {
      for (final w in Workout.getDefaultWorkouts(ftp: 100)) {
        for (final i in w.intervals.where(
          (i) => i.mode == WorkoutMode.power,
        )) {
          expect(
            i.targetPower,
            greaterThanOrEqualTo(50),
            reason: '${w.name} / ${i.name}',
          );
        }
      }
    });

    test('null, zero and negative FTP fall back to the 200 W default', () {
      List<int?> powers(int? ftp) => Workout.getDefaultWorkouts(
        ftp: ftp,
      ).expand((w) => w.intervals).map((i) => i.targetPower).toList();

      expect(powers(null), powers(200));
      expect(powers(0), powers(200));
      expect(powers(-50), powers(200));
    });

    test('power targets scale with FTP, except the fixed ramp test', () {
      final low = Workout.getDefaultWorkouts(ftp: 200);
      final high = Workout.getDefaultWorkouts(ftp: 300);

      List<int> powerTargets(Workout w) => w.intervals
          .where((x) => x.mode == WorkoutMode.power)
          .map((x) => x.targetPower!)
          .toList();

      for (var i = 0; i < low.length; i++) {
        expect(high[i].id, low[i].id);
        final lowPowers = powerTargets(low[i]);
        final highPowers = powerTargets(high[i]);
        if (lowPowers.isEmpty) continue; // slope-only workouts have no watts
        if (low[i].id == 'ftp_ramp_test') {
          expect(highPowers, lowPowers);
        } else {
          for (var j = 0; j < lowPowers.length; j++) {
            expect(
              highPowers[j],
              greaterThanOrEqualTo(lowPowers[j]),
              reason: '${low[i].name} interval $j',
            );
          }
          expect(
            highPowers.reduce((a, b) => a > b ? a : b),
            greaterThan(lowPowers.reduce((a, b) => a > b ? a : b)),
            reason: low[i].name,
          );
        }
      }
    });

    test('slope-mode intervals carry a slope target', () {
      final slopeIntervals = Workout.getDefaultWorkouts()
          .expand((w) => w.intervals)
          .where((i) => i.mode == WorkoutMode.slope);
      expect(slopeIntervals, isNotEmpty);
      for (final i in slopeIntervals) {
        expect(i.targetSlope, isNotNull, reason: i.name);
      }
    });

    test('ramp test ramps 100 to 600 W over 25 minutes', () {
      final ramp = Workout.getDefaultWorkouts().firstWhere(
        (w) => w.id == 'ftp_ramp_test',
      );
      final rampInterval = ramp.intervals.firstWhere((i) => i.hasRamping);
      expect(rampInterval.duration, const Duration(minutes: 25));
      expect(rampInterval.powerRamp!.startPower, 100);
      expect(rampInterval.powerRamp!.endPower, 600);
    });
  });

  group('FtpEntry', () {
    test('JSON round trip', () {
      final entry = FtpEntry(ftp: 245, date: DateTime.utc(2026, 3, 14, 9, 30));
      final copy = FtpEntry.fromJson(entry.toJson());
      expect(copy.ftp, 245);
      expect(copy.date, entry.date);
    });
  });

  group('WorkoutSummary', () {
    final start = DateTime.utc(2026, 1, 1, 8);

    WorkoutDataPoint point(double power, double speed, {int hr = 0}) =>
        WorkoutDataPoint(
          timestamp: start,
          power: power,
          speed: speed,
          heartRate: hr,
        );

    test('fromWorkoutData with no data yields zeroed stats', () {
      final s = WorkoutSummary.fromWorkoutData(
        workoutName: 'Empty',
        startTime: start,
        totalDuration: const Duration(minutes: 10),
        totalElapsedTime: const Duration(minutes: 10),
        dataPoints: [],
        intervalSummaries: [],
      );
      expect(s.avgPower, 0);
      expect(s.maxPower, 0);
      expect(s.avgSpeed, 0);
      expect(s.totalEnergy, 0);
      expect(s.powerData, isEmpty);
    });

    test('fromWorkoutData computes averages, max and energy', () {
      final s = WorkoutSummary.fromWorkoutData(
        workoutName: 'W',
        startTime: start,
        totalDuration: const Duration(seconds: 100),
        totalElapsedTime: const Duration(seconds: 120),
        dataPoints: [point(100, 8), point(200, 10), point(300, 12)],
        intervalSummaries: [],
      );
      expect(s.avgPower, 200);
      expect(s.maxPower, 300);
      expect(s.avgSpeed, 10);
      expect(s.totalEnergy, 200 * 100); // joules
      expect(s.totalElapsedTime, const Duration(seconds: 120));
      expect(s.dataPoints, same(s.powerData));
    });

    test('heart rate stats ignore samples without HR data', () {
      final s = WorkoutSummary.fromWorkoutData(
        workoutName: 'W',
        startTime: start,
        totalDuration: const Duration(seconds: 60),
        totalElapsedTime: const Duration(seconds: 60),
        dataPoints: [
          point(100, 8),
          point(100, 8, hr: 120),
          point(100, 8, hr: 160),
        ],
        intervalSummaries: [],
      );
      expect(s.avgHeartRate, 140);
      expect(s.maxHeartRate, 160);
    });

    test('heart rate is 0 when no HR samples exist', () {
      final s = WorkoutSummary.fromWorkoutData(
        workoutName: 'W',
        startTime: start,
        totalDuration: const Duration(seconds: 60),
        totalElapsedTime: const Duration(seconds: 60),
        dataPoints: [point(100, 8)],
        intervalSummaries: [],
      );
      expect(s.avgHeartRate, 0);
      expect(s.maxHeartRate, 0);
    });

    test('JSON round trip preserves stats, samples and intervals', () {
      final original = WorkoutSummary.fromWorkoutData(
        workoutName: 'Round trip',
        startTime: start,
        totalDuration: const Duration(minutes: 30),
        totalElapsedTime: const Duration(minutes: 32),
        dataPoints: [point(150, 9, hr: 130), point(250, 11, hr: 150)],
        intervalSummaries: [
          IntervalSummary(
            name: 'Warm-up',
            type: IntervalType.warmup,
            duration: const Duration(minutes: 10),
            avgPower: 120,
            maxPower: 140,
          ),
        ],
      );
      final copy = WorkoutSummary.fromJson(original.toJson());

      expect(copy.workoutName, 'Round trip');
      expect(copy.startTime, start);
      expect(copy.totalDuration, const Duration(minutes: 30));
      expect(copy.totalElapsedTime, const Duration(minutes: 32));
      expect(copy.avgPower, original.avgPower);
      expect(copy.maxPower, original.maxPower);
      expect(copy.avgHeartRate, original.avgHeartRate);
      expect(copy.maxHeartRate, original.maxHeartRate);
      expect(copy.powerData.length, 2);
      expect(copy.powerData[1].heartRate, 150);
      expect(copy.intervalSummaries.single.type, IntervalType.warmup);
      expect(copy.intervalSummaries.single.avgPower, 120);
    });

    test('fromJson tolerates legacy data without elapsed time or HR', () {
      final copy = WorkoutSummary.fromJson({
        'workoutName': 'Old',
        'startTime': start.toIso8601String(),
        'totalDuration': 600,
        'avgPower': 100,
        'maxPower': 200,
        'avgSpeed': 8,
        'totalEnergy': 60000,
      });
      expect(copy.totalElapsedTime, const Duration(seconds: 600));
      expect(copy.avgHeartRate, 0);
      expect(copy.maxHeartRate, 0);
      expect(copy.powerData, isEmpty);
      expect(copy.intervalSummaries, isEmpty);
    });
  });
}
