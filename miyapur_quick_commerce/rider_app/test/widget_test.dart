import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/main.dart';

void main() {
  testWidgets('Rider App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const FlashFreshRiderApp());
    expect(find.byType(FlashFreshRiderApp), findsOneWidget);
  });
}
