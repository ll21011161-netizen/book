import 'package:flutter_test/flutter_test.dart';
import 'package:gun_book/data/file_scanner.dart';

void main() {
  final compare = FileScanner.compareNatural;
  test('natural order handles numbers, suffixes and long numeric chunks', () {
    for (final pair in [
      ['1.jpg', '2.jpg'],
      ['2.jpg', '10.jpg'],
      ['page1', 'page1a'],
      ['chapter2.jpg', 'chapter10.jpg'],
      ['c2p9.jpg', 'c2p10.jpg'],
      ['prefix', 'prefix-more'],
      ['99999999999999999999.jpg', '100000000000000000000.jpg'],
    ]) {
      expect(compare(pair[0], pair[1]), lessThan(0), reason: '$pair');
      expect(compare(pair[1], pair[0]), greaterThan(0), reason: '$pair');
    }
    expect((['10.jpg', '2.jpg', '1.jpg']..sort(compare)),
        ['1.jpg', '2.jpg', '10.jpg']);
    expect(compare('page1.jpg', 'page1a.jpg'), lessThan(0));
  });
  test('comparator is reflexive, antisymmetric and transitive', () {
    final names = [
      '',
      'a',
      'a1',
      'a01',
      'a001',
      'a1a',
      'a1a2',
      'a1a10',
      'a2',
      'a10',
      'A10',
      'page1.jpg',
      'page1a.jpg',
      '0',
      '00',
      '1',
      '99999999999999999999',
      '100000000000000000000'
    ];
    for (final a in names) {
      expect(compare(a, a), 0);
      for (final b in names) {
        expect(compare(a, b).sign, -compare(b, a).sign, reason: '$a / $b');
        for (final c in names) {
          if (compare(a, b) <= 0 && compare(b, c) <= 0) {
            expect(compare(a, c), lessThanOrEqualTo(0), reason: '$a / $b / $c');
          }
        }
      }
    }
  });
}
