import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../widgets/app_theme.dart';
import '../services/widget_service.dart';
import '../services/auth_service.dart';
import '../cashbook/services/cashbook_service.dart';
import '../cashbook/services/cashbook_notification_service.dart';
import 'dashboard_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'share_intake_screen.dart';
import 'vault_screen.dart';
import '../cashbook/screens/cashbook_screen.dart';
import 'life_home_screen.dart';

/// Top-level shell: bottom navigation between Projects / Search / Vault /
/// Settings. Vault is a first-class destination of its own — a password
/// manager is a fundamentally different tool from the project/idea
/// manager the rest of this app is, so it doesn't belong tucked inside
/// Settings as just another toggle.
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

  StreamSubscription? _shareSub;
  StreamSubscription? _overlaySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initShareListener();
    _initOverlayListener();
  }

  /// Listens for signals sent from the floating bubble (see
  /// overlay_bubble.dart's shareData() calls). This is the actual fix
  /// for edits/adds made via the bubble not showing up in the main app —
  /// an overlay window can float *over* the app without ever properly
  /// backgrounding it, so the resume-based refresh below sometimes never
  /// fires at all. This listener refreshes immediately instead of
  /// waiting for a pause/resume cycle that may not happen.
  void _initOverlayListener() {
    try {
      _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) {
        if (event == 'idea_added' || event == 'idea_updated') {
          if (mounted) setState(() => _dashboardGen++);
        }
      });
    } catch (_) {
      // If the plugin's listener isn't available for some reason, the
      // resume-based refresh below still covers most real-world cases.
    }
  }

  /// "Share TO My Manager" — content shared in from other apps (browser,
  /// gallery, WhatsApp, etc.) arrives here, whether the app was already
  /// open or was launched fresh by the share itself.
  void _initShareListener() {
    try {
      // While the app is already running.
      _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (files) => _handleSharedFiles(files),
        onError: (_) {},
      );
      // Cold start via a share.
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        if (files.isNotEmpty) _handleSharedFiles(files);
      }).catchError((_) {});
    } catch (_) {
      // If the share-intent plugin isn't available for any reason, the
      // rest of the app should still work fine without it.
    }
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ShareIntakeScreen(sharedFiles: files),
    )).then((_) => setState(() => _dashboardGen++));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _overlaySub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() => _dashboardGen++);
      CashbookNotificationService.refresh();
    }
    // Refresh the home screen widget whenever the app leaves the
    // foreground — covers ideas added/edited/completed during the
    // session, right before the person goes back to their home screen.
    if (state == AppLifecycleState.paused) {
      WidgetService.update();
    }
  }

  /// Vault isn't one of the swappable IndexedStack tabs — tapping it
  /// authenticates, then pushes it as a full route on top of everything
  /// (same as the auto-lock-on-pause behavior it already has when opened
  /// this way). The bottom nav's selected tab underneath doesn't change,
  /// so returning from the vault lands back exactly where you were.
  Future<void> _openVault() async {
    final canAuth = await AuthService.canAuthenticate();
    if (!canAuth) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar( SnackBar(
        content: Text('ডিভাইসে ফিঙ্গারপ্রিন্ট/PIN সেট করা নেই'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }
    final ok = await AuthService.authenticate(reason: 'ভল্ট খুলতে যাচাই করো');
    if (ok && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const VaultScreen()));
    }
  }

  /// Cashbook follows the exact same "authenticate, then push as its own
  /// route" pattern as the Vault above — the lock can be turned off from
  /// inside the Cashbook's own settings if the user doesn't want it.
  Future<void> _openCashbook() async {
    if (!CashbookService.lockEnabled) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CashbookScreen()));
      return;
    }
    final canAuth = await AuthService.canAuthenticate();
    if (!canAuth) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ডিভাইসে ফিঙ্গারপ্রিন্ট/PIN সেট করা নেই'),
        backgroundColor: AppTheme.red,
      ));
      return;
    }
    final ok = await AuthService.authenticate(reason: 'ক্যাশবুক খুলতে যাচাই করো');
    if (ok && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CashbookScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      LifeHomeScreen(
        onOpenProjects: () => setState(() => _index = 1),
        onOpenVault: _openVault,
        onOpenCashbook: _openCashbook,
        onOpenSettings: () => setState(() => _index = 3),
      ),
      DashboardScreen(key: ValueKey(_dashboardGen), onThemeToggle: widget.onThemeToggle),
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
          onDestinationSelected: (i) {
            if (i == 3) {
              // Vault's position in the destinations list below — a tap
              // here never changes _index, it just opens the vault as
              // its own route.
              _openVault();
              return;
            }
            if (i == 4) {
              // Cashbook, same non-tab treatment as Vault right above it.
              _openCashbook();
              return;
            }
            // Settings shifted from index 2 to index 5 to make room for
            // Home, Vault and Cashbook, so map the NavigationBar's index
            // back to the tabs list (Home=0, Projects=1, Search=2, Settings=3).
            setState(() => _index = i == 5 ? 3 : i);
          },
          height: 60,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'হোম'),
            NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: 'প্রজেক্ট'),
            NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'খোঁজো'),
            NavigationDestination(
                icon: Icon(Icons.lock_outline),
                selectedIcon: Icon(Icons.lock),
                label: 'ভল্ট'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'ক্যাশবুক'),
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
