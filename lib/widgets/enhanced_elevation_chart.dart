import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/workout_models.dart';

class EnhancedElevationChart extends StatefulWidget {
  final GpxWorkout? gpxWorkout;
  final double? currentDistance;
  final double height;
  final bool isImmersive;

  const EnhancedElevationChart({
    super.key,
    this.gpxWorkout,
    this.currentDistance,
    this.height = 200,
    this.isImmersive = false,
  });

  @override
  State<EnhancedElevationChart> createState() => _EnhancedElevationChartState();
}

class _EnhancedElevationChartState extends State<EnhancedElevationChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gpxWorkout == null) {
      return _buildPlaceholder();
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return _buildChart();
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: widget.isImmersive
            ? Colors.black.withValues(alpha: 0.3)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isImmersive
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.terrain,
              size: 48,
              color: widget.isImmersive
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              'Load GPX Route',
              style: TextStyle(
                color: widget.isImmersive
                    ? Colors.white.withValues(alpha: 0.7)
                    : Colors.grey[600],
                fontSize: 16,
              ),
            ),
            Text(
              'for elevation profile',
              style: TextStyle(
                color: widget.isImmersive
                    ? Colors.white.withValues(alpha: 0.5)
                    : Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final gpxWorkout = widget.gpxWorkout!;
    final elevationProfile = gpxWorkout.getElevationProfile();

    if (elevationProfile.isEmpty) {
      return _buildPlaceholder();
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: widget.isImmersive
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.6),
                ],
              )
            : null,
        color: widget.isImmersive ? null : Colors.white,
        boxShadow: [
          if (!widget.isImmersive)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: _getElevationInterval(gpxWorkout),
            verticalInterval: _getDistanceInterval(gpxWorkout),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: widget.isImmersive
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.3),
                strokeWidth: 0.5,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: widget.isImmersive
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.3),
                strokeWidth: 0.5,
              );
            },
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              axisNameWidget: Text(
                'km',
                style: TextStyle(
                  color: widget.isImmersive
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.grey[600],
                  fontSize: 10,
                ),
              ),
              axisNameSize: 16,
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: _getDistanceInterval(gpxWorkout),
                getTitlesWidget: (value, meta) {
                  return Text(
                    (value / 1000).round().toString(),
                    style: TextStyle(
                      color: widget.isImmersive
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.grey[600],
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
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
            border: Border.all(
              color: widget.isImmersive
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.5),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.round()} m',
                    TextStyle(
                      color: widget.isImmersive ? Colors.yellow : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          minX: 0,
          maxX: gpxWorkout.totalDistance,
          minY: gpxWorkout.minElevation - 10,
          maxY: gpxWorkout.maxElevation + 10,
          lineBarsData: [
            // Main elevation line with animation
            LineChartBarData(
              spots: elevationProfile
                  .take((elevationProfile.length * _animation.value).round())
                  .map((point) => FlSpot(point.distance, point.elevation))
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: _getElevationColor(gpxWorkout),
              barWidth: widget.isImmersive ? 3 : 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _getElevationColor(gpxWorkout).withValues(alpha: 0.4),
                    _getElevationColor(gpxWorkout).withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

            // Current position indicator
            if (widget.currentDistance != null && _animation.isCompleted)
              _buildCurrentPositionIndicator(gpxWorkout),
          ],
          extraLinesData: ExtraLinesData(
            verticalLines:
                widget.currentDistance != null && _animation.isCompleted
                ? [
                    VerticalLine(
                      x: widget.currentDistance!,
                      color: widget.isImmersive ? Colors.yellow : Colors.red,
                      strokeWidth: 2,
                      dashArray: [8, 4],
                      label: VerticalLineLabel(
                        show: false,
                        labelResolver: (line) => 'YOU ARE HERE',
                        style: TextStyle(
                          color: widget.isImmersive
                              ? Colors.yellow
                              : Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ]
                : [],
          ),
        ),
      ),
    );
  }

  LineChartBarData _buildCurrentPositionIndicator(GpxWorkout gpxWorkout) {
    final currentElevation = _getCurrentElevation(gpxWorkout);

    return LineChartBarData(
      spots: [FlSpot(widget.currentDistance!, currentElevation)],
      isCurved: false,
      color: Colors.transparent,
      barWidth: 0,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) {
          return FlDotCirclePainter(
            radius: widget.isImmersive ? 8 : 6,
            color: widget.isImmersive ? Colors.yellow : Colors.red,
            strokeWidth: 2,
            strokeColor: widget.isImmersive ? Colors.white : Colors.white,
          );
        },
      ),
    );
  }

  double _getCurrentElevation(GpxWorkout gpxWorkout) {
    if (widget.currentDistance == null) return 0;

    final elevationProfile = gpxWorkout.getElevationProfile();
    if (elevationProfile.isEmpty) return 0;

    // Find the closest elevation point to current distance
    double minDiff = double.infinity;
    double closestElevation = elevationProfile.first.elevation;

    for (final point in elevationProfile) {
      final diff = (point.distance - widget.currentDistance!).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestElevation = point.elevation;
      }
    }

    return closestElevation;
  }

  Color _getElevationColor(GpxWorkout gpxWorkout) {
    final elevationRange = gpxWorkout.maxElevation - gpxWorkout.minElevation;

    if (widget.isImmersive) {
      // More vivid colors for immersive mode
      if (elevationRange > 1000) return Colors.purple; // Mountain route
      if (elevationRange > 500) return Colors.orange; // Hilly route
      if (elevationRange > 100) return Colors.green; // Rolling hills
      return Colors.cyan; // Flat route
    } else {
      // Standard colors for normal mode
      if (elevationRange > 1000) return Colors.red; // Mountain route
      if (elevationRange > 500) return Colors.orange; // Hilly route
      if (elevationRange > 100) return Colors.green; // Rolling hills
      return Colors.blue; // Flat route
    }
  }

  double _getDistanceInterval(GpxWorkout gpxWorkout) {
    if (gpxWorkout.totalDistance > 100000) {
      return 20000; // Every 20km for long routes
    }
    if (gpxWorkout.totalDistance > 50000) return 10000; // Every 10km
    if (gpxWorkout.totalDistance > 20000) return 5000; // Every 5km
    if (gpxWorkout.totalDistance > 10000) return 2000; // Every 2km
    return 1000; // Every 1km for short routes
  }

  double _getElevationInterval(GpxWorkout gpxWorkout) {
    final elevationRange = gpxWorkout.maxElevation - gpxWorkout.minElevation;
    if (elevationRange > 1000) return 200; // Every 200m for mountain routes
    if (elevationRange > 500) return 100; // Every 100m
    if (elevationRange > 200) return 50; // Every 50m
    if (elevationRange > 100) return 25; // Every 25m
    return 10; // Every 10m for flat routes
  }
}

class ImmersiveRouteStats extends StatelessWidget {
  final GpxWorkout gpxWorkout;
  final double? currentDistance;

  const ImmersiveRouteStats({
    super.key,
    required this.gpxWorkout,
    this.currentDistance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: 0.4),
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ROUTE OVERVIEW',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white.withValues(alpha: 0.8),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                'Distance',
                (gpxWorkout.totalDistance / 1000).toStringAsFixed(1),
                'km',
                Icons.straighten,
              ),
              _buildStatItem(
                'Climb',
                '${gpxWorkout.totalElevationGain.toInt()}',
                'm',
                Icons.trending_up,
              ),
              _buildStatItem(
                'Max Alt.',
                '${gpxWorkout.maxElevation.toInt()}',
                'm',
                Icons.landscape,
              ),
              if (currentDistance != null)
                _buildStatItem(
                  'Progress',
                  ((currentDistance! / gpxWorkout.totalDistance) * 100)
                      .toStringAsFixed(0),
                  '%',
                  Icons.location_on,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    String unit,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
