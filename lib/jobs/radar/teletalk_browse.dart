import 'package:flutter/material.dart';
import '../../reminder/models/reminder.dart' show bn;
import '../../widgets/app_theme.dart';
import '../models/job_models.dart';
import '../services/app_launcher.dart';
import '../services/job_service.dart';
import 'engine/bn_util.dart' show fmtDateBn, todayDhaka, daysBetween;
import 'engine/match_engine.dart' show postRelevance;
import 'engine/teletalk_source.dart';
import 'radar_service.dart';

/// Teletalk AllJobs-এর মতো তালিকা: সব চলমান সরকারি চাকরি, সার্চ ও ফিল্টারসহ।
/// তোমার টার্গেট পদগুলোতে 🎯 চিহ্ন থাকে।
class TeletalkBrowse extends StatefulWidget {
  final VoidCallback onSaved;
  const TeletalkBrowse({super.key, required this.onSaved});
  @override
  State<TeletalkBrowse> createState() => _TeletalkBrowseState();
}

enum _Filter { all, mine, soon3, soon7, newest }

class _TeletalkBrowseState extends State<TeletalkBrowse> {
  List<TeletalkJob> _jobs = [];
  Set<String> _saved = {};
  bool _loading = false;
  String? _error;
  _Filter _filter = _Filter.all;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _jobs = RadarService.teletalkAll();
    _loadSaved();
    if (_jobs.isEmpty) _refresh();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final list = await JobService.circulars();
    if (mounted) setState(() => _saved = list.map((c) => c.url).where((u) => u.isNotEmpty).toSet());
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final j = await fetchTeletalkJobs();
      await RadarService.saveTeletalkAll(j);
      if (mounted) setState(() { _jobs = j; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Teletalk থেকে আনা যায়নি — ইন্টারনেট দেখো'; });
    }
  }

  String _key(TeletalkJob j) => '${j.applyUrl}#${j.jobId}';

  bool _mine(TeletalkJob j) => postRelevance('${j.titleBn} ${j.titleEn}', RadarService.profile()) == 'yes';

  int? _daysLeft(TeletalkJob j) => j.deadline == null ? null : daysBetween(todayDhaka(), j.deadline!);

