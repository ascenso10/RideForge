import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/workout_models.dart';
import '../widgets/animated_transitions.dart';
import '../services/fit_file_service.dart';
import '../services/strava_service.dart';
import '../widgets/strava_upload.dart';
import '../widgets/garmin_upload.dart';
import '../config/feature_flags.dart';
import 'ftp_calibrate_screen.dart';

class WorkoutCompletionScreen extends StatefulWidget {
  final WorkoutSummary workoutSummary;

  const WorkoutCompletionScreen({super.key, required this.workoutSummary});

  @override
  State<WorkoutCompletionScreen> createState() =>
      _WorkoutCompletionScreenState();
}

class _WorkoutCompletionScreenState extends State<WorkoutCompletionScreen>
    with TickerProviderStateMixin {
  late AnimationController _celebrationController;
  late AnimationController _dataController;
  late Animation<double> _celebrationAnimation;
  late Animation<double> _dataAnimation;

  final FitFileService _fitFileService = FitFileService();
  String? _fitFilePath;
  final bool _generatingFit = false;
  int? _estimatedFtp;

  @override
  void initState() {
    super.initState();

    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _dataController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _celebrationAnimation = CurvedAnimation(
      parent: _celebrationController,
      curve: Curves.elasticOut,
    );

    _dataAnimation = CurvedAnimation(
      parent: _dataController,
      curve: Curves.easeOutCubic,
    );

    // Start animations
    _celebrationController.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      _dataController.forward();
    });

    // Save workout to history
    _saveWorkoutToHistory();

    // If this was an FTP ramp test, compute the result but do NOT save yet.
    // The user must confirm via "Set Up Workouts" — bailing early discards it.
    if (widget.workoutSummary.workoutName == 'FTP Ramp Test') {
      final ftp = (widget.workoutSummary.maxPower * 0.75).round();
      setState(() => _estimatedFtp = ftp);
    }

    // Check for existing FIT file (since WorkoutService now generates it automatically)
    _checkForFitFile();
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    _dataController.dispose();
    super.dispose();
  }

  Future<void> _checkForFitFile() async {
    try {
      // Look for the FIT file that should have been created by WorkoutService
      // We'll check for files that match our workout name and time
      final fitFiles = await _fitFileService.getSavedFitFiles();

      if (fitFiles.isNotEmpty) {
        // Find the most recent FIT file (likely ours)
        final recentFile = fitFiles.first;
        final fileStat = recentFile.statSync();
        final now = DateTime.now();
        final fileAge = now.difference(fileStat.modified).inMinutes;

        // If the file was created within the last 2 minutes, assume it's ours
        if (fileAge < 2) {
          setState(() {
            _fitFilePath = recentFile.path;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking for FIT file: $e');
    }
  }

  Future<void> _saveWorkoutToHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyStrings = prefs.getStringList('workout_history') ?? [];

      // Add the new workout to history
      historyStrings.add(jsonEncode(widget.workoutSummary.toJson()));

      // Keep only the last 100 workouts to prevent unlimited growth
      if (historyStrings.length > 100) {
        historyStrings.removeRange(0, historyStrings.length - 100);
      }

      await prefs.setStringList('workout_history', historyStrings);
    } catch (e) {
      debugPrint('Error saving workout to history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C2416),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildCelebrationHeader(),
              const SizedBox(height: 32),
              AnimatedBuilder(
                animation: _dataAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _dataAnimation.value,
                    child: Transform.translate(
                      offset: Offset(0, 50 * (1 - _dataAnimation.value)),
                      child: Column(
                        children: [
                          _buildWorkoutOverview(),
                          if (_estimatedFtp != null) ...[
                            const SizedBox(height: 24),
                            _buildFtpResultCard(_estimatedFtp!),
                            const SizedBox(height: 16),
                            _buildPowerZonesCard(_estimatedFtp!),
                          ],
                          const SizedBox(height: 24),
                          _buildPerformanceMetrics(),
                          const SizedBox(height: 24),
                          _buildPowerChart(),
                          const SizedBox(height: 24),
                          _buildIntervalSummary(),
                          const SizedBox(height: 24),
                          _buildFitFileSection(),
                          const SizedBox(height: 24),
                          _buildUploadSection(),
                          const SizedBox(height: 32),
                          _buildActionButtons(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationHeader() {
    return AnimatedBuilder(
      animation: _celebrationAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _celebrationAnimation.value,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.yellow.withValues(alpha: 0.3),
                      Colors.orange.withValues(alpha: 0.1),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.emoji_events,
                  size: 80,
                  color: Colors.yellow,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'WORKOUT COMPLETE!',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 1,
                  shadows: [
                    Shadow(
                      color: Colors.yellow.withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.workoutSummary.workoutName,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkoutOverview() {
    return AnimatedDataCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Workout Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Duration',
                    _formatDuration(widget.workoutSummary.totalDuration),
                    Icons.timer,
                  ),
                ),
                Expanded(
                  child: _buildSummaryItem(
                    'Avg Power',
                    '${widget.workoutSummary.avgPower.toStringAsFixed(0)} W',
                    Icons.flash_on,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryItem(
                    'Max Power',
                    '${widget.workoutSummary.maxPower.toStringAsFixed(0)} W',
                    Icons.trending_up,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white60),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFtpResultCard(int ftp) {
    return AnimatedDataCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.amber, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated FTP',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.amber.withValues(alpha: 0.85),
                    ),
                  ),
                  Text(
                    '$ftp W',
                    style: GoogleFonts.inter(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    '75% of ${(ftp / 0.75).round()} W max power',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerZonesCard(int ftp) {
    final zones = [
      (
        1,
        'Active Recovery',
        Colors.blueGrey,
        '< ${(ftp * 0.55).round()}W',
        '< 55%',
      ),
      (
        2,
        'Endurance',
        Colors.blue,
        '${(ftp * 0.56).round()}–${(ftp * 0.75).round()}W',
        '56–75%',
      ),
      (
        3,
        'Tempo',
        Colors.green,
        '${(ftp * 0.76).round()}–${(ftp * 0.90).round()}W',
        '76–90%',
      ),
      (
        4,
        'Threshold',
        Colors.amber,
        '${(ftp * 0.91).round()}–${(ftp * 1.05).round()}W',
        '91–105%',
      ),
      (
        5,
        'VO₂ Max',
        Colors.orange,
        '${(ftp * 1.06).round()}–${(ftp * 1.20).round()}W',
        '106–120%',
      ),
      (
        6,
        'Anaerobic',
        Colors.deepOrange,
        '${(ftp * 1.21).round()}–${(ftp * 1.50).round()}W',
        '121–150%',
      ),
      (7, 'Neuromuscular', Colors.red, '> ${(ftp * 1.50).round()}W', '> 150%'),
    ];

    return AnimatedDataCard(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Power Zones',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Based on $ftp W FTP',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            ...zones.map((z) {
              final (num, name, color, watts, pct) = z;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          'Z$num',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            pct,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      watts,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceMetrics() {
    return AnimatedDataCard(
      slideDirection: const Offset(0.3, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Performance Metrics',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCircle(
                    'Energy',
                    '${(widget.workoutSummary.totalEnergy / 1000).toStringAsFixed(1)} kJ',
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricCircle(
                    'Avg Speed',
                    '${widget.workoutSummary.avgSpeed.toStringAsFixed(1)} km/h',
                    Colors.blue,
                  ),
                ),
              ],
            ),
            if (widget.workoutSummary.avgHeartRate > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCircle(
                      'Avg HR',
                      '${widget.workoutSummary.avgHeartRate} bpm',
                      Colors.red,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCircle(
                      'Max HR',
                      '${widget.workoutSummary.maxHeartRate} bpm',
                      Colors.pink,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCircle(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerChart() {
    return AnimatedDataCard(
      slideDirection: const Offset(-0.3, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Power Profile',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 50,
                    verticalInterval: _chartXInterval(),
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.white.withValues(alpha: 0.1),
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.white.withValues(alpha: 0.1),
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
                        interval: _chartXInterval(),
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${(value / 60).toInt()}m',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 100,
                        reservedSize: 42,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}W',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _generatePowerChartData(),
                      isCurved: true,
                      color: Colors.yellow,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.yellow.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<FlSpot> _generatePowerChartData() {
    final spots = <FlSpot>[];
    final dataPoints = widget.workoutSummary.powerData;

    for (int i = 0; i < dataPoints.length; i++) {
      spots.add(FlSpot(i * 5.0, dataPoints[i].power));
    }

    return spots;
  }

  /// Returns an x-axis label interval (in seconds) that yields ~5 labels.
  double _chartXInterval() {
    final totalSeconds = widget.workoutSummary.powerData.length * 5.0;
    if (totalSeconds <= 0) return 300;
    // Pick the smallest "nice" step that gives ≤6 labels
    for (final step in [60, 120, 180, 300, 600, 900, 1200, 1800]) {
      if (totalSeconds / step <= 6) return step.toDouble();
    }
    return 1800;
  }

  Widget _buildIntervalSummary() {
    if (widget.workoutSummary.intervalSummaries.length <= 1) {
      return const SizedBox.shrink();
    }
    return AnimatedDataCard(
      slideDirection: const Offset(0, 0.3),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Interval Breakdown',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            ...widget.workoutSummary.intervalSummaries.map(_buildIntervalItem),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalItem(IntervalSummary interval) {
    Color intervalColor;
    switch (interval.type) {
      case IntervalType.warmup:
        intervalColor = Colors.green;
        break;
      case IntervalType.work:
        intervalColor = Colors.red;
        break;
      case IntervalType.rest:
        intervalColor = Colors.blue;
        break;
      case IntervalType.cooldown:
        intervalColor = Colors.orange;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: intervalColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: intervalColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: intervalColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  interval.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: intervalColor,
                  ),
                ),
                Text(
                  '${_formatDuration(interval.duration)} • Avg: ${interval.avgPower.toStringAsFixed(0)}W • Max: ${interval.maxPower.toStringAsFixed(0)}W',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFitFileSection() {
    return AnimatedDataCard(
      slideDirection: const Offset(0, 0.2),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.file_download,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 8),
                Text(
                  'Workout File',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_generatingFit) ...[
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generating FIT file...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ] else if (_fitFilePath != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FIT file ready!',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Compatible with Strava, TrainingPeaks, and other fitness apps',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _shareFitFile,
                      icon: Icon(
                        Icons.share,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Failed to generate FIT file',
                      style: TextStyle(color: Colors.red),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSection() {
    if (_fitFilePath == null) {
      return const SizedBox.shrink();
    }

    // Check if any upload features are enabled
    final showStrava = StravaService.isAvailable;
    final showGarmin = FeatureFlags.enableGarminUpload;

    if (!showStrava && !showGarmin) {
      return const SizedBox.shrink();
    }

    return AnimatedDataCard(
      slideDirection: const Offset(0, 0.2),
      child: Column(
        children: [
          // Strava Upload
          if (showStrava) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: StravaUploadWidget(
                  fitFilePath: _fitFilePath!,
                  onUploadComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Successfully uploaded to Strava!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  onUploadFailed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to upload to Strava'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          if (showStrava && showGarmin) const SizedBox(height: 16),
          // Garmin Upload
          if (showGarmin) ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: GarminUploadWidget(
                  fitFilePath: _fitFilePath!,
                  onUploadComplete: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Successfully uploaded to Garmin!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  onUploadFailed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to upload to Garmin'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleContinue() {
    if (_estimatedFtp != null) {
      _persistFtpEntry(_estimatedFtp!);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FtpCalibrateScreen(ftp: _estimatedFtp!),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _persistFtpEntry(int ftp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ftpStrings = prefs.getStringList('ftp_history') ?? [];
      ftpStrings.add(
        jsonEncode(
          FtpEntry(ftp: ftp, date: widget.workoutSummary.startTime).toJson(),
        ),
      );
      await prefs.setStringList('ftp_history', ftpStrings);
    } catch (e) {
      debugPrint('Error saving FTP entry: $e');
    }
  }

  Widget _buildActionButtons() {
    final isFtpTest = _estimatedFtp != null;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _handleContinue,
            icon: Icon(isFtpTest ? Icons.tune : Icons.check),
            label: Text(
              isFtpTest ? 'Set Up Workouts' : 'Continue',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isFtpTest ? Colors.amber : Colors.green,
              foregroundColor: isFtpTest ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (isFtpTest) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Discard result',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _shareWorkout,
          icon: const Icon(Icons.share),
          label: const Text('Share Workout'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  void _shareFitFile() async {
    if (_fitFilePath != null) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_fitFilePath!)],
          text: 'Check out my workout!',
        ),
      );
    }
  }

  void _shareWorkout() async {
    final summary = widget.workoutSummary;
    final hrLines = summary.avgHeartRate > 0
        ? '\n❤️ Avg HR: ${summary.avgHeartRate} bpm\n💓 Max HR: ${summary.maxHeartRate} bpm'
        : '';
    final text =
        '''
🚴‍♂️ Workout Complete!

${summary.workoutName}
⏱ Duration: ${_formatDuration(summary.totalDuration)}
⚡ Avg Power: ${summary.avgPower.toStringAsFixed(0)}W
📈 Max Power: ${summary.maxPower.toStringAsFixed(0)}W
🔥 Energy: ${(summary.totalEnergy / 1000).toStringAsFixed(1)}kJ$hrLines

#RideForge #Cycling #Workout
    ''';

    await SharePlus.instance.share(ShareParams(text: text));
  }

  String _formatDuration(Duration duration) {
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
