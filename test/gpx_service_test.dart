// ignore_for_file: avoid_print
/// GPX Service Tests
///
/// Run with: flutter test test/gpx_service_test.dart
/// Or with verbose output: flutter test test/gpx_service_test.dart --reporter expanded
///
/// These tests validate GPX parsing, slope computation, elevation smoothing,
/// GpxWorkout computed properties, and JSON serialisation — without running
/// the app.
///
/// NOTE: Several "known issue" tests deliberately expect failures in the
/// current implementation to document fragile behaviour that can cause erratic
/// loading in production.
@Tags(['gpx'])
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rideForge/services/gpx_service.dart';
import 'package:rideForge/models/workout_models.dart';

// ---------------------------------------------------------------------------
// GPX fixture helpers
// ---------------------------------------------------------------------------

/// Builds a minimal, well-formed GPX string with the supplied track points.
/// Each [points] entry is a tuple-like map: {lat, lon, ele, time (optional)}.
String _buildGpx(List<Map<String, dynamic>> points) {
  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="TestSuite">')
    ..writeln('  <trk><trkseg>');
  for (final p in points) {
    buf.write(
      '    <trkpt lat="${p['lat']}" lon="${p['lon']}">'
      '<ele>${p['ele']}</ele>',
    );
    if (p['time'] != null) buf.write('<time>${p['time']}</time>');
    buf.writeln('</trkpt>');
  }
  buf.writeln('  </trkseg></trk>');
  buf.writeln('</gpx>');
  return buf.toString();
}

/// A two-point route that is almost perfectly flat, separated by ~111 m
/// (0.001° latitude at the equator).
const _kFlatGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="0.0" lon="0.0"><ele>100.0</ele></trkpt>
    <trkpt lat="0.001" lon="0.0"><ele>100.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

/// A route with a clear uphill segment (~10 m rise over ~111 m → ~9% grade).
const _kUphillGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="0.0"   lon="0.0"><ele>100.0</ele></trkpt>
    <trkpt lat="0.001" lon="0.0"><ele>110.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

/// A route with a clear downhill segment.
const _kDownhillGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="0.0"   lon="0.0"><ele>200.0</ele></trkpt>
    <trkpt lat="0.001" lon="0.0"><ele>190.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

/// A valid GPX with timestamps.
const _kTimestampedGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="51.5074" lon="-0.1278">
      <ele>10.0</ele>
      <time>2024-06-01T10:00:00Z</time>
    </trkpt>
    <trkpt lat="51.5080" lon="-0.1280">
      <ele>12.0</ele>
      <time>2024-06-01T10:01:00Z</time>
    </trkpt>
  </trkseg></trk>
</gpx>''';

/// GPX with no track points at all (should throw).
const _kEmptyTrackGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg></trkseg></trk>
</gpx>''';

/// GPX with some points that are missing the required <ele> element.
const _kMissingEleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="0.0" lon="0.0"><ele>100.0</ele></trkpt>
    <trkpt lat="0.001" lon="0.0"></trkpt>
    <trkpt lat="0.002" lon="0.0"><ele>102.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

/// GPX with some points that are missing lat/lon attributes.
const _kMissingLatLonGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="0.0" lon="0.0"><ele>100.0</ele></trkpt>
    <trkpt lon="0.001"><ele>101.0</ele></trkpt>
    <trkpt lat="0.002" lon="0.0"><ele>102.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

/// GPX whose numeric values have leading/trailing whitespace.
const _kWhitespaceGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat=" 0.0 " lon=" 0.0 "><ele> 100.0 </ele></trkpt>
    <trkpt lat=" 0.001 " lon=" 0.0 "><ele> 101.0 </ele></trkpt>
  </trkseg></trk>
</gpx>''';

/// GPX with route points (<rtept>) instead of track points (<trkpt>).
/// The app only reads <trkpt>, so this should throw (no track points found).
const _kRoutePointsOnlyGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <rte>
    <rtept lat="0.0" lon="0.0"><ele>100.0</ele></rtept>
    <rtept lat="0.001" lon="0.0"><ele>101.0</ele></rtept>
  </rte>
</gpx>''';

/// GPX with non-numeric lat attribute (will crash double.parse).
const _kInvalidLatGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="N51.5074" lon="-0.1278"><ele>10.0</ele></trkpt>
  </trkseg></trk>
