// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:naza_llamadart_gui/controller.dart';
import 'package:naza_llamadart_gui/main.dart';
import 'package:naza_llamadart_gui/models.dart';

void main() {
  testWidgets('NAZA shows the simple bottom navigation', (
    WidgetTester tester,
  ) async {
    final controller = NazaController();
    controller.section = NazaSection.roadScanner;
    await tester.pumpWidget(NazaApp(controller: controller));

    expect(find.text('Scan'), findsWidgets);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.radar_rounded), findsOneWidget);
  });
}
