import 'package:flutter/material.dart';
import '../widgets/app_theme.dart';

class _Module {
  final String name;
  final IconData icon;
  final Color color;
  final bool ready;
  const _Module(this.name, this.icon, this.color, {this.ready = false});
}

const _readyModules = <String>{'ক্যাশবুক', 'ভল্ট', 'প্রজেক্ট', 'সেটিংস'};

const _modules = [
  _Module('ক্যাশবুক', Icons.account_balance_wallet, Color(0xFF4F46E5), ready: true),
  _Module('ভল্ট', Icons.lock, Color(0xFF15803D), ready: true),
  _Module('প্রজেক্ট', Icons.folder, Color(0xFFB45309), ready: true),
  _Module('পরিবার ও রুটিন', Icons.family_restroom, Color(0xFFDC4C4C)),
  _Module('পড়াশোনা', Icons.school, Color(0xFF38BDF8)),
  _Module('রিমাইন্ডার ও বিল', Icons.notifications_active, Color(0xFFFBBF24)),
  _Module('ডকুমেন্ট ও তথ্য', Icons.folder_special, Color(0xFF4ADE80)),
  _Module('প্রোডাক্টিভিটি', Icons.checklist, Color(0xFFA78BFA)),
  _Module('কৃষি/সম্পত্তি', Icons.agriculture, Color(0xFF84CC16)),
  _Module('ঋণ-দেনা', Icons.handshake, Color(0xFFF472B6)),
  _Module('সামাজিক', Icons.groups, Color(0xFF38BDF8)),
  _Module('ব্যবসা', Icons.storefront, Color(0xFFF97316)),
  _Module('সেটিংস', Icons.settings, Color(0xFF9A9AA5), ready: true),
];

class LifeHomeScreen extends StatelessWidget {
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenVault;
  final VoidCallback onOpenCashbook;
  final VoidCallback onOpenSettings;

  const LifeHomeScreen({
    super.key,
    required this.onOpenProjects,
    required this.onOpenVault,
    required this.onOpenCashbook,
    required this.onOpenSettings,
  });

  void _tap(BuildContext context, _Module m) {
    switch (m.name) {
      case 'প্রজেক্ট': onOpenProjects(); return;
      case 'ভল্ট': onOpenVault(); return;
      case 'ক্যাশবুক': onOpenCashbook(); return;
      case 'সেটিংস': onOpenSettings(); return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('🚧 ${m.name}'),
        content: const Text('এই মডিউলটা এখনো তৈরি হচ্ছে — শীঘ্রই আসছে!'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ঠিক আছে'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('আমার জীবন', style: AppTheme.display(size: 24)),
                const SizedBox(height: 4),
                Text('জীবনকে সাজাও, এক অ্যাপে', style: AppTheme.caption(size: 13)),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final m = _modules[i];
                  return _ModuleCard(module: m, onTap: () => _tap(context, m));
                },
                childCount: _modules.length,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final _Module module;
  final VoidCallback onTap;
  const _ModuleCard({required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bg2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: module.ready ? module.color.withOpacity(0.15) : AppTheme.bg3,
                  shape: BoxShape.circle,
                ),
                child: Icon(module.icon, color: module.ready ? module.color : AppTheme.textMuted, size: 22),
              ),
              if (!module.ready)
                Positioned(
                  right: -2, top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: AppTheme.bg2, shape: BoxShape.circle),
                    child: Icon(Icons.lock_clock, size: 13, color: AppTheme.textMuted),
                  ),
                ),
            ]),
            const SizedBox(height: 8),
            Text(module.name,
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: module.ready ? AppTheme.textPrimary : AppTheme.textMuted)),
            if (!module.ready)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('শীঘ্রই', style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
              ),
          ]),
        ),
      ),
    );
  }
}
