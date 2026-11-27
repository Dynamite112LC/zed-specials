// Corrections people have made to readings.
//
// In the app, "Fix this reading" opens a filled-in issue on the feed's
// GitHub repository. The feed builder reads those issues and applies the
// corrections, so a fix reaches every device and the price history.
//
// Anyone can open an issue on a public repository, so only issues written
// by the repository's owner count. Each one carries the correction as a
// small block of JSON, which is checked field by field before use.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:zed_specials/src/models.dart';

const _titlePrefix = 'Price correction';

/// Picks the corrections out of a page of GitHub's issue list (the decoded
/// JSON of GET /repos/{owner}/{repo}/issues), oldest first.
List<Correction> parseCorrectionIssues(List<dynamic> issues) {
  final dated = <(String, Correction)>[];
  for (final issue in issues) {
    if (issue is! Map) continue;
    if (issue.containsKey('pull_request')) continue;
    if (issue['author_association'] != 'OWNER') continue;
    final title = issue['title'], body = issue['body'];
    if (title is! String || !title.startsWith(_titlePrefix)) continue;
    if (body is! String) continue;
    final block = RegExp(
      r'```json\s*(\{.*?\})\s*```',
      dotAll: true,
    ).firstMatch(body);
    if (block == null) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(block.group(1)!);
    } catch (_) {
      continue;
    }
    final correction = Correction.tryParse(decoded);
    if (correction == null) continue;
    dated.add((issue['created_at'] as String? ?? '', correction));
  }
  dated.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final d in dated) d.$2];
}

/// Reads the corrections from [repo] ("owner/name"). Null when GitHub could
/// not be asked, so the caller can fall back on the last list it saved.
Future<List<Correction>?> fetchCorrections(
  http.Client client,
  String repo, {
  String? token,
}) async {
  if (!RegExp(r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$').hasMatch(repo)) return null;
  final all = <dynamic>[];
  try {
    for (var page = 1; page <= 5; page++) {
      final res = await client
          .get(
            Uri.https('api.github.com', '/repos/$repo/issues', {
              'state': 'all',
              'per_page': '100',
              'page': '$page',
            }),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'zed-specials-feed-builder',
              if (token != null && token.isNotEmpty)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      all.addAll(list);
      if (list.length < 100) break;
    }
  } catch (_) {
    return null;
  }
  return parseCorrectionIssues(all);
}
