import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_theme.dart';
import '../services/trainer_service.dart';
import 'animated_transitions.dart';

class DataChart extends StatefulWidget {
  const DataChart({super.key});

  @override
  State<DataChart> createState() => _DataChartState();
}

class _DataChartState extends State<DataChart> with TickerProviderStateMixin {
  String _selectedMetric = 'Power';
  final List<String> _metrics = ['Power', 'Speed'];
  late AnimationController _chartAnimationController;
  late Animation<double> _chartAnimation;

  @override
  void initState() {
    super.initState();
    _chartAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _chartAnimation = CurvedAnimation(
      parent: _chartAnimationController,
      curve: Curves.easeInOut,
    );
    _chartAnimationController.forward();
  }

  @override
  void dispose() {
    _chartAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedDataCard(
      child: Card(
        margin: const EdgeInsets.all(16.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Performance Chart',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  DropdownButton<String>(
                    value: _selectedMetric,
                    items: _metrics.map((metric) {
                      return DropdownMenuItem(
                        value: metric,
                        child: Text(metric),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedMetric = value ?? 'Power';
                      });
                      // Restart animation when metric changes
                      _chartAnimationController.reset();
                      _chartAnimationController.forward();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer<TrainerService>(
                  builder: (context, trainerService, child) {
                    return AnimatedBuilder(
                      animation: _chartAnimation,
                      builder: (context, child) {
                        return _buildChart(trainerService);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(TrainerService trainerService) {
    final dataHistory = trainerService.dataHistory;

    if (dataHistory.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final spots = <FlSpot>[];
    final now = DateTime.now();

    final animatedDataLength = (dataHistory.length * _chartAnimation.value)
        .round();

    for (int i = 0; i < animatedDataLength; i++) {
      final data = dataHistory[i];
      final secondsAgo = now.difference(data.timestamp).inSeconds.toDouble();

      double value;
      switch (_selectedMetric) {
        case 'Speed':
          value = data.speed;
          break;
        default: // Power
          value = data.power;
      }

      spots.add(FlSpot(-secondsAgo, value));
    }

    if (spots.isEmpty) {
      return const Center(child: Text('No data available for selected metric'));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: _getHorizontalInterval(),
          verticalInterval: 30,
          getDrawingHorizontalLine: (value) {
            return const FlLine(
              color: AppColors.outlineVariant,
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return const FlLine(
              color: AppColors.outlineVariant,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 60,
              getTitlesWidget: (value, meta) {
                final minutes = (-value / 60).round();
                return Text(
                  '${minutes}m',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: _getHorizontalInterval(),
              reservedSize: 42,
              getTitlesWidget: (value, meta) {
                return Text(
                  _formatValue(value),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.outline),
        ),
        minX: spots.isNotEmpty ? spots.first.x : -300,
        maxX: 0,
        minY: _getMinY(spots),
        maxY: _getMaxY(spots),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: _getLineColor(),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: _getLineColor().withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  double _getHorizontalInterval() {
    switch (_selectedMetric) {
      case 'Speed':
        return 5.0;
      default: // Power
        return 50.0;
    }
  }

  double _getMinY(List<FlSpot> spots) {
    if (spots.isEmpty) return 0;
    final minValue = spots
        .map((spot) => spot.y)
        .reduce((a, b) => a < b ? a : b);
    return (minValue - _getHorizontalInterval()).clamp(0, double.infinity);
  }

  double _getMaxY(List<FlSpot> spots) {
    if (spots.isEmpty) return 100;
    final maxValue = spots
        .map((spot) => spot.y)
        .reduce((a, b) => a > b ? a : b);
    return maxValue + _getHorizontalInterval();
  }

  Color _getLineColor() {
    switch (_selectedMetric) {
      case 'Speed':
        return AppColors.successLight;
      default: // Power
        return AppColors.power;
    }
  }

  String _formatValue(double value) {
    return value.toStringAsFixed(0);
  }
}
