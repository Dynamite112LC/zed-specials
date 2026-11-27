// Reads the products on one leaflet page from the best source it has.
import 'dart:convert';
import 'dart:io';

import 'extract.dart';
import 'pdf_text.dart';
import 'second_reader.dart';

/// A page with fewer text runs than this is a picture of a page with a
/// stray caption, not a typeset page.
const _minTextRuns = 25;

typedef PageReading = ({
  List<ExtractedItem> items,
  String source,

  /// Size of the page in the units the items' boxes are in.
  int width,
  int height,

  /// What the second reader added, when the page has a second reading.
  CombinedReading? second,
});

/// [ocr], [flashes] and [pdfText] are the decoded JSON of the page's
/// ".ocr.json", ".flashes.json" and ".text.json", where they exist.
///
/// The PDF's own text wins when it is there, because it is exact; OCR is
/// kept as the check on it (a PDF can hold real text for the small print
/// and pictures for the prices) and fills in the letters the PDF could not
/// name.
///
/// [second] is the page's second reading (see second_reader.dart), which is
/// put together with a reading made by OCR. Text taken from a PDF is exact
/// already and is left alone.
PageReading readPage(
  String retailerId, {
  Map<String, dynamic>? ocr,
  Map<String, dynamic>? flashes,
  Map<String, dynamic>? pdfText,
  Object? second,
}) {
  final ocrPage = ocr == null ? null : OcrPage.fromJson(ocr, flashes: flashes);
  final fromOcr = ocrPage == null
      ? const <ExtractedItem>[]
      : extractItems(retailerId, ocrPage);

  final runs = (pdfText?['lines'] as List?)?.length ?? 0;
  if (pdfText != null && runs >= _minTextRuns) {
    final text = ocr == null ? pdfText : repairLigatures(pdfText, ocr);
    final fromText = extractItems(retailerId, OcrPage.fromJson(text));
    if (fromText.isNotEmpty && fromText.length >= 0.8 * fromOcr.length) {
      return (
        items: fromText,
        source: 'pdf-text',
        width: text['width'] as int,
        height: text['height'] as int,
        second: null,
      );
    }
  }
  final secondItems = parseSecondReading(second);
  final combined = secondItems == null
      ? null
      : combineReadings(fromOcr, secondItems, page: ocrPage);
  return (
    items: combined?.items ?? fromOcr,
    source: 'ocr',
    width: ocr?['width'] as int? ?? 1,
    height: ocr?['height'] as int? ?? 1,
    second: combined,
  );
}

/// Reads the page whose image is [imagePath] from the files cached beside
/// it, and its second reading from [secondFile] when that exists. Null when
/// nothing has been read from the page yet.
PageReading? readCachedPage(
  String retailerId,
  String imagePath, {
  File? secondFile,
}) {
  Map<String, dynamic>? load(String suffix) {
    final f = File('$imagePath$suffix');
    if (!f.existsSync()) return null;
    final j = jsonDecode(f.readAsStringSync());
    return j is Map<String, dynamic> && j.isNotEmpty ? j : null;
  }

  final ocr = load('.ocr.json');
  final text = load('.text.json');
  if (ocr == null && text == null) return null;
  return readPage(
    retailerId,
    ocr: ocr,
    flashes: load('.flashes.json'),
    pdfText: text,
    second: secondFile != null && secondFile.existsSync()
        ? jsonDecode(secondFile.readAsStringSync())
        : null,
  );
}
