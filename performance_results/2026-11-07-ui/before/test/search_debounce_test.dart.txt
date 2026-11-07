import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/screens/bookshelf/search_delegate.dart';

void main() {
  testWidgets('rapid typing searches once and clearing cancels queued search', (tester) async {
    final calls = <String>[];
    final delegate = SearchDel(() {}, search: (query) async {
      calls.add(query);
      return <LibraryItem>[MangaBook(id: '1', title: query, filePaths: [])];
    });
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(onPressed: () => showSearch(context: context, delegate: delegate), child: const Text('Open')))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'g');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(find.byType(TextField), 'gun');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 201));
    await tester.pump();
    expect(calls, ['gun']);
    expect(find.text('gun'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'gunbook');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, ['gun']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
