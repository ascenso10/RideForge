import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_theme.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/workout_models.dart';
import 'package:fl_chart/fl_chart.dart';

class WorkoutHistoryScreen extends StatefulWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  State<WorkoutHistoryScreen> createState() => _WorkoutHistoryScreenState();
}

class _WorkoutHistoryScreenState extends State<WorkoutHistoryScreen> {
  List<WorkoutSummary> _workoutHistory = [];
  List<FileSystemEntity> _fitFiles = [];
  List<FtpEntry> _ftpHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWorkoutHistory();
    _loadFitFiles();
    _loadFtpHistory();
  }

  Future<void> _loadWorkoutHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyStrings = prefs.getStringList('workout_history') ?? [];

      final history = <WorkoutSummary>[];
      for (final historyString in historyStrings) {
        try {
          final json = jsonDecode(historyString);
          history.add(WorkoutSummary.fromJson(json));
        } catch (e) {
          debugPrint('Error loading workout from history: $e');
        }
      }

      // Sort by date, most recent first
      history.sort((a, b) => b.startTime.compareTo(a.startTime));

      setState(() {
        _workoutHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading workout history: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFtpHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ftpStrings = prefs.getStringList('ftp_history') ?? [];
      final entries = ftpStrings
          .map((s) => FtpEntry.fromJson(jsonDecode(s)))
          .toList();
      entries.sort((a, b) => a.date.compareTo(b.date));
      setState(() => _ftpHistory = entries);
    } catch (e) {
      debugPrint('Error loading FTP history: $e');
    }
  }

  Future<void> _loadFitFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fitDirectory = Directory('${directory.path}/fit_files');

      if (!await fitDirectory.exists()) return;

      final files = fitDirectory
          .listSync()
          .where((file) => file.path.endsWith('.fit'))
          .toList();
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

      setState(() {
        _fitFiles = files;
      });
    } catch (e) {
      debugPrint('Error loading FIT files: $e');
    }
  }

  Future<void> _deleteWorkout(WorkoutSummary workout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyStrings = prefs.getStringList('workout_history') ?? [];

      // Remove the workout from history
      historyStrings.removeWhere((historyString) {
        try {
          final json = jsonDecode(historyString);
          final summary = WorkoutSummary.fromJson(json);
          return summary.startTime == workout.startTime &&
              summary.workoutName == workout.workoutName;
        } catch (e) {
          return false;
        }
      });

      await prefs.setStringList('workout_history', historyStrings);

      setState(() {
        _workoutHistory.remove(workout);
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Workout deleted')));
      }
    } catch (e) {
      debugPrint('Error deleting workout: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error deleting workout')));
      }
    }
  }

  Future<void> _openFitFile(FileSystemEntity file) async {
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sharing file: $e')));
      }
    }
  }

  FileSystemEntity? _findFitFileForWorkout(WorkoutSummary workout) {
    final sanitized = workout.workoutName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(' ', '_')
        .trim();
    final dt = workout.startTime;
    final dateStr =
        '${dt.year.toString().padLeft(4, '0')}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}_'
        '${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}'
        '${dt.second.toString().padLeft(2, '0')}';
    final expectedName = '${sanitized}_$dateStr.fit';
    try {
      return _fitFiles.firstWhere(
        (f) => f.uri.pathSegments.last == expectedName,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (isLandscape) {
      return Scaffold(body: _buildWorkoutHistoryTab());
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workout History'),
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Workouts', icon: Icon(Icons.fitness_center)),
              Tab(text: 'FTP', icon: Icon(Icons.bolt)),
            ],
          ),
        ),
        body: TabBarView(children: [_buildWorkoutHistoryTab(), _buildFtpTab()]),
      ),
    );
  }

  Widget _buildWorkoutHistoryTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_workoutHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No workout history yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Complete a workout to see it here',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _workoutHistory.length,
      itemBuilder: (context, index) {
        final workout = _workoutHistory[index];
        return _buildWorkoutCard(workout);
      },
    );
  }

  Widget _buildWorkoutCard(WorkoutSummary workout) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          workout.workoutName.contains('GPX')
              ? Icons.terrain
              : Icons.fitness_center,
          color: AppColors.primary,
        ),
        title: Text(
          workout.workoutName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatDateTime(workout.startTime),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.timer, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  _formatDuration(workout.totalDuration),
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Icon(Icons.bolt, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '${workout.avgPower.round()}W avg',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _showDeleteConfirmation(workout),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWorkoutStats(workout),
                const SizedBox(height: 16),
                if (workout.dataPoints.isNotEmpty) ...[
                  const Text(
                    'Power (watts)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: _buildPowerChart(workout.dataPoints),
                  ),
                  if (workout.dataPoints.any((d) => d.heartRate > 0)) ...[
                    const SizedBox(height: 12),
                    _buildHrChartHeader(),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 160,
                      child: _buildHrChart(workout.dataPoints),
                    ),
                  ],
                ],
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final fitFile = _findFitFileForWorkout(workout);
                    if (fitFile == null) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Download FIT'),
                        onPressed: () => _openFitFile(fitFile),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutStats(WorkoutSummary workout) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatColumn('Avg Power', '${workout.avgPower.round()}W'),
            _buildStatColumn('Max Power', '${workout.maxPower.round()}W'),
          ],
        ),
        if (workout.avgHeartRate > 0) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatColumn(
                'Avg HR',
                '${workout.avgHeartRate} bpm',
                color: AppColors.heartRate,
              ),
              _buildStatColumn(
                'Max HR',
                '${workout.maxHeartRate} bpm',
                color: AppColors.heartRate,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStatColumn(
    String label,
    String value, {
    Color color = AppColors.power,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildFtpTab() {
    if (_ftpHistory.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bolt, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No FTP tests yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Complete an FTP Ramp Test to track your progress',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final latestFtp = _ftpHistory.last.ftp;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_ftpHistory.length > 1) ...[
          _buildFtpChart(),
          const SizedBox(height: 24),
        ],
        _buildPowerZonesCard(latestFtp),
        const SizedBox(height: 24),
        ..._ftpHistory.reversed.toList().asMap().entries.map((e) {
          final entry = e.value;
          // delta vs the previous chronological entry (next in reversed list)
          final chronoIndex = _ftpHistory.length - 1 - e.key;
          final prev = chronoIndex > 0 ? _ftpHistory[chronoIndex - 1] : null;
          final delta = prev != null ? entry.ftp - prev.ftp : null;
          return _buildFtpEntryCard(entry, delta);
        }),
      ],
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Power Zones',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '$ftp W FTP',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...zones.map((z) {
            final (num, name, color, watts, pct) = z;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
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
                          ),
                        ),
                        Text(
                          pct,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
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
    );
  }

  Widget _buildFtpChart() {
    final spots = _ftpHistory
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.ftp.toDouble()))
        .toList();

    final minFtp = _ftpHistory
        .map((e) => e.ftp)
        .reduce((a, b) => a < b ? a : b);
    final maxFtp = _ftpHistory
        .map((e) => e.ftp)
        .reduce((a, b) => a > b ? a : b);
    final yPadding = ((maxFtp - minFtp) * 0.2).clamp(10, 50).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FTP Progress',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minY: minFtp - yPadding,
                maxY: maxFtp + yPadding,
                gridData: FlGridData(show: true),
                borderData: FlBorderData(show: true),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        if (value == meta.min || value == meta.max) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          '${value.toInt()}W',
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= _ftpHistory.length) {
                          return const SizedBox.shrink();
                        }
                        if (value == meta.min || value == meta.max) {
                          return const SizedBox.shrink();
                        }
                        final d = _ftpHistory[index].date;
                        return Text(
                          '${d.day}/${d.month}',
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.power,
                    barWidth: 2,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.power.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFtpEntryCard(FtpEntry entry, int? delta) {
    Color deltaColor = Colors.grey;
    String deltaText = '';
    if (delta != null) {
      deltaColor = delta >= 0 ? Colors.green : Colors.red;
      deltaText = delta >= 0 ? '+${delta}W' : '${delta}W';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.bolt, color: AppColors.power),
        title: Text(
          '${entry.ftp} W',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(_formatDateTime(entry.date)),
        trailing: delta != null
            ? Text(
                deltaText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: deltaColor,
                ),
              )
            : null,
      ),
    );
  }

  void _showDeleteConfirmation(WorkoutSummary workout) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workout'),
        content: Text(
          'Are you sure you want to delete "${workout.workoutName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteWorkout(workout);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildHrChartHeader() {
    return Row(
      children: [
        Icon(Icons.favorite, size: 14, color: AppColors.heartRate),
        const SizedBox(width: 4),
        Text(
          'Heart Rate (bpm)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.heartRate,
          ),
        ),
      ],
    );
  }

  AxisTitles _leftPowerAxis() {
    const reserved = 36.0;
    return AxisTitles(
      axisNameSize: 16,
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: reserved,
        getTitlesWidget: (value, meta) {
          if (value == meta.min || value == meta.max) {
            return const SizedBox.shrink();
          }
          return SizedBox(
            width: reserved,
            child: Text(
              '${value.toInt()}',
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.right,
            ),
          );
        },
      ),
    );
  }

  AxisTitles _leftHrAxis() {
    const reserved = 40.0;
    return AxisTitles(
      axisNameSize: 16,
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: reserved,
        getTitlesWidget: (value, meta) {
          if (value == meta.min || value == meta.max) {
            return const SizedBox.shrink();
          }
          return SizedBox(
            width: reserved,
            child: Text(
              '${value.toInt()}',
              style: const TextStyle(
                fontSize: 10,
                color: Color.fromARGB(255, 0, 0, 0),
              ),
              textAlign: TextAlign.right,
            ),
          );
        },
      ),
    );
  }

  /// Returns a tick interval (in x-axis units) that keeps labels from crowding,
  /// targeting roughly 4–5 visible ticks across the chart.
  double _xTickInterval(int sampleCount, int totalSeconds) {
    if (sampleCount <= 1 || totalSeconds <= 0) return 1;
    final totalMinutes = totalSeconds / 60.0;
    final minuteStep = totalMinutes <= 10
        ? 1
        : totalMinutes <= 30
        ? 5
        : totalMinutes <= 90
        ? 10
        : 15;
    // Convert minute step → sample-index step
    return (sampleCount - 1) / totalMinutes * minuteStep;
  }

  AxisTitles _timeBottomAxis(int sampleCount, int totalSeconds) {
    final interval = _xTickInterval(sampleCount, totalSeconds);
    return AxisTitles(
      axisNameWidget: const Text(
        'Time (min)',
        style: TextStyle(fontSize: 10, color: Colors.grey),
      ),
      axisNameSize: 16,
      sideTitles: SideTitles(
        showTitles: true,
        interval: interval,
        reservedSize: 22,
        getTitlesWidget: (value, meta) {
          // Suppress boundary labels — they clip against the chart edge
          if (value == meta.min || value == meta.max) {
            return const SizedBox.shrink();
          }
          final mins = sampleCount > 1 && totalSeconds > 0
              ? (value / (sampleCount - 1) * totalSeconds / 60).round()
              : 0;
          return Text('$mins', style: const TextStyle(fontSize: 10));
        },
      ),
    );
  }

  Widget _buildPowerChart(List<WorkoutDataPoint> dataPoints) {
    if (dataPoints.isEmpty) return const SizedBox();

    final sampledData = dataPoints.length > 100
        ? dataPoints
              .asMap()
              .entries
              .where((e) => e.key % (dataPoints.length ~/ 100) == 0)
              .map((e) => e.value)
              .toList()
        : dataPoints;

    final spots = sampledData
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.power))
        .toList();

    final totalSeconds = dataPoints.isNotEmpty
        ? dataPoints.last.timestamp
              .difference(dataPoints.first.timestamp)
              .inSeconds
        : 0;

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: _leftPowerAxis(),
          bottomTitles: _timeBottomAxis(sampledData.length, totalSeconds),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.power,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.power.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHrChart(List<WorkoutDataPoint> dataPoints) {
    final sampledData = dataPoints.length > 100
        ? dataPoints
              .asMap()
              .entries
              .where((e) => e.key % (dataPoints.length ~/ 100) == 0)
              .map((e) => e.value)
              .toList()
        : dataPoints;

    final spots = sampledData
        .asMap()
        .entries
        .where((e) => e.value.heartRate > 0)
        .map((e) => FlSpot(e.key.toDouble(), e.value.heartRate.toDouble()))
        .toList();

    if (spots.isEmpty) return const SizedBox();

    final totalSeconds = dataPoints.isNotEmpty
        ? dataPoints.last.timestamp
              .difference(dataPoints.first.timestamp)
              .inSeconds
        : 0;

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true),
        titlesData: FlTitlesData(
          leftTitles: _leftHrAxis(),
          bottomTitles: _timeBottomAxis(sampledData.length, totalSeconds),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: true),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.heartRate,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.heartRate.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else {
      return '${minutes}m ${seconds}s';
    }
  }
}
