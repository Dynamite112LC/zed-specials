import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zed_specials/src/models.dart';

import '../tool/src/corrections.dart';
import '../tool/src/page_reader.dart';
import '../tool/src/pdf_text.dart';

DealItem item(String id, String name, double price, {int page = 3}) => DealItem(
  id: id,
  catalogueId: 'shoprite-toys',
  retailerId: 'shoprite',
  page: page,
  name: name,
  price: price,
);

Map<String, dynamic> issue({
  required String title,
  required Object correction,
  String author = 'OWNER',
  String created = '2026-11-27T10:00:00Z',
}) => {
  'title': title,
  'author_association': author,
  'created_at': created,
  'body': 'Some words for people.\n\n```json\n${jsonEncode(correction)}\n```\n',
};

void main() {
  final robots = item('a', 'Robots Transforming Combat Figurine', 14.99);
  final fix = Correction(
    leaflet: 'shoprite-toys',
    page: 3,
    readName: robots.name,
    readPrice: 14.99,
    price: 99.99,
    name: robots.name,
  );

  group('applying corrections', () {
    test('a fixed price is marked as corrected', () {
      final out = applyCorrections([robots, item('b', 'Other', 5)], [fix]);
      expect(out.first.price, 99.99);
      expect(out.first.corrected, isTrue);
      expect(out.last.corrected, isFalse);
    });

    test('a reading that is not a product is dropped', () {
      final remove = Correction(
        leaflet: 'shoprite-toys',
        page: 3,
        readName: robots.name,
        readPrice: 14.99,
        remove: true,
      );
      expect(applyCorrections([robots], [remove]), isEmpty);
    });

    test('a correction only touches the reading it was made against', () {
      // Same name on another page, and same place at another price.
      final elsewhere = item('c', robots.name, 14.99, page: 4);
      final repriced = item('d', robots.name, 19.99);
      final out = applyCorrections([elsewhere, repriced], [fix]);
      expect(out.every((i) => !i.corrected), isTrue);
    });

    test('the latest correction wins', () {
      final later = Correction(
        leaflet: 'shoprite-toys',
        page: 3,
        readName: robots.name,
        readPrice: 14.99,
        price: 89.99,
      );
      expect(applyCorrections([robots], [fix, later]).single.price, 89.99);
    });

    test('survives being written down and read back', () {
      final again = Correction.tryParse(jsonDecode(jsonEncode(fix.toJson())));
      expect(again!.matches(robots), isTrue);
      expect(again.price, 99.99);
    });
  });

  group('corrections filed as issues', () {
    test('only the owner\'s issues count', () {
      final list = parseCorrectionIssues([
        issue(title: 'Price correction: Robots', correction: fix.toJson()),
        issue(
          title: 'Price correction: free stuff',
          correction: fix.toJson(),
          author: 'NONE',
        ),
        issue(
          title: 'Price correction: also not the owner',
          correction: fix.toJson(),
          author: 'CONTRIBUTOR',
        ),
      ]);
      expect(list, hasLength(1));
    });

    test('other issues and broken ones are ignored', () {
      final list = parseCorrectionIssues([
        issue(title: 'The app crashes', correction: fix.toJson()),
        {
          'title': 'Price correction: no block',
          'author_association': 'OWNER',
          'body': 'no json here',
        },
        {
          'title': 'Price correction: bad json',
          'author_association': 'OWNER',
          'body': '```json\n{not json}\n```',
        },
        issue(
          title: 'Price correction: silly price',
          correction: {
            ...fix.toJson(),
            'correct': {'price': -5},
          },
        ),
        issue(
          title: 'Price correction: nothing to change',
          correction: {
            'leaflet': 'x',
            'page': 1,
            'read': {'name': 'n', 'price': 1},
          },
        ),
        {
          ...issue(title: 'Price correction: a PR', correction: fix.toJson()),
          'pull_request': <String, dynamic>{},
        },
      ]);
      expect(list, isEmpty);
    });

    test('come back oldest first, so the newest is applied last', () {
      final list = parseCorrectionIssues([
        issue(
          title: 'Price correction: second',
          correction: {
            ...fix.toJson(),
            'correct': {'price': 89.99},
          },
          created: '2026-11-28T10:00:00Z',
        ),
        issue(title: 'Price correction: first', correction: fix.toJson()),
      ]);
      expect(list.map((c) => c.price), [99.99, 89.99]);
    });
  });

  group('text inside a PDF', () {
    String page(List<String> runs) =>
        '<pdf2xml><page number="1" position="absolute" top="0" left="0" '
        'height="1785" width="1262">${runs.join()}</page></pdf2xml>';
    String run(int top, int left, int w, int h, String text) =>
        '<text top="$top" left="$left" width="$w" height="$h" font="1">$text</text>';

    test('kwacha and raised ngwee stay separate runs', () {
      final p = parsePdfXml(
        page([
          run(1149, 514, 93, 51, '<b>199</b>'),
          run(1148, 606, 40, 30, '<b>99</b>'),
          run(1176, 607, 18, 7, 'Each'),
        ]),
      )!;
      final texts = [for (final l in p['lines'] as List) (l as Map)['t']];
      expect(texts, containsAll(['199', '99', 'Each']));
      expect(p['source'], 'pdf-text');
      // 150 dpi page images from a 108 dpi layout.
      expect(p['width'], (1262 * 150 / 72 / 1.5).round());
    });

    test('a line split by a change of font is put back together', () {
      final p = parsePdfXml(
        page([
          run(500, 100, 40, 10, '<b>Jacobs</b>'),
          run(500, 143, 90, 10, 'Instant Coffee'),
        ]),
      )!;
      expect((p['lines'] as List).single['t'], 'Jacobs Instant Coffee');
    });

    test('a drop shadow does not double the words', () {
      final p = parsePdfXml(
        page([
          run(500, 100, 120, 10, 'PnP Red Apples 1.5kg'),
          run(501, 101, 120, 10, 'PnP Red Apples 1.5kg'),
        ]),
      )!;
      expect(p['lines'], hasLength(1));
    });

    test('letter pairs the PDF could not name are taken from OCR', () {
      final text = {
        'width': 1000,
        'height': 1000,
        'lines': [
          {
            't': 'Nescafe Rico y',
            'x': 100,
            'y': 100,
            'w': 200,
            'h': 20,
            'th': 20,
            's': 1.0,
          },
          {
            't': 'In Tin 100g',
            'x': 100,
            'y': 125,
            'w': 150,
            'h': 20,
            'th': 20,
            's': 1.0,
          },
        ],
      };
      final ocr = {
        'width': 1000,
        'height': 1000,
        'lines': [
          {
            't': 'Nescafe Ricoffy',
            'x': 98,
            'y': 98,
            'w': 205,
            'h': 24,
            'th': 24,
            's': 0.99,
          },
          {
            't': 'In Tin 100g',
            'x': 98,
            'y': 123,
            'w': 150,
            'h': 24,
            'th': 24,
            's': 0.99,
          },
        ],
      };
      final fixed = repairLigatures(text, ocr);
      expect((fixed['lines'] as List).first['t'], 'Nescafe Ricoffy');
      // A real space between words is left alone.
      expect((fixed['lines'] as List).last['t'], 'In Tin 100g');
    });

    test('a page without real text is read by OCR', () {
      final reading = readPage(
        'picknpay',
        ocr: {'width': 100, 'height': 100, 'lines': <dynamic>[]},
        pdfText: {'width': 100, 'height': 100, 'lines': <dynamic>[]},
      );
      expect(reading.source, 'ocr');
    });
  });
}
