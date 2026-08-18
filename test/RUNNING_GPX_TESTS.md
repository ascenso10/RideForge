# Running GPX Service Tests

## Prerequisites

Make sure Flutter is installed and dependencies are fetched:

```bash
flutter pub get
```

---

## Run all GPX tests

```bash
flutter test test/gpx_service_test.dart
```

## Run with expanded (verbose) output

Shows each test name and pass/fail individually:

```bash
flutter test test/gpx_service_test.dart --reporter expanded
```

## Run a single test group by name

```bash
flutter test test/gpx_service_test.dart --name "GPX Parsing"
flutter test test/gpx_service_test.dart --name "Slope Computation"
flutter test test/gpx_service_test.dart --name "JSON Serialisation"
```

## Run including skipped tests

The whitespace-padded values test is skipped by default (it is diagnostic).
To run it:

```bash
flutter test test/gpx_service_test.dart --run-skipped
```

## Run all project tests

```bash
flutter test
```

---

## Validate a real GPX file (gpx_validator.dart)

Pass your own GPX file as an argument.  No sample data is baked in —
it uses exactly the same pipeline the app runs at import time.

```bash
dart run test/gpx_validator.dart /path/to/your/route.gpx
```

**Example:**
```bash
dart run test/gpx_validator.dart ~/Downloads/col_du_galibier.gpx
```

### What the validator reports

1. **Parsed points** — total count, first & last point (lat / lon / ele / time)
2. **Raw elevation stats** — min, max, average, std-dev (high std-dev flags GPS noise)
3. **Raw slopes** — min / max / avg / p95 before any smoothing
4. **Processed slopes** — same stats after the app's iterative smoothing (max 25%)
5. **GpxWorkout fields** — total distance, elevation gain, min/max elevation, total time
6. **ASCII elevation profile** — visual shape of the route
7. **Slope histogram** — segment count per slope band, ⚠️ on extreme bands
8. **Suspicious segments** — any segment whose processed |slope| still exceeds 20%
9. **Summary verdict** — ✅ ready or ⚠️ list of problems found

---

## What the tests cover

| Group | What is validated |
|---|---|
| GPX Parsing – valid | Correct point count, lat/lon/ele values, timestamps, skipped points |
| GPX Parsing – invalid | Throws on empty track, malformed XML, all-missing fields |
| **KNOWN ISSUE** – invalid lat/ele | `double.parse()` is unguarded → `FormatException` crashes the import |
| **KNOWN LIMITATION** – route points | `<rtept>`-only GPX files are unsupported (only `<trkpt>` is read) |
| Haversine Distance | Identical points = 0, 1° latitude ≈ 111 195 m, symmetry, London–Paris |
| Slope Computation | Flat = 0%, uphill positive, downhill negative, ~9% grade, div-by-zero guard |
| Elevation Smoothing | Noise reduction, lat/lon preserved, uniform input unchanged, timestamps kept |
| Iterative Smoothing | Max slope threshold respected, max iterations not exceeded |
| GpxWorkout Properties | totalDistance, totalElevationGain, max/minElevation, totalTime |
| Elevation Profile | Cumulative distances, correct length, strictly increasing |
| JSON Round-Trip | GpxPoint, GpxSegment, GpxWorkout all survive toJson → fromJson |
| Full Pipeline | parse → smooth → compute → GpxWorkout end-to-end |

---

## Known issues surfaced by the tests

The following tests are expected to **fail** until the code is fixed.
They document fragile behaviour that causes erratic loading in production:

### 1. Non-numeric lat / lon / ele values crash the importer

`gpx_service.dart` calls `double.parse()` without a try/catch.
Any GPX file containing a value like `lat="N51.5"` or `<ele>???</ele>`
will throw a `FormatException` and abort the entire import.

**Fix:** wrap the three `double.parse()` calls in try/catch (or use
`double.tryParse()`) and skip the offending point with a warning.

### 2. Route-point GPX files are silently unsupported

The parser only searches for `<trkpt>` elements.  GPX files exported
as routes (`<rte>` / `<rtept>`) produce "No track points found" even
though they contain valid coordinate data.

**Fix:** also search `findAllElements('rtept')` when `<trkpt>` is empty.
