import 'package:flutter_test/flutter_test.dart';
import 'package:garim/main.dart';

void main() {
  testWidgets('가림 앱 smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GarimApp());
  });
}