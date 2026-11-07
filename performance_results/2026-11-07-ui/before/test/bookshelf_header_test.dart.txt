import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/models/library_item.dart';
import 'package:gun_book/widgets/bookshelf_header.dart';

void main() {
  testWidgets('header shows saved progress and changes filters', (tester) async {
    var selected = -1;
    final book = MangaBook(id: 'one', title: '測試漫畫', filePaths: [], lastReadPage: 4, totalPageCount: 10);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BookshelfHeader(recent: book, selectedFilter: 0, onFilter: (value) => selected = value, onContinue: () {}))));
    expect(find.text('測試漫畫'), findsOneWidget);
    expect(find.text('5 / 10 頁'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .5);
    await tester.tap(find.text('未閱讀'));
    expect(selected, 3);
  });
  testWidgets('header hides reading panel without history', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BookshelfHeader(recent: null, selectedFilter: 0, onFilter: (_) {}))));
    expect(find.text('繼續閱讀'), findsNothing);
    expect(find.text('全部'), findsOneWidget);
  });
}
