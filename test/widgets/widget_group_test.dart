import 'package:flutter_test/flutter_test.dart';
import 'package:uptrack_mobile/widgets/widget_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app group id matches the entitled suite', () {
    expect(WidgetGroup.appGroupId, 'group.app.uptrack.mobile');
  });

  test('ensureConfigured is a safe no-op without a host', () async {
    // Under flutter_test the home_widget channel has no host; the helper
    // must swallow that and return normally (twice: the once-guard path).
    await WidgetGroup.ensureConfigured();
    await WidgetGroup.ensureConfigured();
  });
}
