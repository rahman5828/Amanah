
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amanah_app/main.dart';

void main() {
  testWidgets('AMANAH welcome screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WelcomeScreen(),
      ),
    );

    expect(find.text('AMANAH'), findsOneWidget);
    expect(find.text('Intelligence that cares.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}
