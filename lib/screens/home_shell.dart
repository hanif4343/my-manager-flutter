import 'package:flutter/material.dart';
import '../widgets/app_theme.dart';
import 'dashboard_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Top-level shell: bottom navigation between Projects / Search / Settings.
/// Moving these into a bottom bar means the Dashboard's AppBar no longer
/// needs to carry Search and Settings icons — less clutter, better thumb
/// reach, and each section stays out of the way until you actually tap it.
class HomeShell extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const HomeShell({super.key, required this.onThemeToggle});
  @override State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  // Bumped whenever the app comes back to the foreground, so the Dashboard
  // tab is rebuilt from scratch and re-reads the DB — needed because an
  // idea can now be added from the floating bubble while the app was in
  // the background, and the tab wouldn't otherwise know to refresh.
  int _dashboardGen = 0;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _dashboardGen++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardScreen(key: ValueKey(_dashboardGen)),
      const SearchScreen(),
      SettingsScreen(onThemeToggle: widget.onThemeToggle),
    ];

    return Scaffold(
      backgroundColor: AppTheme.bg,
      // IndexedStack keeps each tab's state (scroll position, search
      // query, etc.) alive when switching, instead of rebuilding it.
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: AppTheme.bg2,
          indicatorColor: AppTheme.accent.withOpacity(0.15),
          labelTextStyle: MaterialStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(MaterialState.selected)
                  ? AppTheme.accent : AppTheme.textMuted)),
          iconTheme: MaterialStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(MaterialState.selected)
                  ? AppTheme.accent : AppTheme.textMuted)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          height: 60,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'প্রজেক্ট'),
            NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'খোঁজো'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'সেটিংস'),
          ],
        ),
      ),
    );
  }
}
