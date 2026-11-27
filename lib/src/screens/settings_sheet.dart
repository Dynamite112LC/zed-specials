import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalogue_viewer.dart';

void showSettingsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  TextEditingController? _url;
  bool _saving = false;

  @override
  void dispose() {
    _url?.dispose();
    super.dispose();
  }

  String _ago(DateTime t, DateTime now) {
    if (t.millisecondsSinceEpoch == 0) return 'never';
    final d = now.difference(t);
    if (d.inMinutes < 60) return 'less than an hour ago';
    if (d.inHours < 24) return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago, on ${shortDate(t)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = AppScope.of(context);
    final url = _url ??= TextEditingController(text: s.feedUrl);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SectionTitle('Settings'),
            const SizedBox(height: 20),
            Text(
              'Where specials come from',
              style: display(context, size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Leaflets are collected from each shop\'s own Zambian specials '
              'page. Last collected ${_ago(s.feed.generatedAt, s.now)}.',
              style: TextStyle(fontSize: 14.5, color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 8),
            for (final r in Retailer.all)
              InkWell(
                onTap: () => openOnShopSite(context, r.website),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(child: RetailerMark(r, fontSize: 15)),
                      Text(
                        'Open specials page',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Feed address',
              style: display(context, size: 17, weight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'The web address of a hosted feed.json. With an address set, '
              'the app downloads new specials when it opens and when you '
              'pull down to refresh. Leave it empty to use the specials '
              'saved with the app.',
              style: TextStyle(fontSize: 14.5, color: p.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'https://example.com/specials/feed.json',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _saving = true);
                        await s.setFeedUrl(url.text);
                        final notice = s.takeNotice();
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(notice ?? 'Feed address saved.'),
                          ),
                        );
                      },
                child: Text(_saving ? 'Saving' : 'Save feed address'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
