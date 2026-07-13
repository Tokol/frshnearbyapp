import 'package:flutter_test/flutter_test.dart';

import 'package:frshnearby/main.dart';

void main() {
  testWidgets('App renders the localized home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FrshNearbyApp());
    await tester.pumpAndSettle();

    // Test environment defaults to the en locale, so the auth entry point shows.
    expect(find.text('Fresh food near you'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
  });
}
