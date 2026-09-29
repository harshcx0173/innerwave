import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/auth/auth_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthScreen()));
    expect(find.text('InnerWave'), findsOneWidget);
  });
}
