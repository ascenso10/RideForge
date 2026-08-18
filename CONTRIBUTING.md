# Contributing to Ride Forge

Thanks for your interest. This is a small project, so the process is informal — open an issue before starting anything large so we can agree on the approach first.

## Setting up

```bash
flutter pub get
dart run build_runner build   # generates lib/env/env.g.dart — required to compile
flutter analyze lib
flutter test
```

You need a physical Android device to run the app. Bluetooth LE does not work in emulators, so anything touching device connectivity cannot be exercised without hardware.

## Hardware-dependent changes

**Anything that touches trainer control needs testing against a real trainer.** BLE behaviour varies a lot between models and the FTMS implementations in the wild are inconsistent — trainers disagree about which control-point opcodes they accept, how they respond to them, and how quickly they apply a new target.

If you change [`lib/services/trainer_service.dart`](lib/services/trainer_service.dart) or anything under the FTMS path, please say in the pull request which trainer you tested on, and what you tested (ERG target changes, resistance mode, reconnection after a dropout). A change that works on one trainer can silently break another, and we have no way to catch that in CI.

The same applies to heart rate monitors, though the HRS profile (`0x180D`) is far more consistent in practice.

## Never commit secrets

`.env` and the generated `lib/env/env.g.dart` are both gitignored, as are `android/key.properties` and any `*.jks` / `*.keystore` file. Please keep it that way.

If you need a new compile-time secret, add it as an `@EnviedField` in [`lib/env/env.dart`](lib/env/env.dart) with a `defaultValue: ''`, add the variable name to `.env.example`, and gate the feature so that a build with no credentials still compiles and simply hides that feature. Strava works this way already — use it as the reference.

Note that `envied` obfuscation is not real secrecy. Anything compiled into a client app is recoverable by a determined person; it only raises the effort. Do not put a secret in the app that would be damaging if extracted.

## Code style

Match the surrounding code. Run `flutter analyze lib` before opening a pull request — it should not introduce new warnings. There are some pre-existing warnings (unused locals and dead private methods, mostly in `trainer_service.dart`); you do not need to fix those, but please don't add more.

## Platform scope

Android is the only supported target. The other Flutter platform directories were removed because they were never built or tested. Pull requests adding real, tested support for another platform are welcome, but they need to genuinely work — including the foreground service that keeps workouts alive with the screen off, which currently has no non-Android implementation.

## Licensing

Ride Forge is licensed under the [Apache License 2.0](LICENSE). By contributing, you agree that your contributions are licensed under the same terms.
