import 'package:flutter/material.dart';

import 'src/app_state.dart';
import 'src/screens/compare_screen.dart';
import 'src/screens/specials_screen.dart';
import 'src/screens/watchlist_screen.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState()..start();
  runApp(ZedSpecialsApp(state: state));
}

class ZedSpecialsApp extends StatelessWidget {
  const ZedSpecialsApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Zed Specials',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const _Shell(),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back to the app after a while: look for new leaflets.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppScope.read(context).refreshIfStale();
    }
  }

  static const _screens = [
    SpecialsScreen(),
    CompareScreen(),
    WatchlistScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);

    // Surface one-off messages (refresh results) as a snackbar.
    final notice = s.notice;
    if (notice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final n = s.takeNotice();
        if (n != null && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(n)));
        }
      });
    }

    if (s.loading) {
      return Scaffold(
        body: Center(
          child: Text(
            'Zed Specials',
            style: display(context, size: 30, color: p.ink),
          ),
        ),
      );
    }

    final hits = s.watchHits;
    Widget watchIcon(IconData icon) => hits == 0
        ? Icon(icon)
        : Badge(
            label: Text('$hits'),
            backgroundColor: p.urgent,
            textColor: Colors.white,
            child: Icon(icon),
          );

    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(index: _tab, children: _screens);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.85,
              minWidth: 88,
              leading: Padding(
                padding: const EdgeInsets.only(top: 20, bottom: 12),
                child: _Wordmark(),
              ),
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.sell_outlined),
                  selectedIcon: Icon(Icons.sell_rounded),
                  label: Text('Specials'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.balance_outlined),
                  selectedIcon: Icon(Icons.balance_rounded),
                  label: Text('Compare'),
                ),
                NavigationRailDestination(
                  icon: watchIcon(Icons.visibility_outlined),
                  selectedIcon: watchIcon(Icons.visibility_rounded),
                  label: const Text('Watchlist'),
                ),
              ],
            ),
            VerticalDivider(width: 1, color: p.line),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.sell_outlined),
              selectedIcon: Icon(Icons.sell_rounded),
              label: 'Specials',
            ),
            const NavigationDestination(
              icon: Icon(Icons.balance_outlined),
              selectedIcon: Icon(Icons.balance_rounded),
              label: 'Compare',
            ),
            NavigationDestination(
              icon: watchIcon(Icons.visibility_outlined),
              selectedIcon: watchIcon(Icons.visibility_rounded),
              label: 'Watchlist',
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's mark on wide screens: a small price tag with a Z.
class _Wordmark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: 'Zed Specials',
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.tag,
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
        ),
        child: ExcludeSemantics(
          child: Text('Z', style: display(context, size: 26, color: p.onTag)),
        ),
      ),
    );
  }
}
