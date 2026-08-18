// ignore_for_file: avoid_print
/// GPX Route Validator
///
/// Loads a real GPX file through the same pipeline the app uses and prints
/// a detailed report so you can verify the data before deploying.
///
/// Usage:
///   dart run test/gpx_validator.dart <path/to/route.gpx>
///
/// Example:
///   dart run test/gpx_validator.dart ~/Downloads/my_route.gpx
library;

import 'dart:io';
import 'dart:math';

import 'package:rideForge/services/gpx_service.dart';
import 'package:rideForge/models/workout_models.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  if (args.isEmpty) {
    _die('Usage: dart run test/gpx_validator.dart <path/to/route.gpx>');
  }

  final filePath = args[0];
  final file = File(filePath);

  if (!file.existsSync()) {
    _die('File not found: $filePath');
  }

  final fileSizeKb = (file.lengthSync() / 1024).toStringAsFixed(1);
  _header('GPX Validator');
  print('File : $filePath');
  print('Size : $fileSizeKb KB');

  // -------------------------------------------------------------------------
  // 1. Parse raw track points
  // -------------------------------------------------------------------------
  _section('1. Parsing track points');

  final service = GpxService();
  late List<GpxPoint> rawPoints;

  try {
    rawPoints = await service.loadGpx(filePath);
  } on FormatException catch (e) {
    _fail(
      'FormatException while parsing — a numeric field contains an '
      'invalid value.\n  Detail: $e',
    );
    exit(1);
  } on Exception catch (e) {
    _fail('Failed to parse GPX: $e');
    exit(1);
  }

  print('Track points parsed : ${rawPoints.length}');
  print('Has timestamps      : ${rawPoints.any((p) => p.time != null)}');
  _printPointSummary('First point', rawPoints.first);
  _printPointSummary('Last point ', rawPoints.last);

  // -------------------------------------------------------------------------
  // 2. Raw elevation stats
  // -------------------------------------------------------------------------
  _section('2. Raw elevation (before smoothing)');

  final rawEles = rawPoints.map((p) => p.ele).toList();
  _printElevationStats(rawEles);

  // -------------------------------------------------------------------------
  // 3. Raw slopes (before smoothing / disableProcessing = true)
  // -------------------------------------------------------------------------
  _section('3. Raw slopes (disableProcessing = true)');

  final rawSegments = service.computeSlopes(rawPoints, disableProcessing: true);
  _printSlopeStats(rawSegments, label: 'raw');

  // -------------------------------------------------------------------------
  // 4. Smoothed slopes (default app settings: iterative smoothing, max 25%)
  // -------------------------------------------------------------------------
  _section('4. Processed slopes (app defaults: iterative smoothing, max 25%)');

  final processedSegments = service.computeSlopes(
    rawPoints,
    disableProcessing: false,
    smoothElevations: true,
    useIterativeSmoothing: true,
    maxSlopePercent: 25.0,
    smoothingWindow: 5,
  );
  _printSlopeStats(processedSegments, label: 'processed');

  // -------------------------------------------------------------------------
  // 5. GpxWorkout computed fields
  // -------------------------------------------------------------------------
  _section('5. GpxWorkout computed fields');

  final workout = GpxWorkout(
    id: 'validator',
    name: file.uri.pathSegments.last,
    description: '',
    filePath: filePath,
    trackPoints: rawPoints,
    segments: processedSegments,
  );

  final distKm = (workout.totalDistance / 1000).toStringAsFixed(2);
  print(
    'Total distance      : $distKm km  (${workout.totalDistance.toStringAsFixed(0)} m)',
  );
  print(
    'Elevation gain      : ${workout.totalElevationGain.toStringAsFixed(1)} m',
  );
  print('Max elevation       : ${workout.maxElevation.toStringAsFixed(1)} m');
  print('Min elevation       : ${workout.minElevation.toStringAsFixed(1)} m');
  print(
    'Elevation range     : ${(workout.maxElevation - workout.minElevation).toStringAsFixed(1)} m',
  );

  if (workout.totalTime != null) {
    final t = workout.totalTime!;
    print(
      'Total time          : ${t.inHours}h ${t.inMinutes.remainder(60)}m ${t.inSeconds.remainder(60)}s',
    );
  } else {
    print('Total time          : n/a (no timestamps in file)');
  }

  // -------------------------------------------------------------------------
  // 6. ASCII elevation profile
  // -------------------------------------------------------------------------
  _section('6. Elevation profile (ASCII)');
  _printAsciiProfile(workout.getElevationProfile());

  // -------------------------------------------------------------------------
  // 7. Slope distribution chart
  // -------------------------------------------------------------------------
  _section('7. Slope distribution (processed segments)');
  _printSlopeHistogram(processedSegments);

  // -------------------------------------------------------------------------
  // 8. Suspicious segments
  // -------------------------------------------------------------------------
  _section('8. Suspicious segments (|slope| > 20%)');
  _printSuspiciousSegments(processedSegments, threshold: 20.0);

  // -------------------------------------------------------------------------
  // Summary verdict
  // -------------------------------------------------------------------------
  _section('Summary');
  _printVerdict(rawPoints, processedSegments, workout);
}

