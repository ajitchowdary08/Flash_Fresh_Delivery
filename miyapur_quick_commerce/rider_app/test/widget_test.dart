import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rider_app/utils/rider_preferences.dart';
import 'package:rider_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Rider App renders without crashing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await RiderPreferences.init();
    await tester.pumpWidget(const FlashFreshRiderApp());
    expect(find.byType(FlashFreshRiderApp), findsOneWidget);
  });
}
