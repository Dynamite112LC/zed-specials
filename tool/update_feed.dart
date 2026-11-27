// Builds assets/data/feed.json: the catalogues currently published by each
// shop, their pages, and every price that could be read from them.
//
//   dart run tool/update_feed.dart            full run
//   dart run tool/update_feed.dart --ocr-only stop after reading the pages
//   dart run tool/update_feed.dart --strict   fail if any shop cannot be read
//                                             (for unattended, scheduled runs)
//   dart run tool/update_feed.dart --history <file>
//                                             where old prices are kept
//                                             (default data/history.json)
//   dart run tool/update_feed.dart --corrections-repo owner/name
//                                             apply the price corrections
//                                             filed as issues on that GitHub
//                                             repository (the scheduled job
//                                             uses its own repository)
//   dart run tool/update_feed.dart --lists-only
//                                             only note which leaflets each
//                                             shop lists today, in
//                                             data/last-scrape.json. Takes
//                                             seconds and needs no Python.
//                                             For a computer that the shops
//                                             answer, covering for the
//                                             scheduled job where they do
//                                             not (tool/update-leaflet-lists.ps1)
//
// Pages are read a second time by a vision model, separately
// (tool/second_reader.py). Its readings are kept in "second/" beside the
// price history and put together with the first reading here; the pages
// still waiting for one are listed in second/pending.json.
//
// Needs Python with RapidOCR for reading prices (see tool/ocr.py) and
// pdftoppm (Poppler) for the shops that publish PDFs. Page images and OCR
// results are cached in .cache/, so repeat runs only process new leaflets.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:zed_specials/src/models.dart';
import 'package:zed_specials/src/scrape/scrapers.dart';

import 'src/corrections.dart';
import 'src/extract.dart';
import 'src/history.dart';
import 'src/matching.dart';
import 'src/page_reader.dart';
import 'src/pdf_text.dart';
import 'src/scrape_memory.dart';

const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

final _cache = Directory('.cache');
final _out = Directory('assets/data');

String _two(int n) => n.toString().padLeft(2, '0');

String findPython() {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  final candidates = [
    Platform.environment['ZED_OCR_PYTHON'],
    'tool/.venv/Scripts/python.exe',
    'tool/.venv/bin/python',
    '$home/.zed_specials/ocr-env/Scripts/python.exe',
    '$home/.zed_specials/ocr-env/bin/python',
  ];
  for (final c in candidates) {
    if (c != null && c.isNotEmpty && File(c).existsSync()) return c;
  }
  return Platform.isWindows ? 'python' : 'python3';
}

Future<bool> download(http.Client client, String url, File dest) async {
  if (dest.existsSync() && dest.lengthSync() > 0) return true;
  try {
    final res = await client
        .get(Uri.parse(url), headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      stderr.writeln('  download failed (${res.statusCode}): $url');
      return false;
    }
    dest.parent.createSync(recursive: true);
    dest.writeAsBytesSync(res.bodyBytes);
    return true;
  } catch (e) {
    stderr.writeln('  download failed ($e): $url');
    return false;
  }
}

Future<void> runPython(List<Map<String, dynamic>> jobs, String label) async {
  if (jobs.isEmpty) return;
  final jobFile = File('${_cache.path}/jobs.json')
    ..writeAsStringSync(jsonEncode(jobs));
  stdout.writeln('$label: ${jobs.length} image jobs');
  final proc = await Process.start(findPython(), [
    'tool/ocr.py',
    jobFile.path,
  ], runInShell: false);
  proc.stdout.transform(utf8.decoder).listen((s) {
    for (final line in const LineSplitter().convert(s)) {
      if (line.startsWith('[') || line.startsWith('done')) {
        stdout.writeln('  $line');
      }
    }
  });
  final err = StringBuffer();
  proc.stderr.transform(utf8.decoder).listen(err.write);
  final code = await proc.exitCode;
  if (code != 0) {
    stderr.writeln(err);
    throw StateError('tool/ocr.py exited with $code');
  }
}

class _Work {
  _Work(this.scraped) : sid = shortId(scraped.id);

  final ScrapedCatalogue scraped;
  final String sid;

  /// Local page images, largest size, in page order.
  final List<File> pages = [];
  String? coverPath;
}

