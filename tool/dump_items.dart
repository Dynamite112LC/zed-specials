// Prints what the readers find on cached pages, for checking by eye.
//   dart run tool/dump_items.dart <retailer> <cacheDir>
import 'dart:convert';
import 'dart:io';

import 'src/extract.dart';

void main(List<String> args) {
  final files =
      Directory(args[1])
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.ocr.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final flashes = File(
      f.path.replaceFirst(RegExp(r'\.ocr\.json$'), '.flashes.json'),
    );
    final page = OcrPage.fromJson(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      flashes: flashes.existsSync()
          ? jsonDecode(flashes.readAsStringSync()) as Map<String, dynamic>
          : null,
    );
    final items = extractItems(args[0], page);
    stdout.writeln('== ${f.uri.pathSegments.last}: ${items.length} items');
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
