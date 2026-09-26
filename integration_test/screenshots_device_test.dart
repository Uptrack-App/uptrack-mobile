// Device entry for the T050 store screenshots.
//
// `flutter test` only runs files under the top-level `integration_test/`
// directory on-device; the canonical test lives in
// `test/integration_test/screenshots_test.dart` so the host suite
// (`flutter test`) keeps exercising the screens with captures skipped.
import '../test/integration_test/screenshots_test.dart' as shots;

void main() => shots.main();
