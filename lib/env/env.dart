import 'package:envied/envied.dart';

part 'env.g.dart';

/// Compile-time secrets loaded from the project root `.env` file.
///
/// Strava credentials are **optional**. Without a `.env` file the fields fall
/// back to empty strings, the app still builds and runs, and Strava features
/// hide themselves (see [hasStravaCredentials] and `StravaService.isAvailable`).
/// Supply credentials only if you want Strava upload in your own build:
///   1. Copy `.env.example` → `.env`
///   2. Fill in values from https://www.strava.com/settings/api
///   3. dart run build_runner build --delete-conflicting-outputs
///
/// Both `.env` and `env.g.dart` are gitignored.
@Envied(path: '.env', obfuscate: true, requireEnvFile: false)
abstract class Env {
  @EnviedField(varName: 'STRAVA_CLIENT_ID', defaultValue: '')
  static final String stravaClientId = _Env.stravaClientId;

  @EnviedField(varName: 'STRAVA_CLIENT_SECRET', defaultValue: '')
  static final String stravaClientSecret = _Env.stravaClientSecret;

  /// Whether this build was compiled with real Strava API credentials.
  static bool get hasStravaCredentials =>
      stravaClientId.isNotEmpty && stravaClientSecret.isNotEmpty;
}
