import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homeparty_backdrop/app_state.dart';
import 'package:homeparty_backdrop/control_page.dart';

void main() {
  testWidgets('app boots with control page', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ControlPage(appState: AppState())),
    );

    expect(find.text('ControlPage'), findsOneWidget);
  });
}
