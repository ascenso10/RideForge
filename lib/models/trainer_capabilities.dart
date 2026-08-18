import 'package:flutter/material.dart';

class TrainerCapabilities {
  final double maxGradient;
  final double minGradient;
  final int maxPower;
  final int maxResistance;
  final GradientHandlingMode gradientMode;
  final GradientCompensationMode compensationMode;
  final double compensationFactor;

  const TrainerCapabilities({
    required this.maxGradient,
    required this.minGradient,
    required this.maxPower,
    required this.maxResistance,
    this.gradientMode = GradientHandlingMode.clamp,
    this.compensationMode = GradientCompensationMode.none,
    this.compensationFactor = 1.0,
  });

  factory TrainerCapabilities.fromJson(Map<String, dynamic> json) {
    return TrainerCapabilities(
      maxGradient: json['maxGradient']?.toDouble() ?? 6.0,
      minGradient: json['minGradient']?.toDouble() ?? 0.0,
      maxPower: json['maxPower']?.toInt() ?? 600,
      maxResistance: json['maxResistance']?.toInt() ?? 100,
      gradientMode: GradientHandlingMode.values.firstWhere(
        (mode) => mode.name == json['gradientMode'],
        orElse: () => GradientHandlingMode.clamp,
      ),
      compensationMode: GradientCompensationMode.values.firstWhere(
        (mode) => mode.name == json['compensationMode'],
        orElse: () => GradientCompensationMode.none,
      ),
      compensationFactor: json['compensationFactor']?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'maxGradient': maxGradient,
      'minGradient': minGradient,
      'maxPower': maxPower,
      'maxResistance': maxResistance,
      'gradientMode': gradientMode.name,
      'compensationMode': compensationMode.name,
      'compensationFactor': compensationFactor,
    };
  }

  // Default generic trainer capabilities (used as fallback when no trainer connected)
  static const TrainerCapabilities generic = TrainerCapabilities(
    maxGradient: 6.0,
    minGradient: 0.0,
    maxPower: 600,
    maxResistance: 100,
  );

  /// Apply trainer limits to a gradient value
  double constrainGradient(double originalGradient) {
    switch (gradientMode) {
      case GradientHandlingMode.clamp:
        final result = originalGradient.clamp(minGradient, maxGradient);
        if (originalGradient != result) {
          debugPrint(
            'Gradient clamped: $originalGradient -> $result (limits: $minGradient to $maxGradient)',
          );
        }
        return result;

      case GradientHandlingMode.scale:
        // Scale down gradients proportionally if they exceed limits
        if (originalGradient > maxGradient) {
          return maxGradient;
        } else if (originalGradient < minGradient) {
          return minGradient;
        }
        return originalGradient;

      case GradientHandlingMode.warn:
        // Just warn but don't modify (handled at UI level)
        return originalGradient;
    }
  }

  /// Calculate gradient compensation when gradient exceeds trainer limits
  CompensationResult calculateCompensation(double originalGradient) {
    final clampedGradient = constrainGradient(originalGradient);
    final lostGradient = originalGradient - clampedGradient;

    // No compensation needed if no gradient was lost or compensation is disabled
    if (lostGradient.abs() <= 0.01 ||
        compensationMode == GradientCompensationMode.none) {
      return CompensationResult(adjustedGradient: clampedGradient);
    }

    // Apply compensation factor to the lost gradient
    final compensatedLoss = lostGradient * compensationFactor;

    switch (compensationMode) {
      case GradientCompensationMode.none:
        return CompensationResult(adjustedGradient: clampedGradient);

      case GradientCompensationMode.rollingResistance:
        // Convert lost gradient to rolling resistance coefficient
        // Formula: Each 1% gradient ≈ 0.001 rolling resistance coefficient
        final rollingResistance = compensatedLoss * 0.001;
        debugPrint(
          'Gradient compensation: ${originalGradient.toStringAsFixed(1)}% -> ${clampedGradient.toStringAsFixed(1)}% + ${rollingResistance.toStringAsFixed(4)} rolling resistance',
        );
        return CompensationResult(
          adjustedGradient: clampedGradient,
          rollingResistance: rollingResistance,
        );

      case GradientCompensationMode.directResistance:
        // Convert lost gradient to additional resistance percentage
        // Formula: Each 1% gradient ≈ 15% additional resistance
        final additionalResistance = (compensatedLoss * 15.0).clamp(0.0, 100.0);
        debugPrint(
          'Gradient compensation: ${originalGradient.toStringAsFixed(1)}% -> ${clampedGradient.toStringAsFixed(1)}% + ${additionalResistance.toStringAsFixed(1)}% resistance',
        );
        return CompensationResult(
          adjustedGradient: clampedGradient,
          additionalResistance: additionalResistance,
        );
    }
  }

