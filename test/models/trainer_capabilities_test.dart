import 'package:flutter_test/flutter_test.dart';
import 'package:rideForge/models/trainer_capabilities.dart';

TrainerCapabilities _caps({
  double min = 0.0,
  double max = 6.0,
  GradientHandlingMode mode = GradientHandlingMode.clamp,
  GradientCompensationMode compensation = GradientCompensationMode.none,
  double factor = 1.0,
}) => TrainerCapabilities(
  maxGradient: max,
  minGradient: min,
  maxPower: 600,
  maxResistance: 100,
  gradientMode: mode,
  compensationMode: compensation,
  compensationFactor: factor,
);

void main() {
  group('constrainGradient', () {
    test('clamp mode limits to min and max', () {
      final c = _caps(min: -2, max: 6);
      expect(c.constrainGradient(10), 6);
      expect(c.constrainGradient(-5), -2);
      expect(c.constrainGradient(3), 3);
    });

    test('scale mode currently caps at the limits', () {
      final c = _caps(min: -2, max: 6, mode: GradientHandlingMode.scale);
      expect(c.constrainGradient(10), 6);
      expect(c.constrainGradient(-5), -2);
      expect(c.constrainGradient(3), 3);
    });

    test('warn mode leaves the gradient untouched', () {
      final c = _caps(max: 6, mode: GradientHandlingMode.warn);
      expect(c.constrainGradient(12), 12);
      expect(c.constrainGradient(-9), -9);
    });
  });

  group('isGradientSupported', () {
    test('limits are inclusive', () {
      final c = _caps(min: -2, max: 6);
      expect(c.isGradientSupported(6), isTrue);
      expect(c.isGradientSupported(-2), isTrue);
      expect(c.isGradientSupported(6.01), isFalse);
      expect(c.isGradientSupported(-2.01), isFalse);
    });
  });

  group('calculateCompensation', () {
    test('no compensation when gradient is within limits', () {
      final c = _caps(compensation: GradientCompensationMode.directResistance);
      final r = c.calculateCompensation(4);
      expect(r.adjustedGradient, 4);
      expect(r.additionalResistance, 0);
      expect(r.rollingResistance, 0);
    });

    test('mode none only clamps', () {
      final r = _caps(max: 6).calculateCompensation(10);
      expect(r.adjustedGradient, 6);
      expect(r.additionalResistance, 0);
      expect(r.rollingResistance, 0);
    });

    test('rolling resistance: 0.001 per lost percent', () {
      final r = _caps(
        max: 6,
        compensation: GradientCompensationMode.rollingResistance,
      ).calculateCompensation(10);
      expect(r.adjustedGradient, 6);
      expect(r.rollingResistance, closeTo(0.004, 1e-9));
      expect(r.additionalResistance, 0);
    });

    test('direct resistance: 15% per lost percent', () {
      final r = _caps(
        max: 6,
        compensation: GradientCompensationMode.directResistance,
      ).calculateCompensation(8);
      expect(r.adjustedGradient, 6);
      expect(r.additionalResistance, closeTo(30, 1e-9));
      expect(r.rollingResistance, 0);
    });

    test('direct resistance is capped at 100%', () {
      final r = _caps(
        max: 6,
        compensation: GradientCompensationMode.directResistance,
      ).calculateCompensation(30);
      expect(r.additionalResistance, 100);
    });

    test('compensation factor scales the lost gradient', () {
      final r = _caps(
        max: 6,
        factor: 0.5,
        compensation: GradientCompensationMode.directResistance,
      ).calculateCompensation(8);
      expect(r.additionalResistance, closeTo(15, 1e-9));
    });

    test('losses of 0.01 or less are ignored', () {
      final r = _caps(
        max: 6,
        compensation: GradientCompensationMode.directResistance,
      ).calculateCompensation(6.005);
      expect(r.additionalResistance, 0);
    });
  });

  group('analyzeRoute', () {
    test('empty route is fully compatible', () {
      final r = _caps().analyzeRoute([]);
      expect(r.compatibilityScore, 1.0);
      expect(r.totalSegments, 0);
      expect(r.isFullySupported, isTrue);
    });

    test('counts unsupported segments and computes the score', () {
      final r = _caps(min: 0, max: 6).analyzeRoute([1, 2, 8, 12]);
      expect(r.totalSegments, 4);
      expect(r.cappedSegments, 2);
      expect(r.compatibilityScore, 0.5);
      expect(r.maxOriginalGradient, 12);
      expect(r.maxTrainerGradient, 6);
      expect(r.isFullySupported, isFalse);
    });

    test('maxOriginalGradient is the largest by magnitude', () {
      final r = _caps(min: -20, max: 20).analyzeRoute([3, -15, 8]);
      expect(r.maxOriginalGradient, -15);
    });
  });

  group('RouteCompatibility labels', () {
    RouteCompatibility rc(double score, int capped) => RouteCompatibility(
      compatibilityScore: score,
      cappedSegments: capped,
      totalSegments: 10,
      maxOriginalGradient: 0,
      maxTrainerGradient: 6,
    );

    test('fully supported', () {
      expect(rc(1.0, 0).compatibilityLabel, 'Fully Supported');
    });
    test('minor limitations at 0.8 and above', () {
      expect(rc(0.8, 2).compatibilityLabel, 'Minor Limitations');
    });
    test('moderate limitations between 0.5 and 0.8', () {
      expect(rc(0.6, 4).compatibilityLabel, 'Moderate Limitations');
      expect(rc(0.5, 5).compatibilityLabel, 'Moderate Limitations');
    });
    test('major limitations below 0.5', () {
      expect(rc(0.49, 6).compatibilityLabel, 'Major Limitations');
    });
  });

  group('JSON', () {
    test('round trip preserves all fields', () {
      final c = _caps(
        min: -3,
        max: 9,
        mode: GradientHandlingMode.warn,
        compensation: GradientCompensationMode.rollingResistance,
        factor: 0.75,
      );
      final copy = TrainerCapabilities.fromJson(c.toJson());
      expect(copy.minGradient, -3);
      expect(copy.maxGradient, 9);
      expect(copy.maxPower, 600);
      expect(copy.maxResistance, 100);
      expect(copy.gradientMode, GradientHandlingMode.warn);
      expect(copy.compensationMode, GradientCompensationMode.rollingResistance);
      expect(copy.compensationFactor, 0.75);
    });

    test('empty JSON yields the generic defaults', () {
      final c = TrainerCapabilities.fromJson({});
      expect(c.maxGradient, TrainerCapabilities.generic.maxGradient);
      expect(c.minGradient, TrainerCapabilities.generic.minGradient);
      expect(c.maxPower, TrainerCapabilities.generic.maxPower);
      expect(c.maxResistance, TrainerCapabilities.generic.maxResistance);
      expect(c.gradientMode, GradientHandlingMode.clamp);
      expect(c.compensationMode, GradientCompensationMode.none);
      expect(c.compensationFactor, 1.0);
    });

    test('unknown mode names fall back to defaults', () {
      final c = TrainerCapabilities.fromJson({
        'gradientMode': 'bogus',
        'compensationMode': 'bogus',
      });
      expect(c.gradientMode, GradientHandlingMode.clamp);
      expect(c.compensationMode, GradientCompensationMode.none);
    });
  });
}
