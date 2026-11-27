import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'catalogue_viewer.dart' show PriceRow;
import 'item_sheet.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final term = _input.text.trim();
    if (term.isEmpty) {
      _focus.requestFocus();
      return;
    }
    final s = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    if (s.isWatched(term)) {
      messenger.showSnackBar(
        SnackBar(content: Text('"$term" is already on your watchlist.')),
      );
      return;
    }
    await s.watch(term);
    _input.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 720;

    // Items on special first.
    final terms = [...s.watchlist];
    final matches = {for (final t in terms) t: s.watchMatches(t)};
    terms.sort((a, b) {
      final ha = matches[a]!.isNotEmpty ? 0 : 1;
      final hb = matches[b]!.isNotEmpty ? 0 : 1;
      return ha.compareTo(hb);
    });
    final onSpecial = terms.where((t) => matches[t]!.isNotEmpty).length;

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.zero,
      children: [
        SafeArea(
          bottom: false,
          child: ContentWidth(
            child: Padding(
              padding: EdgeInsets.only(top: wide ? 36 : 20, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      terms.isEmpty
                          ? 'What do you buy often?'
                          : onSpecial == 0
                          ? 'Nothing you watch is on special.'
                          : '$onSpecial of your ${terms.length} item${terms.length == 1 ? ' is' : 's are'} on special.',
                      style: display(context, size: wide ? 46 : 34),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _add(),
                            decoration: const InputDecoration(
                              hintText: 'Add an item, like sugar',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(onPressed: _add, child: const Text('Watch')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (terms.isEmpty)
          ContentWidth(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text(
                  'Add the things you buy most, like cooking oil, sugar or '
                  'mealie meal. Whenever a leaflet has one on special, it '
                  'appears here with the lowest price first.',
                  style: TextStyle(fontSize: 15, color: p.inkSoft, height: 1.45),
                ),
              ),
            ),
          )
        else
          ContentWidth(
            child: Column(
              children: [
                for (final term in terms)
                  _WatchCard(
                    term: term,
                    matches: matches[term]!,
                    onRemove: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await s.unwatch(term);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Stopped watching "$term".'),
                          action: SnackBarAction(
                            label: 'Undo',
                            textColor: p.tag,
                            onPressed: () => s.watch(term),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _WatchCard extends StatefulWidget {
  const _WatchCard({
    required this.term,
    required this.matches,
    required this.onRemove,
  });

  final String term;
  final List<DealItem> matches;
  final VoidCallback onRemove;

  @override
  State<_WatchCard> createState() => _WatchCardState();
}

class _WatchCardState extends State<_WatchCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final matches = widget.matches;
    final shown = _all ? matches : matches.take(3).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.term,
                  style: display(context, size: 19, weight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Stop watching ${widget.term}',
                onPressed: widget.onRemove,
                icon: Icon(Icons.close_rounded, color: p.inkSoft),
              ),
            ],
          ),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10, right: 10),
              child: Text(
                'Not on special this week.',
                style: TextStyle(fontSize: 14.5, color: p.inkSoft),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var k = 0; k < shown.length; k++) ...[
                    if (k > 0) const Divider(),
                    PriceRow(
                      item: shown[k],
                      best: k == 0,
                      onTap: () => showItemSheet(context, shown[k]),
                    ),
                  ],
                  if (matches.length > 3)
                    TextButton(
                      onPressed: () => setState(() => _all = !_all),
                      child: Text(
                        _all
                            ? 'Show fewer'
                            : 'Show all ${matches.length} prices',
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
