import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rsk_teleop/app_branding.dart';

void main() {
  testWidgets('App bar shows display name', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        title: kAppDisplayName,
        home: Scaffold(
          appBar: AppBar(title: const Text(kAppDisplayName)),
        ),
      ),
    );
    expect(find.text(kAppDisplayName), findsOneWidget);
  });
}
