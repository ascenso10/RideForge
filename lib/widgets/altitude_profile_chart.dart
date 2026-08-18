import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/workout_models.dart';

class AltitudeProfileChart extends StatelessWidget {
  final GpxWorkout gpxWorkout;
  final double? currentDistance; // Current position during workout
  final double height;

  const AltitudeProfileChart({
    super.key,
    required this.gpxWorkout,
    this.currentDistance,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final elevationProfile = gpxWorkout.getElevationProfile();
    if (elevationProfile.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No elevation data available')),
      );
    }

    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: _getElevationInterval(),
            verticalInterval: _getDistanceInterval(),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.withValues(alpha: 0.3),
                strokeWidth: 1,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: Colors.grey.withValues(alpha: 0.3),
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: _getDistanceInterval(),
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${(value / 1000).toStringAsFixed(1)}km',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                interval: _getElevationInterval(),
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}m',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
          ),
          minX: 0,
          maxX: gpxWorkout.totalDistance,
          minY: gpxWorkout.minElevation - 10,
          maxY: gpxWorkout.maxElevation + 10,
          lineBarsData: [
            LineChartBarData(
              spots: elevationProfile
                  .map((point) => FlSpot(point.distance, point.elevation))
                  .toList(),
              isCurved: false,
              color: _getElevationColor(),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: _getElevationColor().withValues(alpha: 0.2),
              ),
            ),
            if (currentDistance != null) _buildCurrentPositionLine(),
          ],
          extraLinesData: ExtraLinesData(
            verticalLines: currentDistance != null
                ? [
                    VerticalLine(
                      x: currentDistance!,
                      color: Colors.red,
                      strokeWidth: 2,
                      dashArray: [5, 5],
                    ),
                  ]
                : [],
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildCurrentPositionLine() {
    return LineChartBarData(
      spots: [
        FlSpot(currentDistance!, gpxWorkout.minElevation - 10),
        FlSpot(currentDistance!, gpxWorkout.maxElevation + 10),
      ],
      isCurved: false,
      color: Colors.red,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );
  }

  Color _getElevationColor() {
    // Color gradient based on elevation changes
    final elevationRange = gpxWorkout.maxElevation - gpxWorkout.minElevation;
    if (elevationRange > 1000) return Colors.red; // Mountain route
    if (elevationRange > 500) return Colors.orange; // Hilly route
    if (elevationRange > 100) return Colors.green; // Rolling hills
    return Colors.blue; // Flat route
  }

  double _getDistanceInterval() {
    if (gpxWorkout.totalDistance > 100000) {
      return 20000; // Every 20km for long routes
    }
    if (gpxWorkout.totalDistance > 50000) return 10000; // Every 10km
    if (gpxWorkout.totalDistance > 20000) return 5000; // Every 5km
    if (gpxWorkout.totalDistance > 10000) return 2000; // Every 2km
    return 1000; // Every 1km for short routes
  }

  double _getElevationInterval() {
    final elevationRange = gpxWorkout.maxElevation - gpxWorkout.minElevation;
    if (elevationRange > 1000) return 200; // Every 200m for mountain routes
    if (elevationRange > 500) return 100; // Every 100m
    if (elevationRange > 200) return 50; // Every 50m
    if (elevationRange > 100) return 25; // Every 25m
    return 10; // Every 10m for flat routes
  }
}

class ElevationStatsCard extends StatelessWidget {
  final GpxWorkout gpxWorkout;

  const ElevationStatsCard({super.key, required this.gpxWorkout});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Route Statistics',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  'Distance',
                  '${(gpxWorkout.totalDistance / 1000).toStringAsFixed(1)} km',
                  Icons.straighten,
                ),
                _buildStatColumn(
                  'Elevation Gain',
                  '${gpxWorkout.totalElevationGain.toInt()} m',
                  Icons.trending_up,
                ),
                _buildStatColumn(
                  'Max Elevation',
                  '${gpxWorkout.maxElevation.toInt()} m',
                  Icons.landscape,
                ),
                if (gpxWorkout.totalTime != null)
                  _buildStatColumn(
                    'Duration',
                    _formatDuration(gpxWorkout.totalTime!),
                    Icons.timer,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }
}