// ---------------------------------------------------------------------------
// Report helpers
// ---------------------------------------------------------------------------

void _header(String title) {
  final line = '═' * (title.length + 4);
  print('\n╔$line╗');
  print('║  $title  ║');
  print('╚$line╝');
}

void _section(String title) {
  print('\n── $title ${'─' * (60 - title.length - 4)}');
}

void _fail(String msg) => print('\n❌  $msg');

void _die(String msg) {
  print(msg);
  exit(1);
}

void _printPointSummary(String label, GpxPoint p) {
  final t = p.time != null ? '  time=${p.time!.toIso8601String()}' : '';
  print(
    '$label : lat=${p.lat.toStringAsFixed(6)}  '
    'lon=${p.lon.toStringAsFixed(6)}  '
    'ele=${p.ele.toStringAsFixed(1)} m$t',
  );
}

void _printElevationStats(List<double> eles) {
  final minEle = eles.reduce(min);
  final maxEle = eles.reduce(max);
  final avgEle = eles.reduce((a, b) => a + b) / eles.length;

  // Standard deviation
  final variance =
      eles.map((e) => pow(e - avgEle, 2)).reduce((a, b) => a + b) / eles.length;
  final stdDev = sqrt(variance);

  print('Min : ${minEle.toStringAsFixed(1)} m');
  print('Max : ${maxEle.toStringAsFixed(1)} m');
  print('Avg : ${avgEle.toStringAsFixed(1)} m');
  print(
    'Std : ${stdDev.toStringAsFixed(1)} m  '
    '(high std-dev may indicate GPS noise)',
  );
}

void _printSlopeStats(List<GpxSegment> segments, {required String label}) {
  if (segments.isEmpty) {
    print('No segments.');
    return;
  }
  final slopes = segments.map((s) => s.slope).toList();
  final minSlope = slopes.reduce(min);
  final maxSlope = slopes.reduce(max);
  final avgSlope = slopes.reduce((a, b) => a + b) / slopes.length;
  final absSlopes = slopes.map((s) => s.abs()).toList()..sort();
  final p95 =
      absSlopes[(absSlopes.length * 0.95).floor().clamp(
        0,
        absSlopes.length - 1,
      )];

  print('Segments : ${segments.length}');
  print(
    'Min slope: ${minSlope.toStringAsFixed(2)}%  '
    '(${minSlope < -25 ? "⚠️  very steep descent" : "ok"})',
  );
  print(
    'Max slope: ${maxSlope.toStringAsFixed(2)}%  '
    '(${maxSlope > 25 ? "⚠️  very steep climb" : "ok"})',
  );
  print('Avg slope: ${avgSlope.toStringAsFixed(2)}%');
  print(
    'p95 |slope|: ${p95.toStringAsFixed(2)}%  '
    '(95% of segments are below this)',
  );
}

void _printAsciiProfile(List<ElevationPoint> profile) {
  if (profile.isEmpty) {
    print('(empty)');
    return;
  }

  const width = 60;
  const height = 10;

  final totalDist = profile.last.distance;
  final minEle = profile.map((p) => p.elevation).reduce(min);
  final maxEle = profile.map((p) => p.elevation).reduce(max);
  final eleRange = maxEle - minEle;

  // Sample the profile into [width] buckets
  final buckets = List<double>.filled(width, minEle);
  for (final p in profile) {
    final col = ((p.distance / totalDist) * (width - 1)).round().clamp(
      0,
      width - 1,
    );
    if (p.elevation > buckets[col]) buckets[col] = p.elevation;
  }

  // Render rows top → bottom
  final grid = List.generate(height, (_) => List<String>.filled(width, ' '));
  for (var col = 0; col < width; col++) {
    final normalised = eleRange > 0 ? (buckets[col] - minEle) / eleRange : 0.0;
    final row = (height - 1) - (normalised * (height - 1)).round();
    for (var r = row; r < height; r++) {
      grid[r][col] = '█';
    }
  }

  print('  ${maxEle.toStringAsFixed(0)} m ┐');
  for (final row in grid) {
    print('         │${row.join()}');
  }
  print('  ${minEle.toStringAsFixed(0)} m ┘${'─' * width}');
  print(
    '         0 km${' ' * (width - 10)}${(totalDist / 1000).toStringAsFixed(1)} km',
  );
}

