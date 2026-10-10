import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../services/spending_guard.dart';

const _red = Color(0xFFDC2626);
const _amber = Color(0xFFF59E0B);

/// ক্যাশবুকের উপরের খরচ-প্রহরী কার্ড। সব ঠিক থাকলে ছোট সবুজ লাইন; জরুরি খরচের টাকা
/// কমে এলে (আবশ্যিক খরচের কাছাকাছি গেলে) বড়, লাল, স্পন্দিত কার্ড — চোখ এড়ানো কঠিন।
class SpendingGuardCard extends StatefulWidget {
  /// "আবশ্যিক খরচ দেখো" বাটনে ট্যাপ করলে আবশ্যিক খরচ ট্যাবে যেতে।
  final VoidCallback? onOpenEssentials;
  const SpendingGuardCard({super.key, this.onOpenEssentials});
  @override State<SpendingGuardCard> createState() => _SpendingGuardCardState();
}

class _SpendingGuardCardState extends State<SpendingGuardCard> with SingleTickerProviderStateMixin {
  GuardReport? _r;
  bool _open = false;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    SpendingGuard.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SpendingGuard.changes.removeListener(_load);
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await SpendingGuard.assess();
      if (mounted) setState(() => _r = r);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    if (r == null) return const SizedBox.shrink();
    if (!SpendingGuard.enabled) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => showGuardSettings(context),
            icon: const Icon(Icons.shield_outlined, size: 16),
            label: const Text('খরচ-প্রহরী বন্ধ — চালু করো', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
    }
    return r.level == GuardLevel.ok ? _calm(r) : _alarm(r);
  }

  // ───────────── সব ঠিক ─────────────

  Widget _calm(GuardReport r) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Material(
        color: AppTheme.green.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.shield_rounded, size: 18, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.essentialsLine,
                      maxLines: _open ? 4 : 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.tune_rounded, size: 18, color: AppTheme.textMuted),
                  onPressed: () => showGuardSettings(context),
                ),
              ]),
              if (_open)
                for (final l in r.detailLines)
                  Padding(
                    padding: const EdgeInsets.only(left: 26, top: 2),
                    child: Text('• $l', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ),
            ]),
          ),
        ),
      ),
    );
  }

  // ───────────── বড় লাল সতর্কতা ─────────────

  Widget _alarm(GuardReport r) {
    final danger = r.level == GuardLevel.danger;
    final base = danger ? _red : _amber;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [base, Color.lerp(base, Colors.black, 0.28)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: base.withOpacity(0.25 + 0.35 * _pulse.value),
                blurRadius: 10 + 14 * _pulse.value,
                spreadRadius: 1 + 2 * _pulse.value,
              ),
            ],
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.headline,
                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, height: 1.25)),
            const SizedBox(height: 8),
            Text(r.essentialsLine,
                style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4)),
            if (r.detailLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final l in r.detailLines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text('• $l', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12.5, height: 1.35)),
                ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.22), borderRadius: BorderRadius.circular(10)),
              child: Text(
                danger
                    ? 'টাকা কম খরচ করুন — আবশ্যিক কাজ আগে করুন। অকারণ খরচ আজ বন্ধ।'
                    : 'সাবধান! টাকা কম খরচ করুন — আবশ্যিক খরচ আগে মেটান। অযাচিত খরচ এখনই থামান।',
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              if (widget.onOpenEssentials != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: widget.onOpenEssentials,
                  child: const Text('আবশ্যিক খরচ দেখো'),
                ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: () => showGuardSettings(context),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('সেটিংস'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ═════════════ খরচ লেখার সময়ের "থামো" ডায়ালগ ═════════════

/// নতুন খরচ সেভের আগে: এটা করলে অবস্থা কী দাঁড়াবে দেখিয়ে লাল ডায়ালগ। ৩ সেকেন্ড ভাবার সুযোগ,
/// তারপর "দরকারি, সেভ করো" চালু হয়। true = এগোও, false/null = বাদ।
Future<bool?> showSpendingNudge(BuildContext context, GuardReport r, double amount) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NudgeDialog(r: r, amount: amount),
  );
}

class _NudgeDialog extends StatefulWidget {
  final GuardReport r;
  final double amount;
  const _NudgeDialog({required this.r, required this.amount});
  @override State<_NudgeDialog> createState() => _NudgeDialogState();
}

class _NudgeDialogState extends State<_NudgeDialog> {
  int _left = 3;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() async {
    while (_left > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() => _left--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final danger = r.level == GuardLevel.danger;
    final base = danger ? _red : _amber;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [base, Color.lerp(base, Colors.black, 0.3)!],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✋ থামো!', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('৳${bn(widget.amount.round())} খরচ কি এখনই সত্যিই দরকার?',
              style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.3)),
          const SizedBox(height: 12),
          Text(r.headline, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('এই খরচের পরে: ${r.essentialsLine}',
              style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 13, height: 1.4)),
          for (final l in r.detailLines.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('• $l', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12.5, height: 1.35)),
            ),
          const SizedBox(height: 14),
          const Text('একটু ভাবো: এটা না করলে কি চলে? পরে করা যায়?',
              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: base, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('না, বাদ দিই ✓', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _left > 0 ? null : () => Navigator.pop(context, true),
              child: Text(_left > 0 ? '⏳ ${bn(_left)} সেকেন্ড ভাবো...' : 'দরকারি, তবুও সেভ করো',
                  style: TextStyle(color: _left > 0 ? Colors.white54 : Colors.white, fontSize: 13.5)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═════════════ সেটিংস ═════════════

Future<void> showGuardSettings(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bg2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => const _GuardSettingsSheet(),
  );
}

class _GuardSettingsSheet extends StatefulWidget {
  const _GuardSettingsSheet();
  @override State<_GuardSettingsSheet> createState() => _GuardSettingsSheetState();
}

class _GuardSettingsSheetState extends State<_GuardSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final on = SpendingGuard.enabled;
    final margin = SpendingGuard.marginPct;
    final nag = SpendingGuard.nagMinutes;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('খরচ-প্রহরী', style: TextStyle(color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'ক্যাশবুকে যত টাকা আছে তা থেকে বাকি আবশ্যিক খরচ মেটানোর পরে হাতে কত থাকবে হিসাব করে। '
            'আবশ্যিক খরচের কাছাকাছি গেলে লাল সতর্কতা দেয়: "টাকা কম খরচ করুন, আবশ্যিক কাজ আগে করুন"।',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5, height: 1.45),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            activeColor: AppTheme.accent,
            title: Text('চালু', style: TextStyle(color: AppTheme.textPrimary)),
            onChanged: (v) async {
              await SpendingGuard.saveSettings(on: v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 6),
          Text('কখন "কাছাকাছি" ধরবে', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 2),
          Text('আবশ্যিক খরচ মেটানোর পর হাতে থাকা টাকা আবশ্যিক খরচের এই % এর কম হলে',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final v in [20, 30, 50, 80])
              ChoiceChip(
                label: Text('${bn(v)}%'),
                selected: margin == v,
                showCheckmark: false,
                onSelected: (_) async {
                  await SpendingGuard.saveSettings(margin: v);
                  if (mounted) setState(() {});
                },
              ),
          ]),
          const SizedBox(height: 14),
          Text('নোটিফিকেশনে বারবার বলার ব্যবধান', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const SizedBox(height: 2),
          Text('সকাল ৮টা–রাত ১০টায়, সতর্ক অবস্থায়। জরুরি (লাল) অবস্থায় এর অর্ধেক সময়ে।',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final v in [60, 120, 180, 360])
              ChoiceChip(
                label: Text(v < 120 ? '${bn(v)} মি' : '${bn(v ~/ 60)} ঘণ্টা'),
                selected: nag == v,
                showCheckmark: false,
                onSelected: (_) async {
                  await SpendingGuard.saveSettings(nag: v);
                  if (mounted) setState(() {});
                },
              ),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await SpendingGuard.nudgeIfNeeded(force: true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('পরীক্ষামূলক নোটিফিকেশন পাঠানো হয়েছে')));
              }
            },
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('এখনই একটা নোটিফিকেশন পরীক্ষা করো'),
          ),
        ]),
      ),
    );
  }
}
