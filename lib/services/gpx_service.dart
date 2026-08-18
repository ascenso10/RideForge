import 'dart:io';
import 'dart:math';
import 'package:xml/xml.dart';

/// Represents a single point in a GPX track
class GpxPoint {
  final double lat;
  final double lon;
  final double ele; // elevation in meters
  final DateTime? time; // optional timestamp

  GpxPoint({
    required this.lat,
    required this.lon,
    required this.ele,
    this.time,
  });

  factory GpxPoint.fromJson(Map<String, dynamic> json) {
    return GpxPoint(
      lat: json['lat'].toDouble(),
      lon: json['lon'].toDouble(),
      ele: json['ele'].toDouble(),
      time: json['time'] != null ? DateTime.parse(json['time']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lon': lon,
      'ele': ele,
      'time': time?.toIso8601String(),
    };
  }

  @override
  String toString() => 'GpxPoint(lat: $lat, lon: $lon, ele: $ele, time: $time)';
}

/// Represents a slope between two consecutive points
class GpxSegment {
  final GpxPoint start;
  final GpxPoint end;
  final double slope; // in percent (%)

  GpxSegment({required this.start, required this.end, required this.slope});

  factory GpxSegment.fromJson(Map<String, dynamic> json) {
    return GpxSegment(
      start: GpxPoint.fromJson(json['start']),
      end: GpxPoint.fromJson(json['end']),
      slope: json['slope'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'start': start.toJson(), 'end': end.toJson(), 'slope': slope};
  }

  @override
  String toString() =>
      'Segment from ${start.lat},${start.lon} to ${end.lat},${end.lon} -> slope: ${slope.toStringAsFixed(2)}%';
}

/// Service to load GPX and compute slopes
class GpxService {
  /// Load GPX from a local file path
  Future<List<GpxPoint>> loadGpx(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('GPX file not found at $filePath');
    }

    final xmlStr = await file.readAsString();
    return parseGpxContent(xmlStr);
  }

  /// Load GPX from file content (for file picker results)
  Future<List<GpxPoint>> loadGpxFromBytes(List<int> bytes) async {
    final xmlStr = String.fromCharCodes(bytes);
    return parseGpxContent(xmlStr);
  }

  /// Parse GPX content from XML string
  List<GpxPoint> parseGpxContent(String xmlContent) {
    final doc = XmlDocument.parse(xmlContent);
    final trackPoints = <GpxPoint>[];

    // Iterate through all <trkpt> elements
    for (final trkpt in doc.findAllElements('trkpt')) {
      final latStr = trkpt.getAttribute('lat');
      final lonStr = trkpt.getAttribute('lon');
      final eleEl = trkpt.findElements('ele').isEmpty
          ? null
          : trkpt.findElements('ele').first;
      final timeEl = trkpt.findElements('time').isEmpty
          ? null
          : trkpt.findElements('time').first;

      if (latStr == null || lonStr == null || eleEl == null) continue;

      final lat = double.parse(latStr);
      final lon = double.parse(lonStr);
      final ele = double.parse(eleEl.innerText);
      final time = timeEl != null
          ? DateTime.tryParse(timeEl.innerText)?.toUtc()
          : null;

      trackPoints.add(GpxPoint(lat: lat, lon: lon, ele: ele, time: time));
    }

    if (trackPoints.isEmpty) {
      throw Exception('No track points found in GPX file.');
    }

    return trackPoints;
  }

  /// Apply median smoothing to elevation data
  List<GpxPoint> smoothElevation(List<GpxPoint> points, {int windowSize = 5}) {
    if (points.length <= windowSize) return points;

    final smoothedPoints = <GpxPoint>[];
    final halfWindow = windowSize ~/ 2;

    for (var i = 0; i < points.length; i++) {
      final start = (i - halfWindow).clamp(0, points.length - 1);
      final end = (i + halfWindow + 1).clamp(0, points.length);

      // Extract elevations in the window
      final elevations = <double>[];
      for (var j = start; j < end; j++) {
        elevations.add(points[j].ele);
      }

      // Calculate median
      elevations.sort();
      final medianEle = elevations.length % 2 == 0
          ? (elevations[elevations.length ~/ 2 - 1] +
                    elevations[elevations.length ~/ 2]) /
                2
          : elevations[elevations.length ~/ 2];

      // Create new point with smoothed elevation
      smoothedPoints.add(
        GpxPoint(
          lat: points[i].lat,
          lon: points[i].lon,
          ele: medianEle,
          time: points[i].time,
        ),
      );
    }

    return smoothedPoints;
  }

  /// Apply iterative median smoothing until max slope is below threshold
  List<GpxPoint> smoothElevationUntilMaxSlope(
    List<GpxPoint> points, {
    double maxSlopePercent = 25.0,
    int windowSize = 5,
    int maxIterations = 10,
  }) {
    if (points.length <= windowSize) return points;

    var currentPoints = points;
    var iteration = 0;

    while (iteration < maxIterations) {
      // Apply one pass of median smoothing
      currentPoints = smoothElevation(currentPoints, windowSize: windowSize);

      // Calculate current max slope
      var maxSlope = 0.0;
      for (var i = 1; i < currentPoints.length; i++) {
        final start = currentPoints[i - 1];
        final end = currentPoints[i];
        final distance = haversine(start.lat, start.lon, end.lat, end.lon);
        final elevDiff = end.ele - start.ele;
        final slope = distance > 1e-3 ? (elevDiff / distance) * 100 : 0.0;
        maxSlope = max(maxSlope, slope.abs());
      }

      iteration++;

      // If max slope is within threshold, we're done
      if (maxSlope <= maxSlopePercent) {
        break;
      }
    }

    return currentPoints;
  }

  /// Compute slopes between consecutive points
  List<GpxSegment> computeSlopes(
    List<GpxPoint> points, {
    bool smoothElevations = true,
    int smoothingWindow = 5,
    double maxSlopePercent = 25.0,
    bool useIterativeSmoothing = true,
    bool disableProcessing = false,
  }) {
    // If processing is disabled, use raw track points directly
    final processedPoints = disableProcessing
        ? points
        : (smoothElevations
              ? (useIterativeSmoothing
                    ? smoothElevationUntilMaxSlope(
                        points,
                        maxSlopePercent: maxSlopePercent,
                        windowSize: smoothingWindow,
                      )
                    : smoothElevation(points, windowSize: smoothingWindow))
              : points);

    final segments = <GpxSegment>[];
    for (var i = 1; i < processedPoints.length; i++) {
      final start = processedPoints[i - 1];
      final end = processedPoints[i];
      final distance = haversine(start.lat, start.lon, end.lat, end.lon);
      final elevDiff = end.ele - start.ele;
      final slope = distance > 1e-3
          ? (elevDiff / distance) * 100
          : 0.0; // avoid division by zero
      segments.add(GpxSegment(start: start, end: end, slope: slope));
    }
    return segments;
  }

  /// Haversine formula to compute distance between two lat/lon points in meters
  double haversine(double lat1, double lon1, double lat2, double lon2) {
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
}