  Future<void> _watch(TeletalkJob j) async {
    final org = j.orgNameBn.isNotEmpty ? j.orgNameBn : j.orgName;
    final title = j.titleBn.isNotEmpty ? j.titleBn : j.titleEn;
    final note = StringBuffer('Teletalk ${j.jobId}');
    if (j.published != null) note.write('\nআবেদন শুরু: ${fmtDateBn(j.published!)}');
    note.write('\nশর্ত (বয়স/শিক্ষা/টাইপিং) আবেদনের সাইটের বিজ্ঞপ্তিতে দেখো');
    await JobService.saveCircular(Circular(
      title: '$org — $title',
      org: org,
      post: title,
      deadline: j.deadline == null ? null : DateTime(j.deadline!.year, j.deadline!.month, j.deadline!.day),
      fee: 0,
      url: _key(j),
      note: note.toString(),
    ));
    widget.onSaved();
    await _loadSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('সার্কুলার ট্যাবে যোগ হয়েছে — শেষ তারিখের রিমাইন্ডারও সেট হয়েছে')));
    }
  }

  List<TeletalkJob> _visible() {
    final q = _q.text.trim().toLowerCase();
    var list = _jobs.where((j) {
      final d = _daysLeft(j);
      if (d != null && d < 0) return false;
      if (q.isNotEmpty) {
        final hay = '${j.titleBn} ${j.titleEn} ${j.orgName} ${j.orgNameBn} ${j.shortName}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      switch (_filter) {
        case _Filter.mine:
          return _mine(j);
        case _Filter.soon3:
          return d != null && d <= 3;
        case _Filter.soon7:
          return d != null && d <= 7;
        case _Filter.newest:
        case _Filter.all:
          return true;
      }
    }).toList();
    if (_filter == _Filter.soon3 || _filter == _Filter.soon7) {
      list.sort((a, b) => (_daysLeft(a) ?? 999).compareTo(_daysLeft(b) ?? 999));
    }
    return list; // API ইতিমধ্যে নতুন-আগে ক্রমে আসে
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible();
    final mineCount = _jobs.where(_mine).length;
    final at = RadarService.teletalkSavedAt();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: 'পদ / প্রতিষ্ঠান / keyword খোঁজো',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          IconButton(
            tooltip: 'রিফ্রেশ',
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: _refresh,
          ),
        ]),
      ),
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _fchip('সব (${bn(_jobs.length)})', _Filter.all),
            _fchip('🎯 আমার পদ (${bn(mineCount)})', _Filter.mine),
            _fchip('৩ দিনে শেষ', _Filter.soon3),
            _fchip('৭ দিনে শেষ', _Filter.soon7),
          ],
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('⚠️ $_error', style: TextStyle(color: AppTheme.red, fontSize: 12.5)),
        ),
      if (at != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('তালিকা আনা হয়েছে: ${bn(at.day)}/${bn(at.month)} ${bn(at.hour.toString().padLeft(2, '0'))}:${bn(at.minute.toString().padLeft(2, '0'))} · উৎস: alljobs.teletalk.com.bd',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ),
        ),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text(_loading ? 'তালিকা আনা হচ্ছে…' : 'কিছু পাওয়া যায়নি',
                    style: TextStyle(color: AppTheme.textMuted)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                itemCount: list.length,
                itemBuilder: (_, i) => _card(list[i]),
              ),
      ),
    ]);
  }

  Widget _fchip(String label, _Filter f) => Padding(
        padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12.5)),
          selected: _filter == f,
          onSelected: (_) => setState(() => _filter = f),
        ),
      );

  Color _urgency(int d) => d <= 3 ? AppTheme.red : (d <= 7 ? AppTheme.yellow : AppTheme.green);

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _card(TeletalkJob j) {
    final d = _daysLeft(j);
    final mine = _mine(j);
    final saved = _saved.contains(_key(j));
    final org = j.orgNameBn.isNotEmpty ? j.orgNameBn : j.orgName;
    final notStarted = j.published != null && daysBetween(todayDhaka(), j.published!) > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: mine ? AppTheme.green.withOpacity(0.6) : AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (mine) _chip('🎯 আমার পদ', AppTheme.green),
            if (d != null) _chip(d == 0 ? 'আজই শেষ' : 'আর ${bn(d)} দিন', _urgency(d)),
            if (notStarted) _chip('আবেদন শুরু ${fmtDateBn(j.published!)}', AppTheme.accent),
          ]),
          const SizedBox(height: 8),
          Text(j.titleBn.isNotEmpty ? j.titleBn : j.titleEn,
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          if (j.titleBn.isNotEmpty && j.titleEn.isNotEmpty)
            Text(j.titleEn, style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(org, style: TextStyle(color: AppTheme.textMuted, fontSize: 12.5)),
          const SizedBox(height: 6),
          Text(
            [
              if (j.vacancy != null) 'পদ: ${bn(j.vacancy!)}টি',
              if (j.deadline != null) 'শেষ: ${fmtDateBn(j.deadline!)}',
              j.jobId,
            ].join('  ·  '),
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            saved
                ? _chip('✔ নজরে আছে', AppTheme.textSecondary)
                : FilledButton.tonal(onPressed: () => _watch(j), child: const Text('নজরে নাও')),
            TextButton(
              onPressed: () async {
                final ok = await AppLauncher.openUrl(j.applyUrl);
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('লিংক খোলা যায়নি')));
                }
              },
              child: const Text('🔗 আবেদন/বিস্তারিত'),
            ),
          ]),
        ]),
      ),
    );
  }
}
