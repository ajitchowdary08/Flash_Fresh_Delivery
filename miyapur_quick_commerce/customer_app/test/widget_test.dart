import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const FlashFreshApp());
    expect(find.byType(FlashFreshApp), findsOneWidget);
  });
}
