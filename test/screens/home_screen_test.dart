import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:medlingua/providers/app_provider.dart';
import 'package:medlingua/screens/home_screen.dart';

void main() {
  group('HomeScreen', () {
    Widget buildTestWidget() {
      return ChangeNotifierProvider(
        create: (_) => AppProvider(),
        child: const MaterialApp(home: HomeScreen()),
      );
    }

    testWidgets('renders bottom navigation with 4 tabs', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Should have a NavigationBar (Material 3)
      expect(find.byType(NavigationBar), findsOneWidget);

      // Should have 4 tab labels
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Triage'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows FAB for new triage', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('tapping nav tabs changes view', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Tap History tab
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('Encounter History'), findsOneWidget);

      // Tap Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
    });
  });
}