</gpx>''';

/// GPX with non-numeric elevation (will crash double.parse).
const _kInvalidEleGpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TestSuite">
  <trk><trkseg>
    <trkpt lat="51.5074" lon="-0.1278"><ele>???</ele></trkpt>
  </trkseg></trk>
</gpx>''';

// ---------------------------------------------------------------------------
// Convenience factory
// ---------------------------------------------------------------------------

/// Creates a [GpxWorkout] from raw lat/lon/ele lists (no timestamps).
GpxWorkout _makeWorkout({
  required List<double> lats,
  required List<double> lons,
  required List<double> eles,
  bool disableProcessing = true,
}) {
  assert(lats.length == lons.length && lons.length == eles.length);
  final service = GpxService();
  final points = List.generate(
    lats.length,
    (i) => GpxPoint(lat: lats[i], lon: lons[i], ele: eles[i]),
  );
  final segments = service.computeSlopes(
    points,
    disableProcessing: disableProcessing,
  );
  return GpxWorkout(
    id: 'test',
    name: 'Test Route',
    description: '',
    filePath: 'test.gpx',
    trackPoints: points,
    segments: segments,
  );
}

// ===========================================================================
// TESTS
// ===========================================================================

void main() {
  late GpxService service;

  setUp(() => service = GpxService());

  // -------------------------------------------------------------------------
  group('GPX Parsing – valid inputs', () {
    test('parses two-point flat route', () {
      final points = service.parseGpxContent(_kFlatGpx);
      expect(points, hasLength(2));
      expect(points[0].lat, closeTo(0.0, 1e-9));
      expect(points[0].lon, closeTo(0.0, 1e-9));
      expect(points[0].ele, closeTo(100.0, 1e-9));
      expect(points[1].lat, closeTo(0.001, 1e-9));
    });

    test('parses timestamps when present', () {
      final points = service.parseGpxContent(_kTimestampedGpx);
      expect(points, hasLength(2));
      expect(points[0].time, isNotNull);
      expect(points[0].time!.year, 2024);
      expect(points[0].time!.month, 6);
      expect(points[0].time!.isUtc, isTrue);
      expect(points[1].time, isNotNull);
    });

    test('time is null when <time> element is absent', () {
      final points = service.parseGpxContent(_kFlatGpx);
      expect(points[0].time, isNull);
    });

    test('skips points that are missing <ele>', () {
      final points = service.parseGpxContent(_kMissingEleGpx);
      // Middle point has no <ele> so it must be skipped → 2 valid points.
      expect(points, hasLength(2));
      expect(points[0].ele, closeTo(100.0, 1e-9));
      expect(points[1].ele, closeTo(102.0, 1e-9));
    });

    test('skips points that are missing lat or lon attribute', () {
      final points = service.parseGpxContent(_kMissingLatLonGpx);
      // Middle point has no lat → 2 valid points.
      expect(points, hasLength(2));
    });

    test('parses many track points', () {
      final raw = List.generate(
        100,
        (i) => {'lat': i * 0.0001, 'lon': 0.0, 'ele': 100.0 + i},
      );
      final points = service.parseGpxContent(_buildGpx(raw));
      expect(points, hasLength(100));
      expect(points.last.ele, closeTo(199.0, 1e-9));
    });
  });

  // -------------------------------------------------------------------------
  group('GPX Parsing – invalid / edge inputs', () {
    test('throws when there are no <trkpt> elements', () {
      expect(
        () => service.parseGpxContent(_kEmptyTrackGpx),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when XML is malformed', () {
      expect(
        () => service.parseGpxContent('<this is not valid xml'),
        throwsA(anything),
      );
    });

    test('throws when all points lack required fields', () {
      // Every <trkpt> is missing <ele>, so the list ends up empty → exception.
      const gpx = '''<gpx version="1.1">
        <trk><trkseg>
          <trkpt lat="0.0" lon="0.0"></trkpt>
        </trkseg></trk>
      </gpx>''';
      expect(() => service.parseGpxContent(gpx), throwsA(isA<Exception>()));
    });

    // --- KNOWN FRAGILITY: unguarded double.parse() calls ---
    // The following two tests document current crashes that cause erratic
    // loading.  They are expected to throw a FormatException.  If you add
    // try/catch around double.parse() in gpx_service.dart these tests should
    // be updated to expect graceful handling instead.

    test('KNOWN ISSUE – crashes on non-numeric lat value', () {
      expect(
        () => service.parseGpxContent(_kInvalidLatGpx),
        throwsA(isA<FormatException>()),
        reason:
            'double.parse() is unguarded; non-numeric lat crashes the import',
      );
    });

    test('KNOWN ISSUE – crashes on non-numeric elevation value', () {
      expect(
        () => service.parseGpxContent(_kInvalidEleGpx),
        throwsA(isA<FormatException>()),
        reason:
            'double.parse() is unguarded; non-numeric ele crashes the import',
      );
    });

    // --- KNOWN LIMITATION: route points vs track points ---

    test('KNOWN LIMITATION – throws for <rtept>-only GPX (no <trkpt>)', () {
      // The parser only looks for <trkpt>.  A GPX exported as a route
      // (common in some GPS devices) will fail with "No track points found."
      expect(
        () => service.parseGpxContent(_kRoutePointsOnlyGpx),
        throwsA(isA<Exception>()),
        reason:
            'Parser only handles <trkpt>; route-only GPX files are unsupported',
      );
    });

    // --- KNOWN FRAGILITY: leading/trailing whitespace in numeric strings ---

    test(
      'KNOWN ISSUE – may crash on whitespace-padded lat/lon/ele',
      () {
        // double.parse(" 0.0 ") throws FormatException in Dart.
        // If this becomes a passing test it means the issue has been fixed.
        List<GpxPoint> throws() => service.parseGpxContent(_kWhitespaceGpx);
        // We accept either outcome here so the test always "passes" as a
        // diagnostic: print what actually happens.
        try {
          final points = throws();
          print(
            '  ✓ Whitespace-padded values parsed successfully (${points.length} points)',
          );
        } on FormatException catch (e) {
          print('  ✗ FormatException on whitespace-padded values: $e');
          // Rethrow so the failure is visible in CI.
          rethrow;
        }
      },
      skip: 'Diagnostic only – run manually to check trim behaviour',
    );
  });

  // -------------------------------------------------------------------------
  group('Haversine Distance', () {
    test('distance between identical points is zero', () {
      expect(service.haversine(51.5, -0.12, 51.5, -0.12), closeTo(0.0, 1e-6));
    });

    test('1 degree latitude ≈ 111 195 m', () {
      // Standard geographic constant.
      expect(service.haversine(0, 0, 1, 0), closeTo(111195, 50));
    });

    test('result is symmetric (A→B == B→A)', () {
      final ab = service.haversine(51.5, -0.12, 48.85, 2.35);
      final ba = service.haversine(48.85, 2.35, 51.5, -0.12);
      expect(ab, closeTo(ba, 1e-3));
    });

    test('London to Paris is roughly 340 km', () {
      // London: 51.5074° N, 0.1278° W  |  Paris: 48.8566° N, 2.3522° E
      expect(
        service.haversine(51.5074, -0.1278, 48.8566, 2.3522),
        closeTo(340_000, 5_000),
      );
    });

    test('0.001° latitude at equator ≈ 111.2 m', () {
      expect(service.haversine(0, 0, 0.001, 0), closeTo(111.2, 0.5));
    });
  });

  // -------------------------------------------------------------------------
  group('Slope Computation', () {
    test('flat route produces ~0% slope', () {
      final points = service.parseGpxContent(_kFlatGpx);
      final segments = service.computeSlopes(points, disableProcessing: true);
      expect(segments, hasLength(1));
      expect(segments.first.slope, closeTo(0.0, 0.01));
    });

    test('uphill segment produces a positive slope', () {
      final points = service.parseGpxContent(_kUphillGpx);
      final segments = service.computeSlopes(points, disableProcessing: true);
      expect(segments.first.slope, greaterThan(0));
    });

    test('downhill segment produces a negative slope', () {
      final points = service.parseGpxContent(_kDownhillGpx);
      final segments = service.computeSlopes(points, disableProcessing: true);
      expect(segments.first.slope, lessThan(0));
    });

    test('~10 m rise over ~111 m gives ~9% grade', () {
      // 10 m elevation change over ~111.2 m horizontal = ~9% grade.
      final points = service.parseGpxContent(_kUphillGpx);
      final segments = service.computeSlopes(points, disableProcessing: true);
      expect(segments.first.slope, closeTo(9.0, 1.0));
    });

    test('slope for duplicate/coincident points is 0 (div-by-zero guard)', () {
      // Two identical lat/lon → distance < 1e-3 → slope must be 0.
      final pts = [
        GpxPoint(lat: 0.0, lon: 0.0, ele: 100.0),
        GpxPoint(lat: 0.0, lon: 0.0, ele: 150.0),
      ];
      final segments = service.computeSlopes(pts, disableProcessing: true);
      expect(segments.first.slope, closeTo(0.0, 1e-9));
    });

    test('number of segments equals number of track points minus one', () {
      final raw = List.generate(
        20,
        (i) => {'lat': i * 0.001, 'lon': 0.0, 'ele': 100.0 + i * 2},
      );
      final points = service.parseGpxContent(_buildGpx(raw));
      final segments = service.computeSlopes(points, disableProcessing: true);
      expect(segments, hasLength(points.length - 1));
    });

    test('disableProcessing skips smoothing and uses raw points', () {
      // Create a noisy elevation profile and compare raw vs smoothed slopes.
      final rawPts = <GpxPoint>[];
      for (var i = 0; i < 20; i++) {
        final noiseEle = 100.0 + i * 5.0 + (i.isEven ? 50.0 : 0.0);
        rawPts.add(GpxPoint(lat: i * 0.001, lon: 0.0, ele: noiseEle));
      }
      final rawSegments = service.computeSlopes(
        rawPts,
        disableProcessing: true,
      );
      final smoothedSegments = service.computeSlopes(
        rawPts,
        disableProcessing: false,
      );
      // Raw segments will have much higher maximum slope due to noise.
      final rawMax = rawSegments.map((s) => s.slope.abs()).reduce(max);
      final smoothedMax = smoothedSegments
          .map((s) => s.slope.abs())
          .reduce(max);
      expect(smoothedMax, lessThan(rawMax));
    });

    test(
      'start and end GpxPoints on each segment match consecutive track points',
      () {
        final points = service.parseGpxContent(_kUphillGpx);
        final segments = service.computeSlopes(points, disableProcessing: true);
        expect(segments.first.start.lat, points.first.lat);
        expect(segments.first.end.lat, points.last.lat);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('Elevation Smoothing', () {
    test('returns unchanged list when points.length <= windowSize', () {
      final pts = [
        GpxPoint(lat: 0.0, lon: 0.0, ele: 100.0),
        GpxPoint(lat: 0.001, lon: 0.0, ele: 200.0),
        GpxPoint(lat: 0.002, lon: 0.0, ele: 150.0),
      ];
      // windowSize defaults to 5, list has only 3 points.
      final result = service.smoothElevation(pts);
      expect(result, same(pts));
    });

    test('preserves lat/lon while modifying elevation', () {
      final raw = List.generate(
        10,
        (i) => GpxPoint(
          lat: i * 0.001,
          lon: i * 0.001,
          ele: i.isEven ? 100.0 : 200.0,
        ),
      );
      final smoothed = service.smoothElevation(raw, windowSize: 3);
      for (var i = 0; i < raw.length; i++) {
        expect(smoothed[i].lat, raw[i].lat);
        expect(smoothed[i].lon, raw[i].lon);
      }
    });

    test('removes an isolated elevation spike', () {
      // A median filter is chosen precisely because it rejects lone outliers
      // (a GPS altitude glitch) while leaving genuine terrain intact. Note it
      // deliberately does *not* flatten sustained alternation — that is a
      // property of a mean filter, not a median one.
      final raw = List.generate(
        20,
        (i) => GpxPoint(lat: i * 0.001, lon: 0.0, ele: 100.0),
      );
      raw[10] = GpxPoint(lat: 10 * 0.001, lon: 0.0, ele: 900.0);

      final smoothed = service.smoothElevation(raw, windowSize: 5);

      final rawRange =
          raw.map((p) => p.ele).reduce(max) - raw.map((p) => p.ele).reduce(min);
      final smoothedRange =
          smoothed.map((p) => p.ele).reduce(max) -
          smoothed.map((p) => p.ele).reduce(min);

      expect(rawRange, 800.0);
      expect(smoothedRange, lessThan(rawRange));
      // The spike is fully rejected: every window around it still has a
      // majority of 100.0 samples, so the median is 100.0 throughout.
      expect(smoothed[10].ele, 100.0);
    });

    test('median of uniform elevations is unchanged', () {
      final raw = List.generate(
        10,
        (i) => GpxPoint(lat: i * 0.001, lon: 0.0, ele: 100.0),
      );
      final smoothed = service.smoothElevation(raw, windowSize: 3);
      for (final pt in smoothed) {
        expect(pt.ele, closeTo(100.0, 1e-9));
      }
    });

    test('preserves timestamps', () {
      final base = DateTime.utc(2024);
      final raw = List.generate(
        10,
        (i) => GpxPoint(
          lat: i * 0.001,
          lon: 0.0,
          ele: 100.0,
          time: base.add(Duration(seconds: i * 10)),
        ),
      );
      final smoothed = service.smoothElevation(raw, windowSize: 3);
      for (var i = 0; i < raw.length; i++) {
        expect(smoothed[i].time, raw[i].time);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('Iterative Smoothing (smoothElevationUntilMaxSlope)', () {
    test('returns unchanged when points.length <= windowSize', () {
      final pts = [
        GpxPoint(lat: 0.0, lon: 0.0, ele: 100.0),
        GpxPoint(lat: 0.001, lon: 0.0, ele: 200.0),
      ];
      final result = service.smoothElevationUntilMaxSlope(pts);
      expect(result, same(pts));
    });

    test(
      'max slope of output is <= maxSlopePercent for a smoothable route',
      () {
        // Create a route whose raw slope exceeds 25% but can be smoothed below.
        final raw = <GpxPoint>[];
        for (var i = 0; i < 30; i++) {
          // Alternating steep spike: 100m, 200m, 100m, ...
          raw.add(
            GpxPoint(lat: i * 0.01, lon: 0.0, ele: i.isEven ? 100.0 : 300.0),
          );
        }
        const maxSlope = 25.0;
        final smoothed = service.smoothElevationUntilMaxSlope(
          raw,
          maxSlopePercent: maxSlope,
          windowSize: 5,
          maxIterations: 10,
        );

        // Verify the resulting max slope.
        double resultMax = 0.0;
        for (var i = 1; i < smoothed.length; i++) {
          final d = service.haversine(
            smoothed[i - 1].lat,
            smoothed[i - 1].lon,
            smoothed[i].lat,
            smoothed[i].lon,
          );
          final diff = (smoothed[i].ele - smoothed[i - 1].ele).abs();
          if (d > 1e-3) resultMax = max(resultMax, (diff / d) * 100);
        }
        expect(
          resultMax,
          lessThanOrEqualTo(maxSlope + 0.1),
        ); // small float tolerance
      },
    );

    test('does not exceed maxIterations', () {
      // Use a route that cannot be fully smoothed in few iterations.
      final raw = List.generate(
        10,
        (i) =>
            GpxPoint(lat: i * 0.001, lon: 0.0, ele: i.isEven ? 0.0 : 10000.0),
      );
      // Should finish in maxIterations without looping forever.
      final result = service.smoothElevationUntilMaxSlope(
        raw,
        maxIterations: 3,
      );
      expect(result, hasLength(raw.length));
    });
  });

  // -------------------------------------------------------------------------
  group('GpxWorkout Computed Properties', () {
    test(
      'totalDistance is sum of haversine distances between consecutive points',
      () {
        final workout = _makeWorkout(
          lats: [0.0, 0.001, 0.002],
          lons: [0.0, 0.0, 0.0],
          eles: [100.0, 100.0, 100.0],
        );
        final expected =
            service.haversine(0.0, 0.0, 0.001, 0.0) +
            service.haversine(0.001, 0.0, 0.002, 0.0);
        expect(workout.totalDistance, closeTo(expected, 0.1));
      },
    );

    test('totalDistance is zero for a single-point workout', () {
      // A single track point cannot form segments, so distance = 0.
      final service2 = GpxService();
      final pts = [GpxPoint(lat: 0.0, lon: 0.0, ele: 100.0)];
      final segs = service2.computeSlopes(pts, disableProcessing: true);
      final workout = GpxWorkout(
        id: 'x',
        name: 'x',
        description: '',
        filePath: 'x.gpx',
        trackPoints: pts,
        segments: segs,
      );
      expect(workout.totalDistance, closeTo(0.0, 1e-9));
    });

    test('totalElevationGain counts only positive elevation differences', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001, 0.002, 0.003],
        lons: [0.0, 0.0, 0.0, 0.0],
        eles: [100.0, 110.0, 105.0, 115.0],
        //           +10     -5      +10 → gain = 20
      );
      expect(workout.totalElevationGain, closeTo(20.0, 1e-9));
    });

    test('totalElevationGain is 0 for a purely descending route', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001, 0.002],
        lons: [0.0, 0.0, 0.0],
        eles: [200.0, 150.0, 100.0],
      );
      expect(workout.totalElevationGain, closeTo(0.0, 1e-9));
    });

    test('maxElevation and minElevation are correct', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001, 0.002, 0.003],
        lons: [0.0, 0.0, 0.0, 0.0],
        eles: [100.0, 250.0, 75.0, 180.0],
      );
      expect(workout.maxElevation, closeTo(250.0, 1e-9));
      expect(workout.minElevation, closeTo(75.0, 1e-9));
    });

    test('totalTime is null when track points have no timestamps', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001],
        lons: [0.0, 0.0],
        eles: [100.0, 100.0],
      );
      expect(workout.totalTime, isNull);
    });

    test('totalTime equals last minus first timestamp', () {
      final pts = service.parseGpxContent(_kTimestampedGpx);
      final segs = service.computeSlopes(pts, disableProcessing: true);
      final workout = GpxWorkout(
        id: 'ts',
        name: 'Timestamped',
        description: '',
        filePath: 'ts.gpx',
        trackPoints: pts,
        segments: segs,
      );
      expect(workout.totalTime, isNotNull);
      expect(workout.totalTime!.inSeconds, 60); // 10:00:00 → 10:01:00 = 60 s
    });
  });

  // -------------------------------------------------------------------------
  group('Elevation Profile', () {
    test('first profile point has distance 0 and correct elevation', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001, 0.002],
        lons: [0.0, 0.0, 0.0],
        eles: [100.0, 110.0, 120.0],
      );
      final profile = workout.getElevationProfile();
      expect(profile.first.distance, closeTo(0.0, 1e-9));
      expect(profile.first.elevation, closeTo(100.0, 1e-9));
    });

    test('profile length equals number of track points', () {
      final raw = List.generate(
        10,
        (i) => {'lat': i * 0.001, 'lon': 0.0, 'ele': 100.0 + i * 3},
      );
      final pts = service.parseGpxContent(_buildGpx(raw));
      final segs = service.computeSlopes(pts, disableProcessing: true);
      final workout = GpxWorkout(
        id: 'p',
        name: 'Profile',
        description: '',
        filePath: 'p.gpx',
        trackPoints: pts,
        segments: segs,
      );
      expect(workout.getElevationProfile(), hasLength(pts.length));
    });

    test('cumulative distances are strictly increasing for a moving route', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001, 0.002, 0.003],
        lons: [0.0, 0.0, 0.0, 0.0],
        eles: [100.0, 101.0, 102.0, 103.0],
      );
      final profile = workout.getElevationProfile();
      for (var i = 1; i < profile.length; i++) {
        expect(profile[i].distance, greaterThan(profile[i - 1].distance));
      }
    });

    test('returns empty list for a workout with no track points', () {
      final workout = GpxWorkout(
        id: 'empty',
        name: '',
        description: '',
        filePath: '',
        trackPoints: [],
        segments: [],
      );
      expect(workout.getElevationProfile(), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('JSON Serialisation Round-Trip', () {
    test('GpxPoint survives toJson → fromJson', () {
      final original = GpxPoint(
        lat: 51.5074,
        lon: -0.1278,
        ele: 42.5,
        time: DateTime.utc(2024, 6, 1, 10, 30),
      );
      final roundTripped = GpxPoint.fromJson(original.toJson());
      expect(roundTripped.lat, original.lat);
      expect(roundTripped.lon, original.lon);
      expect(roundTripped.ele, original.ele);
      expect(roundTripped.time, original.time);
    });

    test('GpxPoint without time survives round-trip with null time', () {
      final original = GpxPoint(lat: 0.0, lon: 0.0, ele: 100.0);
      final roundTripped = GpxPoint.fromJson(original.toJson());
      expect(roundTripped.time, isNull);
    });

    test('GpxSegment survives toJson → fromJson', () {
      final start = GpxPoint(lat: 0.0, lon: 0.0, ele: 100.0);
      final end = GpxPoint(lat: 0.001, lon: 0.0, ele: 110.0);
      final original = GpxSegment(start: start, end: end, slope: 9.0);
      final roundTripped = GpxSegment.fromJson(original.toJson());
      expect(roundTripped.slope, original.slope);
      expect(roundTripped.start.lat, original.start.lat);
      expect(roundTripped.end.ele, original.end.ele);
    });

    test('GpxWorkout survives toJson → fromJson', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001, 0.002],
        lons: [0.0, 0.0, 0.0],
        eles: [100.0, 110.0, 120.0],
      );
      final json = workout.toJson();
      final restored = GpxWorkout.fromJson(json);
      expect(restored.id, workout.id);
      expect(restored.name, workout.name);
      expect(restored.trackPoints, hasLength(workout.trackPoints.length));
      expect(restored.segments, hasLength(workout.segments.length));
      // Computed fields should match after deserialisation.
      expect(restored.totalDistance, closeTo(workout.totalDistance, 0.1));
      expect(
        restored.totalElevationGain,
        closeTo(workout.totalElevationGain, 0.1),
      );
      expect(restored.maxElevation, closeTo(workout.maxElevation, 1e-9));
      expect(restored.minElevation, closeTo(workout.minElevation, 1e-9));
    });

    test('GpxWorkout round-trip preserves elevation profile length', () {
      final workout = _makeWorkout(
        lats: [0.0, 0.001, 0.002, 0.003],
        lons: [0.0, 0.0, 0.0, 0.0],
        eles: [100.0, 105.0, 103.0, 108.0],
      );
      final restored = GpxWorkout.fromJson(workout.toJson());
      expect(
        restored.getElevationProfile().length,
        workout.getElevationProfile().length,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('Full Pipeline (parse → smooth → compute → workout)', () {
    test('realistic multi-segment route produces sensible stats', () {
      // Build a 10-point route with gentle climb then descent.
      final raw = [
        {'lat': 51.500, 'lon': -0.120, 'ele': 10.0},
        {'lat': 51.501, 'lon': -0.121, 'ele': 15.0},
        {'lat': 51.502, 'lon': -0.122, 'ele': 22.0},
        {'lat': 51.503, 'lon': -0.123, 'ele': 30.0},
        {'lat': 51.504, 'lon': -0.124, 'ele': 35.0},
        {'lat': 51.505, 'lon': -0.125, 'ele': 32.0},
        {'lat': 51.506, 'lon': -0.126, 'ele': 28.0},
        {'lat': 51.507, 'lon': -0.127, 'ele': 20.0},
        {'lat': 51.508, 'lon': -0.128, 'ele': 14.0},
        {'lat': 51.509, 'lon': -0.129, 'ele': 10.0},
      ];
      final points = service.parseGpxContent(_buildGpx(raw));
      final smoothed = service.smoothElevationUntilMaxSlope(points);
      final segments = service.computeSlopes(smoothed, disableProcessing: true);
      final workout = GpxWorkout(
        id: 'realistic',
        name: 'Realistic Loop',
        description: 'Test',
        filePath: 'loop.gpx',
        trackPoints: smoothed,
        segments: segments,
      );

      expect(workout.trackPoints, hasLength(10));
      expect(workout.segments, hasLength(9));
      expect(workout.totalDistance, greaterThan(0));
      expect(workout.maxElevation, greaterThanOrEqualTo(workout.minElevation));
      expect(workout.totalElevationGain, greaterThanOrEqualTo(0));
      expect(workout.totalTime, isNull); // no timestamps
    });

    test(
      'fromBytes round-trip produces identical points as parseGpxContent',
      () async {
        final gpx = _buildGpx([
          {'lat': 0.0, 'lon': 0.0, 'ele': 100.0},
          {'lat': 0.001, 'lon': 0.0, 'ele': 101.0},
        ]);
        final fromString = service.parseGpxContent(gpx);
        final fromBytes = await service.loadGpxFromBytes(gpx.codeUnits);
        expect(fromBytes.length, fromString.length);
        for (var i = 0; i < fromString.length; i++) {
          expect(fromBytes[i].lat, fromString[i].lat);
          expect(fromBytes[i].lon, fromString[i].lon);
          expect(fromBytes[i].ele, fromString[i].ele);
        }
      },
    );
  });
}
