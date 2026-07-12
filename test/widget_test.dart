import 'package:flutter_test/flutter_test.dart';

import 'package:frshnearby/main.dart';

void main() {
  testWidgets('App renders the localized home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FrshNearbyApp());
    await tester.pumpAndSettle();

    // Test environment defaults to the en locale, so the English tagline shows.
    expect(find.text('Fresh food from farms near you'), findsOneWidget);
  });
}
