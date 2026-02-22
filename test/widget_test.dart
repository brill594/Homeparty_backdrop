import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homeparty_backdrop/app_i18n.dart';
import 'package:homeparty_backdrop/app_state.dart';
import 'package:homeparty_backdrop/control_page.dart';

void main() {
  testWidgets('app boots with control page', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: AppI18n.englishLocale,
        supportedLocales: AppI18n.supportedLocales,
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppI18n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ControlPage(
          appState: AppState(),
          locale: AppI18n.englishLocale,
          onLocaleChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Control'), findsOneWidget);
  });
}
