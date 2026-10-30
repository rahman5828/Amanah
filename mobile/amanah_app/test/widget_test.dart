import 'package:flutter_test/flutter_test.dart';
import 'package:amanah_app/main.dart';

void main() {
  testWidgets('AMANAH welcome screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const AmanahApp());

    expect(find.text('AMANAH'), findsOneWidget);
    expect(find.text('Intelligence that cares.'), findsOneWidget);
  });
}