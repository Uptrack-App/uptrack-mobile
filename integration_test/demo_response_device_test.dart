/// Device entry point for the R2 demo response acceptance run.
///
/// The fixture itself lives in
/// `test/integration_test/demo_chip_acceptance_test.dart`, so the ordinary host
/// suite (`flutter test`) keeps covering the journey, the layout and the
/// semantics on every run. This file is that same `main` under the
/// conventional top-level `integration_test/` path, which is what the Android
/// run uses:
///
/// ```sh
/// flutter test integration_test/demo_response_device_test.dart \
///   -d emulator-5554 --no-enable-impeller --no-uninstall
/// ```
///
/// `--no-uninstall` is what makes the evidence collectable: the app (and the
/// PNGs it wrote into its own cache) stays on the device after the suite ends,
/// so the host pulls the captures afterwards with
/// `adb exec-out run-as app.uptrack.mobile cat
/// code_cache/uptrack_screenshots/NAME.png` instead of the fixture holding the
/// app open on a timer.
///
/// `code_cache` because `Directory.systemTemp` is the app's code cache on
/// Android (`/data/user/0/app.uptrack.mobile/code_cache`), not its `cache`
/// directory. The `SCREENSHOT_SAVED` line each capture prints carries the
/// absolute path the run actually wrote, and that is the path to pull.
///
/// `--no-enable-impeller` selects the Skia/OpenGL renderer explicitly.
/// Impeller is not the Android default in this Flutter version, and the
/// emulator's software Vulkan stack stalls on it; naming the flag keeps the
/// acceptance run off that path on purpose rather than by accident.
///
/// Nothing here re-declares the journey, so the device run and the host run
/// cannot drift apart.
///
/// This path is device-only by Flutter's own rule: `flutter test` routes any
/// file under a top-level `integration_test/` directory through a device and
/// refuses to run it without `-d`. That is why the fixture also lives under
/// `test/` — the host suite reaches the same `main` there, and running this file
/// without a device is expected to fail with "No devices found" rather than
/// pointing at a defect in the fixture.
library;

import '../test/integration_test/demo_chip_acceptance_test.dart' as fixture;

void main() => fixture.main();
