import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/workout_service.dart';

/// Shown after an FTP Ramp Test completion.
/// Presents the calculated FTP and asks whether to calibrate workout targets.
class FtpCalibrateScreen extends StatelessWidget {
  final int ftp;

  const FtpCalibrateScreen({super.key, required this.ftp});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C2416),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 32),
              _buildFtpDisplay(),
              const SizedBox(height: 24),
              _buildPowerZones(),
              const SizedBox(height: 24),
              _buildWorkoutPreview(),
              const SizedBox(height: 32),
              _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.amber.withValues(alpha: 0.15),
            border: Border.all(
              color: Colors.amber.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: const Icon(Icons.bolt, color: Colors.amber, size: 48),
        ),
        const SizedBox(height: 16),
        Text(
          'New FTP Recorded!',
          style: GoogleFonts.inter(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Do you want to calibrate your workouts to match this FTP?',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.65),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFtpDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Your FTP',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.amber.withValues(alpha: 0.85),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$ftp W',
            style: GoogleFonts.inter(
              fontSize: 56,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '75% of ${(ftp / 0.75).round()} W max power',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPowerZones() {
    final zones = [
      _PowerZone(1, 'Active Recovery', Colors.grey, 0, (ftp * 0.55).round()),
      _PowerZone(
        2,
        'Endurance',
        Colors.blue,
        (ftp * 0.56).round(),
        (ftp * 0.75).round(),
      ),
      _PowerZone(
        3,
        'Tempo',
        Colors.green,
        (ftp * 0.76).round(),
        (ftp * 0.90).round(),
      ),
      _PowerZone(
        4,
        'Threshold',
        Colors.yellow,
        (ftp * 0.91).round(),
        (ftp * 1.05).round(),
      ),
      _PowerZone(
        5,
        'VO₂ Max',
        Colors.orange,
        (ftp * 1.06).round(),
        (ftp * 1.20).round(),
      ),
      _PowerZone(
        6,
        'Anaerobic Capacity',
        Colors.deepOrange,
        (ftp * 1.21).round(),
        (ftp * 1.50).round(),
      ),
      _PowerZone(
        7,
        'Neuromuscular',
        Colors.red,
        (ftp * 1.50).round() + 1,
        null,
      ),
    ];

    final maxWatts = (ftp * 1.60).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Power Zones',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.55),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 14),
          ...zones.map((z) => _buildZoneBar(z, maxWatts)),
        ],
      ),
    );
  }

  Widget _buildZoneBar(_PowerZone z, double maxWatts) {
    final barEnd = z.maxWatts ?? (ftp * 1.65).round();
    final fraction = (barEnd / maxWatts).clamp(0.0, 1.0);
    final rangeLabel = z.maxWatts != null
        ? '${z.minWatts}–${z.maxWatts} W'
        : '>${z.minWatts} W';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: z.color.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: z.color.withValues(alpha: 0.50)),
                ),
                child: Text(
                  '${z.number}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: z.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  z.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              Text(
                rangeLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 6,
                      width: constraints.maxWidth,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                    Container(
                      height: 6,
                      width: constraints.maxWidth * fraction,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [z.color.withValues(alpha: 0.6), z.color],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutPreview() {
    final zones = [
      _ZoneRow('Recovery', ftp * 0.50, '<55%', Colors.blue),
      _ZoneRow('Steady Endurance', ftp * 0.70, '70%', Colors.green),
      _ZoneRow('Tempo', ftp * 0.80, '80%', Colors.teal),
      _ZoneRow('Sweet Spot', ftp * 0.90, '90%', Colors.orange),
      _ZoneRow('Threshold', ftp * 1.00, '100%', Colors.red),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Updated workout targets',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.55),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          ...zones.map((z) => _buildZoneRow(z)),
        ],
      ),
    );
  }

  Widget _buildZoneRow(_ZoneRow z) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: z.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              z.name,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.80),
              ),
            ),
          ),
          Text(
            '${z.watts.round()} W',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '(${z.label} FTP)',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _applyFtp(context),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text(
            'Apply to All Workouts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => _skip(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            'Skip — Keep Current Workouts',
            style: TextStyle(fontSize: 15),
          ),
        ),
      ],
    );
  }

  Future<void> _applyFtp(BuildContext context) async {
    final workoutService = context.read<WorkoutService>();
    await workoutService.applyFtpToWorkouts(ftp);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Workouts updated for FTP $ftp W'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      // Pop this screen and the completion screen to land back at workouts
      int count = 0;
      Navigator.of(context).popUntil((_) => count++ >= 2);
    }
  }

  void _skip(BuildContext context) {
    // Pop this screen and the completion screen
    int count = 0;
    Navigator.of(context).popUntil((_) => count++ >= 2);
  }
}

class _ZoneRow {
  final String name;
  final double watts;
  final String label;
  final Color color;

  const _ZoneRow(this.name, this.watts, this.label, this.color);
}

class _PowerZone {
  final int number;
  final String name;
  final Color color;
  final int minWatts;
  final int? maxWatts; // null = open-ended (Zone 7)

  const _PowerZone(
    this.number,
    this.name,
    this.color,
    this.minWatts,
    this.maxWatts,
  );
}
