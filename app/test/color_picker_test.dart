import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_chat/color_picker.dart';

void main() {
  testWidgets('custom picker accepts any exact RGB color', (tester) async {
    Color? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  chosen = await pickCustomColor(context, Colors.blue),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A1B2C3');
    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();
    expect(chosen, const Color(0xFFA1B2C3));
  });
}
