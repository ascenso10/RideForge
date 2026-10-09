import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_theme.dart';
import '../services/workout_service.dart';

/// Lets the rider scale every power target of the running workout up or down,
/// e.g. easing off a preset on a tired day. Tap the percentage to reset.
class IntensityControl extends StatelessWidget {
  final WorkoutService workoutService;
  final bool dark;

  static const int _step = 5;

  const IntensityControl({
    super.key,
    required this.workoutService,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final percent = workoutService.intensityPercent;
    final adjusted = percent != 100;
    final labelColor = dark ? Colors.grey[400] : AppColors.onSurfaceVariant;
    final valueColor = !adjusted
        ? (dark ? Colors.white : AppColors.onSurface)
        : percent < 100
        ? AppColors.primaryLight
        : AppColors.accent;

    return Row(
      children: [
        _StepButton(
          icon: Icons.remove,
          tooltip: 'Decrease intensity $_step%',
          dark: dark,
          onPressed: percent > WorkoutService.minIntensityPercent
              ? () => _adjust(-_step)
              : null,
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: adjusted
                ? () {
                    HapticFeedback.selectionClick();
                    workoutService.setIntensity(100);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Text(
                    'INTENSITY',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    '$percent%',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                  ),
                  Text(
                    adjusted ? 'Tap to reset' : 'As planned',
                    style: GoogleFonts.inter(fontSize: 11, color: labelColor),
                  ),
                ],
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          tooltip: 'Increase intensity $_step%',
          dark: dark,
          onPressed: percent < WorkoutService.maxIntensityPercent
              ? () => _adjust(_step)
              : null,
        ),
      ],
    );
  }

  void _adjust(int delta) {
    HapticFeedback.selectionClick();
    workoutService.adjustIntensity(delta);
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool dark;
  final VoidCallback? onPressed;

  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.dark,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    // Large hit target: riders tap this mid-effort with sweaty hands.
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 28,
      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      style: dark
          ? IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
              disabledForegroundColor: Colors.white24,
            )
          : null,
      icon: Icon(icon),
    );
  }
}
