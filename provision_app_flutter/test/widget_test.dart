// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provision_app_flutter/main.dart';

void main() {
  testWidgets('Carga de MyApp y pantalla de provisión', (tester) async {
    await tester.pumpWidget(const MyApp());

    // Cambia al tab de Configuración
    await tester.tap(find.text('Configuración'));
    await tester.pumpAndSettle();

    // Verifica AppBar de la pantalla de provisión
    expect(find.text('Provisionar Gateway ESP32'), findsOneWidget);

    // Asegura que existen los campos SSID/Password
    expect(find.text('SSID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
