import 'package:flutter_test/flutter_test.dart';
import 'package:pml_5/main.dart';

void main() {
  testWidgets('Smoke test for PML 5 app', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('INCOMING MESSAGE'), findsOneWidget);
  });
}
