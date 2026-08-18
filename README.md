# Ride Forge

A Flutter app for indoor cycling: build structured training sessions, run them against a Bluetooth smart trainer in ERG mode, and export the result as a `.fit` file.

Built for riders who want to design their own workouts rather than pick from a subscription catalogue. Everything runs on-device — there is no account, no server, and no telemetry.

## Features

- **Workout builder** — compose intervals with target power, duration, and power ramping. Sessions are expressed as a percentage of your FTP, so they scale with your fitness.
- **Built-in workout library** — Recovery, Steady Endurance, Tempo, Sweet Spot, Threshold, Intervals, and Hill Climbing, all scaled automatically from your FTP.
- **FTP calibration** — a built-in ramp test that estimates your Functional Threshold Power, which every other workout is then scaled against.
- **Smart trainer control** — connects over Bluetooth LE using the standard Fitness Machine Service (FTMS, `0x1826`) and drives target power (ERG) or resistance level.
- **Heart rate monitoring** — pairs with any standard BLE heart rate strap (`0x180D`), with a dedicated live monitor screen.
- **Background execution** — workouts keep running with the screen off via an Android foreground service, and the screen stays awake while you're riding.
- **FIT export** — every completed session is written as a `.fit` file you can save, share, or upload to any platform that accepts them.
- **Strava upload** *(optional, see below)* — OAuth 2.0 connection that uploads completed rides directly.
- **Workout history** — past sessions with charts for power, cadence, and heart rate.

### Experimental / off by default

Some features are complete enough to build but not enabled in shipped releases. They are controlled by compile-time constants in [`lib/config/feature_flags.dart`](lib/config/feature_flags.dart) and can be switched on locally:

| Flag | Default | What it does |
| --- | --- | --- |
| `enableGarminUpload` | `false` | Garmin Connect upload via OAuth 1.0a |
| `enableGpxWorkouts` | `false` | Load a GPX track and ride its elevation profile as a workout |
| `showDebugInfo` | `false` | Extra diagnostics on the completion screen |
| `enableFitValidation` | `false` | FIT file validation popup |

## Platform support

**Android is the only supported target.** Several core pieces — the foreground service that keeps workouts alive, in-app update prompts, and the launcher icon configuration — are Android-specific.

The iOS, macOS, Linux, Windows, and web directories that `flutter create` generates are not present in this repository: they were never built or tested, so shipping them would have implied support that does not exist. If you want to experiment with another platform, regenerate the scaffolding yourself:

```bash
flutter create --platforms=ios .
```

Expect to do real work from there — the foreground service and update-prompt code paths have no non-Android implementation.

## Getting started

Requires the Flutter SDK with Dart `^3.9.2`.

```bash
git clone https://github.com/ascenso10/RideForge.git
cd RideForge
flutter pub get

# Generates lib/env/env.g.dart. Required — the app will not compile without it.
dart run build_runner build
```

Then plug in an Android device (Bluetooth LE is not available in emulators) and run:

```bash
flutter run
```

You will need to grant Bluetooth and location permissions on first launch — Android requires location permission for BLE scanning.

### Strava credentials are optional

The `build_runner` step above works with **no configuration at all**. Without credentials the Strava fields compile to empty strings and every Strava entry point hides itself; the rest of the app is fully functional, and you can still export `.fit` files and upload them to Strava manually.

If you want working Strava upload in your own build, register an application at [strava.com/settings/api](https://www.strava.com/settings/api) and:

```bash
cp .env.example .env
# fill in STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET
dart run build_runner build
```

Set your Strava app's **Authorization Callback Domain** to `localhost` — Strava only checks the domain for mobile apps, not the full redirect URI. The app's OAuth callback scheme is `rideforge://`, registered in [`AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml).

`.env` and the generated `lib/env/env.g.dart` are both gitignored. Credentials are obfuscated at compile time by [`envied`](https://pub.dev/packages/envied), which raises the effort needed to pull them out of a built APK but is **not** a substitute for real secrecy — treat any key shipped in a client app as recoverable.

## Project layout

```
lib/
├── config/      feature flags, theme, debug configuration
├── env/         compile-time secrets (envied)
├── models/      workout and ride data models
├── screens/     one file per screen
├── services/    BLE, trainer control, heart rate, FIT, GPX, uploads
└── widgets/     shared UI components
android/         the only supported platform target
scripts/         Python helper for FIT generation (see scripts/README.md)
tools/           FIT file inspection and rewriting utilities
test/            unit tests
```

## Development

```bash
flutter analyze lib          # static analysis
flutter test                 # unit tests
dart run build_runner build  # regenerate env.g.dart after editing .env
```

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the details — the short version is that anything touching trainer control needs testing against real hardware, and no `.env` or `lib/env/env.g.dart` should ever be committed.

## License

Licensed under the [Apache License 2.0](LICENSE).

Not affiliated with or endorsed by Strava, Garmin, or any trainer manufacturer. "Strava" and "Garmin" are trademarks of their respective owners; this project integrates with their public APIs but is not a product of either company.

## Acknowledgements

Built with [Flutter](https://flutter.dev). FIT file encoding uses [`fit_tool`](https://pub.dev/packages/fit_tool); trainer and heart rate connectivity use [`flutter_blue_plus`](https://pub.dev/packages/flutter_blue_plus) and [`flutter_reactive_ble`](https://pub.dev/packages/flutter_reactive_ble).
