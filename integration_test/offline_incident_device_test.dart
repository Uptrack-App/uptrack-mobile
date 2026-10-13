/// Device entry point for the R4 offline incident context run.
///
/// The fixture itself lives in
/// `test/integration_test/offline_incident_device_test.dart`, so the ordinary
/// host suite (`flutter test`) keeps covering the offline relaunch, the resolved
/// summary, the missing-versus-empty snapshot and the semantics on every run.
/// This file is that same `main` under the conventional top-level
/// `integration_test/` path, which is what the Android run uses:
///
/// ```sh
/// flutter test integration_test/offline_incident_device_test.dart \
///   -d emulator-5554 --no-enable-impeller --no-uninstall
/// ```
///
/// `--no-uninstall` is what makes the evidence collectable: the app (and the
/// PNGs it wrote into its own cache) stays on the device after the suite ends, so
/// the host pulls the captures afterwards with
/// `adb exec-out run-as app.uptrack.mobile cat
/// code_cache/uptrack_r4_offline_screenshots/NAME.png` instead of the fixture
/// holding the app open on a timer.
///
/// `code_cache` because `Directory.systemTemp` is the app's code cache on
/// Android (`/data/user/0/app.uptrack.mobile/code_cache`), not its `cache`
/// directory. The `SCREENSHOT_SAVED` line each capture prints carries the
/// absolute path the run actually wrote, and that is the path to pull.
///
/// Nothing here re-declares the cases, so the device run and the host run cannot
/// drift apart.
library;

import '../test/integration_test/offline_incident_device_test.dart' as fixture;

void main() => fixture.main();