void _printSlopeHistogram(List<GpxSegment> segments) {
  // Buckets: <= -15, -15..-10, -10..-5, -5..0, 0..5, 5..10, 10..15, >15
  final labels = [
    '≤-15%',
    '-15..-10',
    '-10..-5',
    '-5..0',
    '0..5',
    '5..10',
    '10..15',
    '≥15%',
  ];
  final counts = List<int>.filled(8, 0);

  for (final s in segments) {
    final g = s.slope;
    if (g <= -15) {
      counts[0]++;
    } else if (g <= -10)
      counts[1]++;
    else if (g <= -5)
      counts[2]++;
    else if (g < 0)
      counts[3]++;
    else if (g < 5)
      counts[4]++;
    else if (g < 10)
      counts[5]++;
    else if (g < 15)
      counts[6]++;
    else
      counts[7]++;
  }

  final total = segments.length;
  const barMax = 30;
  for (var i = 0; i < labels.length; i++) {
    final pct = total > 0 ? counts[i] / total : 0.0;
    final bar = '█' * (pct * barMax).round();
    final flag = (i == 0 || i == 7) && counts[i] > 0 ? ' ⚠️' : '';
    print(
      '${labels[i].padLeft(9)} │$bar ${counts[i]} (${(pct * 100).toStringAsFixed(1)}%)$flag',
    );
  }
}

void _printSuspiciousSegments(
  List<GpxSegment> segments, {
  required double threshold,
}) {
  final suspicious = segments.where((s) => s.slope.abs() > threshold).toList();

  if (suspicious.isEmpty) {
    print(
      'None found — all processed slopes are within ±${threshold.toStringAsFixed(0)}%.',
    );
    return;
  }

  print('Found ${suspicious.length} segment(s) with |slope| > $threshold%:\n');
  for (final s in suspicious.take(20)) {
    print(
      '  slope=${s.slope.toStringAsFixed(2)}%'
      '  from (${s.start.lat.toStringAsFixed(5)}, ${s.start.lon.toStringAsFixed(5)}'
      '  ele=${s.start.ele.toStringAsFixed(1)}m)'
      '  →  (${s.end.lat.toStringAsFixed(5)}, ${s.end.lon.toStringAsFixed(5)}'
      '  ele=${s.end.ele.toStringAsFixed(1)}m)',
    );
  }
  if (suspicious.length > 20) {
    print('  … and ${suspicious.length - 20} more.');
  }
}

void _printVerdict(
  List<GpxPoint> points,
  List<GpxSegment> segments,
  GpxWorkout workout,
) {
  final issues = <String>[];

  if (points.length < 2) {
    issues.add(
      'Too few track points (${points.length}) — route cannot form segments.',
    );
  }
  if (workout.totalDistance < 100) {
    issues.add(
      'Total distance is very short (${workout.totalDistance.toStringAsFixed(0)} m) — check the file.',
    );
  }
  if (workout.maxElevation > 8850) {
    issues.add(
      'Max elevation ${workout.maxElevation.toStringAsFixed(0)} m exceeds Everest — likely GPS noise.',
    );
  }
  if (workout.minElevation < -500) {
    issues.add(
      'Min elevation ${workout.minElevation.toStringAsFixed(0)} m is below sea floor — likely GPS noise.',
    );
  }

  final extremeSlopes = segments.where((s) => s.slope.abs() > 25).length;
  if (extremeSlopes > 0) {
    issues.add(
      '$extremeSlopes segment(s) still exceed ±25% after smoothing — '
      'may cause unrealistic trainer resistance.',
    );
  }

  if (issues.isEmpty) {
    print('✅  Route looks valid and ready to use.');
  } else {
    print('⚠️  ${issues.length} issue(s) found:\n');
    for (final issue in issues) {
      print('  • $issue');
    }
  }
}
