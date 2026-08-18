/// Feature flags for controlling feature availability
/// Set to true to enable, false to hide from the app
class FeatureFlags {
  // Private constructor to prevent instantiation
  FeatureFlags._();

  // ============================================
  // RELEASE CONFIGURATION
  // Change these flags before shipping
  // ============================================

  /// Enable Strava upload functionality
  static const bool enableStravaUpload = true;

  /// Enable Garmin Connect upload functionality
  static const bool enableGarminUpload = false;

  /// Enable GPX workout loading and playback
  static const bool enableGpxWorkouts = false;

  // ============================================
  // STABLE FEATURES (always enabled)
  // ============================================

  /// Enable custom workout builder
  static const bool enableWorkoutBuilder = true;

  /// Enable FIT file export (local save/share)
  static const bool enableFitExport = true;

  /// Enable power ramping in intervals
  static const bool enablePowerRamping = true;

  /// Enable background workout tracking
  static const bool enableBackgroundMode = true;

  // ============================================
  // DEBUG/DEVELOPMENT FLAGS
  // ============================================

  /// Show debug info in workout completion screen
  static const bool showDebugInfo = false;

  /// Enable FIT file validation popup (debug)
  static const bool enableFitValidation = false;
}
