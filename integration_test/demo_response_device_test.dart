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
/// PNGs it wrote into its cache) stays on the device after the suite ends, so
/// the host pulls the captures afterwards with
/// `adb exec-out run-as <package> cat cache/uptrack_screenshots/<name>.png`
/// instead of the fixture holding the app open on a timer.
///
/// Nothing here re-declares the journey, so the device run and the host run
/// cannot drift apart.
library;

import '../test/integration_test/demo_chip_acceptance_test.dart' as fixture;

void main() => fixture.main();
