// Prints what the readers find on cached pages, for checking by eye.
//   dart run tool/dump_items.dart <retailer> <cacheDir>
// A page's second reading is used when it lies beside the page as
// "<page>.vision.json".
import 'dart:io';

import 'src/page_reader.dart';

void main(List<String> args) {
  final files =
      Directory(args[1])
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ocr.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final image = f.path.replaceFirst(RegExp(r'\.ocr\.json$'), '');
    final reading = readCachedPage(
      args[0],
      image,
      secondFile: File('$image.vision.json'),
    )!;
    final items = reading.items;
    final from = reading.source == 'ocr' ? '' : ' (from ${reading.source})';
    stdout.writeln('== ${f.uri.pathSegments.last}: ${items.length} items$from');
    for (final i in items) {
      final size = i.sizeQty == null ? '' : ' [${i.sizeQty} ${i.sizeUnit}]';
      final save = i.save == null ? '' : ' save ${i.save}';
      final card = i.cardPrice == null
          ? ''
          : ' CARD K${i.cardPrice!.toStringAsFixed(2)}';
      final second = i.otherPrice != null
          ? '  OTHER READING: K${i.otherPrice!.toStringAsFixed(2)}'
          : i.agreed
          ? '  agreed'
          : '';
      final was = i.firstName == null ? '' : '  (was: ${i.firstName})';
      stdout.writeln(
        '  K${i.price.toStringAsFixed(2)}${i.perKg ? '/kg' : ''}  ${i.name}'
        '$size$save$card  (${i.confidence.toStringAsFixed(2)})$second$was',
      );
    }
    final s = reading.second;
    if (s != null) {
      stdout.writeln(
        '  second reader: ${s.agreed} agreed, ${s.doubted} differ, '
        '${s.renamed} names repaired, ${s.added} added',
      );
      for (final n in s.notes) {
        stdout.writeln('    $n');
      }
    }
  }
}
