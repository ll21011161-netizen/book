import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/core/utils.dart';

void main() {
  testWidgets('input dialog preserves value and survives repeated dismissal',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await DialogUtils.showInput(context,
                          title: 'Rename', initial: 'old', hint: 'title');
                    },
                    child: const Text('Open'))))));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('old'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'new');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(result, 'new');
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