  /// Check if gradient exceeds trainer capabilities
  bool isGradientSupported(double gradient) {
    return gradient >= minGradient && gradient <= maxGradient;
  }

  /// Get percentage of gradients that will be capped for a route
  RouteCompatibility analyzeRoute(List<double> gradients) {
    if (gradients.isEmpty) {
      return RouteCompatibility(
        compatibilityScore: 1.0,
        cappedSegments: 0,
        totalSegments: 0,
        maxOriginalGradient: 0.0,
        maxTrainerGradient: maxGradient,
      );
    }

    int cappedSegments = 0;
    double maxOriginalGradient = gradients.reduce(
      (a, b) => a.abs() > b.abs() ? a : b,
    );

    for (final gradient in gradients) {
      if (!isGradientSupported(gradient)) {
        cappedSegments++;
      }
    }

    double compatibilityScore = 1.0 - (cappedSegments / gradients.length);

    return RouteCompatibility(
      compatibilityScore: compatibilityScore,
      cappedSegments: cappedSegments,
      totalSegments: gradients.length,
      maxOriginalGradient: maxOriginalGradient,
      maxTrainerGradient: maxGradient,
    );
  }
}

enum GradientHandlingMode {
  clamp, // Clamp gradients to trainer limits
  scale, // Scale gradients proportionally
  warn, // Show warnings but don't modify
}

enum GradientCompensationMode {
  none, // No compensation - just clamp gradients
  rollingResistance, // Use rolling resistance coefficient for compensation
  directResistance, // Use separate resistance commands for compensation
}

class CompensationResult {
  final double adjustedGradient; // The gradient to send to trainer (clamped)
  final double additionalResistance; // Additional resistance percentage (0-100)
  final double rollingResistance; // Rolling resistance coefficient

  const CompensationResult({
    required this.adjustedGradient,
    this.additionalResistance = 0.0,
    this.rollingResistance = 0.0,
  });

  @override
  String toString() {
    return 'CompensationResult(gradient: ${adjustedGradient.toStringAsFixed(1)}%, '
        'resistance: ${additionalResistance.toStringAsFixed(1)}%, '
        'rolling: ${rollingResistance.toStringAsFixed(4)})';
  }
}

class RouteCompatibility {
  final double compatibilityScore; // 0.0 to 1.0
  final int cappedSegments;
  final int totalSegments;
  final double maxOriginalGradient;
  final double maxTrainerGradient;

  RouteCompatibility({
    required this.compatibilityScore,
    required this.cappedSegments,
    required this.totalSegments,
    required this.maxOriginalGradient,
    required this.maxTrainerGradient,
  });

  bool get isFullySupported => cappedSegments == 0;
  bool get hasMinorLimitations => compatibilityScore >= 0.8;
  bool get hasMajorLimitations => compatibilityScore < 0.5;

  String get compatibilityLabel {
    if (isFullySupported) return 'Fully Supported';
    if (hasMinorLimitations) return 'Minor Limitations';
    if (hasMajorLimitations) return 'Major Limitations';
    return 'Moderate Limitations';
  }

  Color get compatibilityColor {
    if (isFullySupported) return const Color(0xFF4CAF50); // Green
    if (hasMinorLimitations) return const Color(0xFFFF9800); // Orange
    if (hasMajorLimitations) return const Color(0xFFF44336); // Red
    return const Color(0xFFFF5722); // Deep Orange
  }
}

extension GradientCompensationModeExtension on GradientCompensationMode {
  String get displayName {
    switch (this) {
      case GradientCompensationMode.none:
        return 'No Compensation';
      case GradientCompensationMode.rollingResistance:
        return 'Rolling Resistance';
      case GradientCompensationMode.directResistance:
        return 'Direct Resistance';
    }
  }

  String get description {
    switch (this) {
      case GradientCompensationMode.none:
        return 'Use standard gradient clamping only';
      case GradientCompensationMode.rollingResistance:
        return 'Compensate using rolling resistance coefficient (recommended)';
      case GradientCompensationMode.directResistance:
        return 'Compensate using additional trainer resistance';
    }
  }

  String get shortDescription {
    switch (this) {
      case GradientCompensationMode.none:
        return 'No extra difficulty for capped gradients';
      case GradientCompensationMode.rollingResistance:
        return 'Uses rolling resistance for authentic feel';
      case GradientCompensationMode.directResistance:
        return 'Adds trainer resistance for steep sections';
    }
  }
}
