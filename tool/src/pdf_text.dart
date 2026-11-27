// Reads the real text out of a PDF leaflet, in the same shape as OCR output.
//
// Some shops publish their leaflet as a PDF made straight from the design
// file, with every word still in it as text. That text is exact: no "20o"
// for "200g", no misread price. Poppler's pdftohtml lists it as runs, one
// per change of font, each with its position, which is just what the
// readers need: the big kwacha digits and the small raised ngwee come as
// separate runs.
//
// A PDF made from pictures of the pages has no such text; then this
// returns nothing and OCR does the reading.
import 'dart:convert';
import 'dart:io';

/// pdftohtml's zoom: its pixel is 1/108 inch.
const _zoom = 1.5;

/// The page images are rendered at 150 dpi (see update_feed.dart).
const _imageDpi = 150.0;

String _unescape(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('\u00a0', ' ')
    // Typeset text joins some letter pairs into one character.
    .replaceAll('\ufb00', 'ff')
    .replaceAll('\ufb01', 'fi')
    .replaceAll('\ufb02', 'fl')
    .replaceAll('\ufb03', 'ffi')
    .replaceAll('\ufb04', 'ffl')
    .trim();

/// The text runs on [page] (1-based) of [pdf], as an OCR-style page:
/// `{"width", "height", "lines": [{t, x, y, w, h, th, s}], "source"}`.
/// Returns null when pdftohtml is missing or fails.
Future<Map<String, dynamic>?> readPdfText(String pdf, int page) async {
  final ProcessResult r;
  try {
    r = await Process.run(
      'pdftohtml',
      [
        '-xml',
        '-i',
        '-stdout',
        '-zoom',
        '$_zoom',
        '-f',
        '$page',
        '-l',
        '$page',
        pdf,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException {
    return null;
  }
  if (r.exitCode != 0) return null;
  return parsePdfXml(r.stdout as String);
}

/// Turns pdftohtml's XML for one page into an OCR-style page. Separate
/// from [readPdfText] so it can be tested without Poppler.
Map<String, dynamic>? parsePdfXml(String xml) {
  final pageTag = RegExp(
    r'<page number="\d+"[^>]*height="(\d+)" width="(\d+)"',
  ).firstMatch(xml);
  if (pageTag == null) return null;
  final scale = _imageDpi / 72 / _zoom;
  final height = int.parse(pageTag.group(1)!),
      width = int.parse(pageTag.group(2)!);

  // A run ends wherever the font changes, so one printed line ("Jacobs"
  // in bold, "Instant Coffee" in regular) can arrive in pieces, and a
  // drop shadow arrives as the same words twice. Put the lines back
  // together first. Pieces of different sizes stay apart: that is how the
  // big kwacha digits and the small raised ngwee are told from each other.
  final runs = <_Run>[];
  final tag = RegExp(
    r'<text top="(-?\d+)" left="(-?\d+)" width="(\d+)" height="(\d+)" font="\d+">(.*?)</text>',
    dotAll: true,
  );
  for (final m in tag.allMatches(xml)) {
    final text = _unescape(m.group(5)!);
    if (text.isEmpty) continue;
    final r = _Run(
      text,
      int.parse(m.group(1)!) * scale,
      int.parse(m.group(2)!) * scale,
      int.parse(m.group(3)!) * scale,
      int.parse(m.group(4)!) * scale,
    );
    final shadow = runs.any(
      (o) =>
          o.text == r.text &&
          (o.top - r.top).abs() < r.h &&
          (o.left - r.left).abs() < r.h,
    );
    if (!shadow) runs.add(r);
  }
  runs.sort((a, b) {
    final sameRow = (a.top - b.top).abs() < 0.3 * (a.h < b.h ? a.h : b.h);
    return sameRow ? a.left.compareTo(b.left) : a.top.compareTo(b.top);
  });
  final joined = <_Run>[];
  for (final r in runs) {
    final last = joined.isEmpty ? null : joined.last;
    final digitsOnly = RegExp(r'^[\d.,]+$');
    if (last != null &&
        (last.top - r.top).abs() < 0.3 * r.h &&
        r.h / last.h > 0.85 &&
        r.h / last.h < 1.18 &&
        r.left - (last.left + last.w) > -0.3 * r.h &&
        r.left - (last.left + last.w) < 0.8 * r.h &&
        // Prices keep to themselves: "188" beside "Each" is not a line.
        !digitsOnly.hasMatch(last.text) &&
        !digitsOnly.hasMatch(r.text)) {
      final gap = r.left - (last.left + last.w) > 0.12 * r.h ? ' ' : '';
      joined[joined.length - 1] = _Run(
        '${last.text}$gap${r.text}',
        last.top < r.top ? last.top : r.top,
        last.left,
        r.left + r.w - last.left,
        last.h > r.h ? last.h : r.h,
      );
    } else {
      joined.add(r);
    }
  }

  // The height a PDF gives for a run is its font's line height, which
  // differs between fonts that print at the same size (a brand name in
  // the medium weight comes out half as tall again as the regular words
  // under it). OCR boxes, which the readers were tuned on, hug what is
  // printed. So ordinary small print is given one common height, the
  // typical one on the page, centred where the run is.
  final wordy =
      joined
          .where((r) => RegExp(r'[A-Za-z]').allMatches(r.text).length >= 8)
          .map((r) => r.h)
          .toList()
        ..sort();
  final typical = wordy.isEmpty ? 0.0 : wordy[wordy.length ~/ 2];

  final lines = <Map<String, dynamic>>[];
  for (final r in joined) {
    final digits = RegExp(r'^[\d.,]+$').hasMatch(r.text);
    double x, y, w, h;
    if (digits) {
      // Measured against OCR boxes of the same price digits.
      h = 1.08 * r.h;
      x = r.left - 0.16 * r.h;
      y = r.top - 0.16 * r.h;
      w = 1.17 * r.w;
    } else {
      final small = typical > 0 && r.h >= 0.6 * typical && r.h <= 1.8 * typical;
      final glyph = small ? typical : r.h;
      h = 1.2 * glyph;
      x = r.left - 0.2 * glyph;
      y = r.top + r.h / 2 - h / 2;
      w = r.w + 0.4 * glyph;
    }
    lines.add({
      't': r.text,
      'x': x.round(),
      'y': y.round(),
      'w': w.round(),
      'h': h.round(),
      'th': h.round(),
      's': 1.0,
    });
  }
  return {
    'width': (width * scale).round(),
    'height': (height * scale).round(),
    'lines': lines,
    'source': 'pdf-text',
  };
}

class _Run {
  _Run(this.text, this.top, this.left, this.w, this.h);

  final String text;
  final double top, left, w, h;
}

/// Some PDFs cannot say which letters a joined pair like "ff" stands for,
/// and give a gap instead: "Nescafe Rico y", "Instant Co ee". Where OCR
/// read the same line, its letters settle what belongs in the gap.
///
/// [text] and [ocr] are OCR-style pages of the same leaflet page. Returns
/// [text] with such lines repaired.
Map<String, dynamic> repairLigatures(
  Map<String, dynamic> text,
  Map<String, dynamic> ocr,
) {
  const pairs = ['ffi', 'ffl', 'ff', 'fi', 'fl'];
  String squash(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final ocrLines = (ocr['lines'] as List).cast<Map<String, dynamic>>();

  final lines = <Map<String, dynamic>>[];
  for (final l in (text['lines'] as List).cast<Map<String, dynamic>>()) {
    final t = l['t'] as String;
    final gaps = RegExp(r'(?<=[a-z]) (?=[a-z])').allMatches(t).toList();
    if (gaps.isEmpty) {
      lines.add(l);
      continue;
    }
    // What OCR printed in the same place.
    final cx = (l['x'] as num) + (l['w'] as num) / 2;
    final cy = (l['y'] as num) + (l['h'] as num) / 2;
    final there = ocrLines
        .where(
          (o) =>
              cy > (o['y'] as num) &&
              cy < (o['y'] as num) + (o['h'] as num) &&
              cx > (o['x'] as num) &&
              cx < (o['x'] as num) + (o['w'] as num),
        )
        .map((o) => squash(o['t'] as String))
        .toList();
    var fixed = t;
    // Try each gap, last first so earlier positions stay valid.
    for (final g in gaps.reversed) {
      for (final pair in pairs) {
        final candidate = fixed.replaceRange(g.start, g.end, pair);
        if (there.any(
          (o) => o == squash(candidate) || o.contains(squash(candidate)),
        )) {
          fixed = candidate;
          break;
        }
        // Several gaps in one line: accept a fill that makes this word
        // one OCR also has.
        final word = RegExp(
          r'[A-Za-z]+$',
        ).stringMatch(fixed.substring(0, g.start));
        final rest = RegExp(r'^[A-Za-z]+').stringMatch(fixed.substring(g.end));
        if (word != null && rest != null) {
          final joined = squash('$word$pair$rest');
          if (joined.length >= 5 && there.any((o) => o.contains(joined))) {
            fixed = candidate;
            break;
          }
        }
      }
    }
    lines.add(fixed == t ? l : {...l, 't': fixed});
  }
  return {...text, 'lines': lines};
}
