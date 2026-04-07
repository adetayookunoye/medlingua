import 'package:flutter_test/flutter_test.dart';
import 'package:medlingua/main.dart';

void main() {
  testWidgets('MedLingua app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MedLinguaApp());
    // Pump a single frame to render the splash screen
    await tester.pump();
    // Splash screen should show the app name
    expect(find.text('MedLingua'), findsOneWidget);
    // Pump past the 3-second splash timer to avoid pending timer errors
    await tester.pump(const Duration(seconds: 4));
  });
}
