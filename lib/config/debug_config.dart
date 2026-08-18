class DebugConfig {
  /// Enable debug mode to bypass trainer connection requirements
  /// This allows testing workout screens without a physical trainer connected
  static const bool enableDebugMode = false;

  /// Whether to simulate trainer data when in debug mode
  static const bool simulateTrainerData = false;

  /// Simulated power values (watts) for debug mode
  static const double simulatedPower = 150.0;

  /// Simulated speed values (km/h) for debug mode
  static const double simulatedSpeed = 25.0;

  /// Simulated cadence values (rpm) for debug mode
  static const double simulatedCadence = 85.0;

  /// Simulated heart rate (bpm) for debug mode
  static const int simulatedHeartRate = 140;
}
