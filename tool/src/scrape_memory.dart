// Stands in for a shop whose site cannot be reached.
//
// Some shops' sites refuse cloud servers, for a day or for good. (Shoprite's
// main site blocks GitHub's servers outright, while the separate host that
// serves its leaflets does not.) A leaflet is valid until the date printed
// on it, so the leaflets a shop had on the last run that got through keep
// standing in for it until each one ends. The other shops carry on being
// updated, and nothing is published that the shop has not itself published.
//
// What a stand-in cannot do is notice a NEW leaflet. So the caller is told
// when each stood-in shop was last reached and can raise the alarm.
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

typedef RememberedScrape = ({
  List<ScrapedCatalogue> catalogues,

  /// Shops that failed and were never reached before: nothing to stand in.
  Map<String, String> errors,

  /// Shops filled in from memory, with the day they were last reached.
  Map<String, DateTime> standIns,
});

/// A remembered leaflet with no end date is trusted for this long.
const undatedLeafletDays = 14;

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

String _dayText(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// Whole days from [a] to [b], both taken as calendar days.
int daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Runs [scrape]. A shop that failed is filled in with the leaflets it had
/// when it was last reached and that have not ended yet. Shops that were
/// reached are remembered in [file] for next time.
Future<RememberedScrape> scrapeWithMemory(
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
  final today = _dayOf(now ?? DateTime.now());
  final catalogues = [...live.catalogues];
  final errors = {...live.errors};
  final standIns = <String, DateTime>{};

  for (final shop in live.errors.keys) {
    final m = memory[shop];
    if (m is! Map<String, dynamic>) continue;
    final reached = _dayOf(DateTime.parse(m['at'] as String));
    final running =
        [
          for (final c in m['catalogues'] as List)
            ScrapedCatalogue.fromJson(c as Map<String, dynamic>),
        ].where((c) {
          final end = c.validTo;
          if (end == null) {
            return daysBetween(reached, today) <= undatedLeafletDays;
          }
          return daysBetween(today, end) >= 0;
        }).toList();
    log?.call(
      '$shop could not be reached (${live.errors[shop]}). Standing in: '
      '${running.length} of its leaflets from ${_dayText(reached)} that '
      'are still running.',
    );
    catalogues.addAll(running);
    errors.remove(shop);
    standIns[shop] = reached;
  }

  for (final shop in {for (final c in live.catalogues) c.retailerId}) {
    memory[shop] = {
      // The day only, so the file changes at most once a day.
      'at': _dayText(today),
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
  return (catalogues: catalogues, errors: errors, standIns: standIns);
}
