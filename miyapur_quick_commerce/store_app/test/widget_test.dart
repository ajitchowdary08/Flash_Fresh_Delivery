import 'package:flutter_test/flutter_test.dart';
import 'package:store_app/main.dart';

void main() {
  testWidgets('Store app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FlashFreshStoreApp());

    // Verify the root widget is present
    expect(find.byType(FlashFreshStoreApp), findsOneWidget);
  });
}
