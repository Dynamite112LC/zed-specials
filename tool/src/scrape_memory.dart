// Stands in for a shop whose site cannot be reached today.
//
// Shops' sites now and then refuse cloud servers for a day. Their leaflets
// run for a week or more, so the list from the last run that did get
// through is nearly always still right, and the page images are in the
// cache already. Without this, one shop having a bad morning would hold
// back the other shops' new leaflets too.
//
// The memory is kept beside the price history, so a run on any machine
// that can reach the shop (the scheduled job, or the feed builder run by
// hand on a computer at home) covers for one that cannot.
import 'dart:convert';
import 'dart:io';

import 'package:zed_specials/src/scrape/scrapers.dart';

typedef ScrapeResult = ({
  List<ScrapedCatalogue> catalogues,
  Map<String, String> errors,
});

/// How many days a shop's last known leaflets may stand in for it. After
/// that the shop is reported as failed, so a lasting block does not go
/// unseen.
const memoryDays = 3;

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

String _dayText(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// Runs [scrape]; a shop that failed is filled in from [file] when it was
/// reached within [memoryDays], and its error is dropped. Shops that were
/// reached are remembered in [file] for next time.
Future<ScrapeResult> scrapeWithMemory(
  File file,
  Future<ScrapeResult> Function() scrape, {
  DateTime? now,
  void Function(String message)? log,
}) async {
  var memory = <String, dynamic>{};
  if (file.existsSync()) {
    try {
      memory = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      // A damaged memory only means no stand-in today.
    }
  }

  final live = await scrape();
  final at = _dayOf(now ?? DateTime.now());
  final catalogues = [...live.catalogues];
  final errors = {...live.errors};

  for (final shop in live.errors.keys) {
    final m = memory[shop];
    if (m is! Map<String, dynamic>) continue;
    final reached = _dayOf(DateTime.parse(m['at'] as String));
    if (at.difference(reached).inHours > memoryDays * 24 + 2) continue;
    final remembered = [
      for (final c in m['catalogues'] as List)
        ScrapedCatalogue.fromJson(c as Map<String, dynamic>),
    ];
    if (remembered.isEmpty) continue;
    log?.call(
      '$shop could not be reached (${live.errors[shop]}). Using its '
      '${remembered.length} leaflets from ${_dayText(reached)}.',
    );
    catalogues.addAll(remembered);
    errors.remove(shop);
  }

  for (final shop in {for (final c in live.catalogues) c.retailerId}) {
    memory[shop] = {
      // The day only, so the file changes at most once a day.
      'at': _dayText(at),
      'catalogues': [
        for (final c in live.catalogues)
          if (c.retailerId == shop) c.toJson(),
      ],
    };
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(memory)}\n',
  );
  return (catalogues: catalogues, errors: errors);
}
