// Prints what the readers find on cached pages, for checking by eye.
//   dart run tool/dump_items.dart <retailer> <cacheDir>
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
    final reading = readCachedPage(args[0], image)!;
    final items = reading.items;
    final from = reading.source == 'ocr' ? '' : ' (from ${reading.source})';
    stdout.writeln('== ${f.uri.pathSegments.last}: ${items.length} items$from');
    for (final i in items) {
      final size = i.sizeQty == null ? '' : ' [${i.sizeQty} ${i.sizeUnit}]';
      final save = i.save == null ? '' : ' save ${i.save}';
      stdout.writeln(
        '  K${i.price.toStringAsFixed(2)}${i.perKg ? '/kg' : ''}  ${i.name}'
        '$size$save  (${i.confidence.toStringAsFixed(2)})',
      );
    }
  }
}