Future<void> main(List<String> args) async {
  final ocrOnly = args.contains('--ocr-only');
  final strict = args.contains('--strict');
  final listsOnly = args.contains('--lists-only');
  final historyArg = args.indexOf('--history');
  final historyFile = File(
    historyArg >= 0 && historyArg + 1 < args.length
        ? args[historyArg + 1]
        : 'data/history.json',
  );
  // Read first: a damaged history must stop the run before anything is
  // written over it.
  final history = PriceHistory.load(historyFile);
  _cache.createSync(recursive: true);
  Directory('${_out.path}/pages').createSync(recursive: true);
  Directory('${_out.path}/crops').createSync(recursive: true);

  final client = http.Client();
  stdout.writeln('Checking the shops\' specials pages');
  // A shop that cannot be reached is filled in with the leaflets it had
  // on the last run that did reach it (see tool/src/scrape_memory.dart).
  final scrape = await scrapeWithMemory(
    File('${historyFile.parent.path}/last-scrape.json'),
    () => scrapeAll(client),
    log: (m) => stderr.writeln('  $m'),
  );
  scrape.errors.forEach((shop, e) => stderr.writeln('  $shop failed: $e'));
  if (scrape.catalogues.isEmpty) {
    stderr.writeln('No catalogues found. Keeping the existing feed.');
    client.close();
    exitCode = 1;
    return;
  }
  if (listsOnly) {
    client.close();
    for (final r in Retailer.all) {
      final n = scrape.catalogues.where((c) => c.retailerId == r.id).length;
      final how = scrape.errors.containsKey(r.id)
          ? 'could not be reached'
          : scrape.standIns.containsKey(r.id)
          ? 'could not be reached; $n remembered'
          : '$n leaflets listed';
      stdout.writeln('${r.name}: $how');
    }
    return;
  }
  if (strict && scrape.errors.isNotEmpty) {
    stderr.writeln(
      'Strict run: ${scrape.errors.keys.join(', ')} could not be read. '
      'Keeping the existing feed.',
    );
    client.close();
    exitCode = 1;
    return;
  }

  // ------------------------------------------------ fetch the page images
  final work = <_Work>[];
  for (final c in scrape.catalogues) {
    final w = _Work(c);
    final dir = Directory('${_cache.path}/${w.sid}');
    dir.createSync(recursive: true);
    stdout.writeln('${c.retailerId}: ${c.title} (${w.sid})');

    if (c.pdfUrl != null) {
      final pdf = File('${dir.path}/c.pdf');
      final done = File('${dir.path}/pdf.done');
      if (!done.existsSync() && await download(client, c.pdfUrl!, pdf)) {
        final r = await Process.run('pdftoppm', [
          '-r',
          '150',
          '-jpeg',
          '-jpegopt',
          'quality=88',
          pdf.path,
          '${dir.path}/p',
        ]);
        if (r.exitCode == 0) {
          done.writeAsStringSync('ok');
        } else {
          stderr.writeln('  pdftoppm failed: ${r.stderr}');
        }
      }
      final rendered = dir
          .listSync()
          .whereType<File>()
          .where((f) => RegExp(r'[\\/]p-\d+\.jpg$').hasMatch(f.path))
          .toList();
      int pageNo(File f) =>
          int.parse(RegExp(r'p-(\d+)\.jpg$').firstMatch(f.path)!.group(1)!);
      rendered.sort((a, b) => pageNo(a).compareTo(pageNo(b)));
      w.pages.addAll(rendered);
    } else {
      for (var i = 0; i < c.ocrImageUrls.length; i++) {
        final url = c.ocrImageUrls[i];
        final ext = url.toLowerCase().endsWith('.webp') ? 'webp' : 'jpg';
        final f = File('${dir.path}/p${_two(i + 1)}.$ext');
        if (await download(client, url, f)) w.pages.add(f);
      }
    }
    stdout.writeln('  ${w.pages.length} pages');
    work.add(w);
  }
  client.close();

  // A leaflet whose pages could not all be fetched would publish with holes.
  if (strict) {
    for (final w in work) {
      final expected = w.scraped.pdfUrl != null
          ? 1
          : w.scraped.ocrImageUrls.length;
      if (w.pages.length < expected) {
        stderr.writeln(
          'Strict run: ${w.scraped.title} has ${w.pages.length} of '
          '$expected pages. Keeping the existing feed.',
        );
        exitCode = 1;
        return;
      }
    }
  }

  // Forget cached pages of leaflets that are no longer published.
  final current = {for (final w in work) w.sid};
  for (final d in _cache.listSync().whereType<Directory>()) {
    if (!current.contains(d.uri.pathSegments.lastWhere((s) => s.isNotEmpty))) {
      d.deleteSync(recursive: true);
    }
  }

  // ----------------------------------------- read the pages, shrink copies
  final jobs = <Map<String, dynamic>>[];
  for (final w in work) {
    for (var i = 0; i < w.pages.length; i++) {
      final src = w.pages[i].path;
      if (!File('$src.ocr.json').existsSync()) {
        jobs.add({'op': 'ocr', 'src': src, 'out': '$src.ocr.json'});
      }
      // Shoprite's prices are also read by their colours, which gets the
      // big stylised digits right where general OCR often does not.
      if (w.scraped.retailerId == 'shoprite' &&
          !File('$src.flashes.json').existsSync()) {
        jobs.add({'op': 'flashes', 'src': src, 'out': '$src.flashes.json'});
      }
      final view = '${_out.path}/pages/${w.sid}-${_two(i + 1)}.jpg';
      if (!File(view).existsSync()) {
        jobs.add({'op': 'resize', 'src': src, 'out': view, 'maxHeight': 1500});
      }
    }
    if (w.pages.isNotEmpty) {
      final cover = '${_out.path}/pages/${w.sid}-cover.jpg';
      w.coverPath = 'pages/${w.sid}-cover.jpg';
      if (!File(cover).existsSync()) {
        jobs.add({
          'op': 'resize',
          'src': w.pages.first.path,
          'out': cover,
          'maxHeight': 560,
          'quality': 80,
        });
      }
    }
  }
  await runPython(jobs, 'Reading pages');
  if (ocrOnly) return;

  // -------------------------------------------------------- find the items
  final previous = _readPreviousFeed();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final catalogues = <Catalogue>[];
  var fromText = 0;
  // Second readings of the pages, made by tool/second_reader.py and kept
  // beside the price history (see tool/src/second_reader.dart).
  final secondDir = Directory('${historyFile.parent.path}/second');
  final awaiting = <Map<String, String>>[];
  var readTwice = 0, agreed = 0, doubted = 0, renamed = 0, added = 0;
  var items = <DealItem>[];
  final cropJobs = <Map<String, dynamic>>[];

  for (final w in work) {
    final c = w.scraped;
    final pages = <CataloguePage>[];
    for (var i = 0; i < w.pages.length; i++) {
      final view = File('${_out.path}/pages/${w.sid}-${_two(i + 1)}.jpg');
      if (!view.existsSync()) continue;
      pages.add(CataloguePage(image: 'pages/${w.sid}-${_two(i + 1)}.jpg'));

      // A leaflet published as a PDF may still hold its words as text,
      // which is exact where OCR is not.
      final textFile = File('${w.pages[i].path}.text.json');
      if (c.pdfUrl != null && !textFile.existsSync()) {
        final n = RegExp(r'p-(\d+)\.jpg$').firstMatch(w.pages[i].path);
        final text = n == null
            ? null
            : await readPdfText(
                '${_cache.path}/${w.sid}/c.pdf',
                int.parse(n.group(1)!),
              );
        // An empty file records that there was nothing to read.
        textFile.writeAsStringSync(jsonEncode(text ?? const {}));
      }

      final key = '${w.sid}-${_two(i + 1)}';
      final secondFile = File('${secondDir.path}/$key.json');
      final reading = readCachedPage(
        c.retailerId,
        w.pages[i].path,
        secondFile: secondFile,
      );
      if (reading == null) continue;
      if (reading.source != 'ocr') fromText++;
      final second = reading.second;
      if (second != null) {
        readTwice++;
        agreed += second.agreed;
        doubted += second.doubted;
        renamed += second.renamed;
        added += second.added;
        for (final note in second.notes) {
          stdout.writeln('  ${c.title} page ${i + 1}: $note');
        }
      } else if (reading.source == 'ocr' && _secondAttempts(secondFile) < 2) {
        // Text taken from a PDF is exact and needs no second reading. A
        // page the second reader failed on twice is left to the first.
        awaiting.add({'key': key, 'image': 'pages/$key.jpg'});
      }
      final found = reading.items;
      for (var k = 0; k < found.length; k++) {
        final e = found[k];
        final id = '${w.sid}-${_two(i + 1)}-${_two(k + 1)}';
        final crop = 'crops/$id.jpg';
        cropJobs.add({
          'op': 'crop',
          'src': w.pages[i].path,
          'out': '${_out.path}/$crop',
          'x': e.crop.x,
          'y': e.crop.y,
          'w': e.crop.w,
          'h': e.crop.h,
          'maxSide': 360,
        });
        final category = categorise(e.name);
        // Two unrecognised words and no pack size is nearly always stray
        // text (a slogan, a fragment of packaging), not a product.
        if (category == 'Other' &&
            e.sizeQty == null &&
            RegExp(r'[A-Za-z]{3,}').allMatches(e.name).length < 3) {
          continue;
        }
        // The litres of a fridge or the kilograms of a washer are not a
        // pack size.
        final sized =
            category != 'Electronics & appliances' &&
            category != 'Home & outdoor' &&
            e.price < 1500 &&
            // "Flour 500g + Sugar 500g": a bundle has no single pack size.
            !e.bundle &&
            !e.name.contains('+');
        items.add(
          DealItem(
            id: id,
            catalogueId: c.id,
            retailerId: c.retailerId,
            page: i + 1,
            name: e.name,
            price: e.price,
            perKg: e.perKg,
            per100g: e.per100g,
            sizeQty: sized ? e.sizeQty : null,
            sizeUnit: sized ? e.sizeUnit : null,
            save: e.save,
            crop: crop,
            category: category,
            confidence: e.confidence,
            agreed: e.agreed,
            otherPrice: e.otherPrice,
            firstName: e.firstName,
            cardPrice: e.cardPrice,
            box: () {
              final r = e.regionOn(reading.width, reading.height);
              double part(num v, int of) =>
                  double.parse((v / of).clamp(0, 1).toStringAsFixed(4));
              return [
                part(r.x, reading.width),
                part(r.y, reading.height),
                part(r.w, reading.width),
                part(r.h, reading.height),
              ];
            }(),
          ),
        );
      }
    }
    catalogues.add(
      Catalogue(
        id: c.id,
        retailerId: c.retailerId,
        title: c.title,
        sourceUrl: c.sourceUrl,
        cover: w.coverPath,
        validFrom: c.validFrom,
        validTo: c.validTo,
        stores: c.stores?.replaceAll(RegExp(r'\s*,\s*'), ', '),
        firstSeen: history.firstSeen(c.id) ?? previous[c.id] ?? today,
        areas: c.areas,
        pages: pages,
      ),
    );
    final n = items.where((i) => i.catalogueId == c.id).length;
    stdout.writeln('${c.retailerId}: ${c.title}: $n prices read');
  }

  // The list of pages still to be read a second time, for the job that
  // does it; and no second readings of leaflets that are gone.
  secondDir.createSync(recursive: true);
  File('${secondDir.path}/pending.json').writeAsStringSync(
    '${const JsonEncoder.withIndent(' ').convert(awaiting)}\n',
  );
  final live = {for (final w in work) w.sid};
  for (final f in secondDir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name != 'pending.json' && !live.contains(name.split('-').first)) {
      f.deleteSync();
    }
  }
  final ghOutput = Platform.environment['GITHUB_OUTPUT'];
  if (ghOutput != null) {
    File(ghOutput).writeAsStringSync(
      'second_pending=${awaiting.length}\n',
      mode: FileMode.append,
    );
  }

  // Crops are rewritten each run because item numbering can shift.
  final cropDir = Directory('${_out.path}/crops');
  for (final f in cropDir.listSync().whereType<File>()) {
    f.deleteSync();
  }
  await runPython(cropJobs, 'Cutting out item pictures');

  // Corrections people filed come before anything is compared or
  // recorded, so matches and the price history use the right figures.
  final repoArg = args.indexOf('--corrections-repo');
  final repo = repoArg >= 0 && repoArg + 1 < args.length
      ? args[repoArg + 1]
      : Platform.environment['GITHUB_REPOSITORY'];
  final correctionsFile = File('${historyFile.parent.path}/corrections.json');
  List<Correction>? corrections;
  if (repo != null && repo.isNotEmpty) {
    final gh = http.Client();
    corrections = await fetchCorrections(
      gh,
      repo,
      token: Platform.environment['GITHUB_TOKEN'],
    );
    gh.close();
    if (corrections == null) {
      stderr.writeln('Could not read the corrections from $repo.');
    } else {
      correctionsFile.parent.createSync(recursive: true);
      correctionsFile.writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert([for (final c in corrections) c.toJson()])}\n',
      );
    }
  }
  // GitHub out of reach, or a run with no repository named: use the last
  // list that was saved.
  if (corrections == null && correctionsFile.existsSync()) {
    try {
      corrections = [
        for (final j in jsonDecode(correctionsFile.readAsStringSync()) as List)
          ?Correction.tryParse(j),
      ];
    } catch (_) {}
  }
  if (corrections != null && corrections.isNotEmpty) {
    final before = items;
    items = applyCorrections(items, corrections);
    final fixed = items.where((i) => i.corrected).length;
    stdout.writeln(
      'Corrections: ${corrections.length} on file, $fixed applied, '
      '${before.length - items.length} readings removed',
    );
  }

  items = groupSimilar(items);
  items = history.record(catalogues, items, today);
  history.save(historyFile);

  // Drop page images of leaflets that are no longer published.
  final keep = {for (final w in work) w.sid};
  for (final f in Directory(
    '${_out.path}/pages',
  ).listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!keep.contains(name.split('-').first)) f.deleteSync();
  }

  final feed = Feed(generatedAt: now, catalogues: catalogues, items: items);
  File(
    '${_out.path}/feed.json',
  ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(feed.toJson()));
  final groups = items.map((i) => i.groupId).whereType<String>().toSet();
  stdout.writeln(
    'Wrote ${_out.path}/feed.json: ${catalogues.length} catalogues, '
    '${items.length} prices, ${groups.length} matched products',
  );
  if (fromText > 0) {
    stdout.writeln('$fromText pages were read from the text inside their PDF');
  }
  if (readTwice > 0 || awaiting.isNotEmpty) {
    stdout.writeln(
      'Second reader: $readTwice pages read twice ($agreed prices agreed, '
      '$doubted differ, $renamed names repaired, $added items added); '
      '${awaiting.length} pages still to read',
    );
  }
  stdout.writeln(
    'Price history in ${historyFile.path}: ${history.leaflets.length} '
    'leaflets, ${history.products.length} products, '
    '${items.where((i) => i.history.isNotEmpty).length} of today\'s prices '
    'have an earlier price to compare with',
  );

  // A stood-in shop keeps its known leaflets, but its new ones go unseen.
  // Say so every time, and raise the alarm once it has gone on for days:
  // the scheduled job turns the "unreachable" output into a failed step
  // after publishing, so GitHub sends an email while the feed stays fresh.
  const alarmAfterDays = 3;
  final onGitHub = Platform.environment['GITHUB_ACTIONS'] == 'true';
  final overdue = <String>[];
  scrape.standIns.forEach((shop, reached) {
    final since = '${reached.year}-${_two(reached.month)}-${_two(reached.day)}';
    final line =
        '$shop has not been reached since $since. Its leaflets from then '
        'are shown until they end; newer ones are not seen. Run the feed '
        'builder on a computer the shop does answer and push the "data" '
        'branch to bring it up to date.';
    stdout.writeln(onGitHub ? '::warning::$line' : line);
    if (daysBetween(reached, today) > alarmAfterDays) {
      overdue.add('$shop (last reached $since)');
    }
  });
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (overdue.isNotEmpty && output != null) {
    File(output).writeAsStringSync(
      'unreachable=${overdue.join(', ')}\n',
      mode: FileMode.append,
    );
  }
}

/// How many times the second reader has tried and failed on a page.
int _secondAttempts(File f) {
  if (!f.existsSync()) return 0;
  try {
    final j = jsonDecode(f.readAsStringSync());
    return j is Map && j['failed'] is int ? j['failed'] as int : 0;
  } catch (_) {
    return 0;
  }
}

/// First-seen dates from the feed written by the previous run.
Map<String, DateTime> _readPreviousFeed() {
  final f = File('${_out.path}/feed.json');
  if (!f.existsSync()) return {};
  try {
    final feed = Feed.fromJson(
      jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
    );
    return {
      for (final c in feed.catalogues)
        if (c.firstSeen != null) c.id: c.firstSeen!,
    };
  } catch (_) {
    return {};
  }
}
