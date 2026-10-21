import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/jobs/radar/engine/match_engine.dart';
import 'package:my_manager/jobs/radar/engine/teletalk_radar.dart';
import 'package:my_manager/jobs/radar/engine/teletalk_source.dart';

// alljobs.teletalk.com.bd/api/v1/published-jobs/search থেকে পাওয়া আসল এন্ট্রির নমুনা।
final profile = RadarProfile(
  dob: DateTime.utc(1999, 1, 1), eduRank: 4, eduLabel: 'স্নাতক (পাস কোর্স, ৩ বছর)', typingBn: 20, typingEn: 20,
  targetKeywords: const [
    r'কম্পিউটার\s*অপারেটর', r'কম্পিউটার\s*মুদ্রাক্ষরিক', r'ডাটা\s*এন্ট্রি', r'ডেটা\s*এন্ট্রি',
    r'ডাটা\s*অপারেটর', r'ডেটা\s*অপারেটর', r'অফিস\s*সহায়ক\s*[-–]?\s*কাম',
    r'computer\s*operator', r'data\s*entry', r'computer\s*typist',
  ],
  excludeKeywords: const ['সাঁট', 'সীট', 'শর্টহ্যান্ড', 'stenograph', 'stenotyp', 'shorthand'],
);

Map<String, dynamic> job(String id, String en, String bn, String vac, {String site = 'https://tax6.teletalk.com.bd/'}) => {
      'job_primary_id': int.parse(id.replaceAll('GJOB', '')),
      'organization_id': 1165,
      'job_id': id,
      'job_title': en,
      'job_title_bn': bn,
      'vacancy': vac,
      'application_site_url': site,
      'published_date': '2026-10-25T04:00:00.000Z',
      'deadline_date': '2026-11-14T10:00:00.000Z',
      'org_name': 'Office of The Commissioner of Taxes Taxes Zone-6, Dhaka(TAX6)',
      'org_name_bn': 'কর কমিশনারের কার্যালয় কর অঞ্চল-৬, ঢাকা',
      'short_name': 'TAX6',
    };

void main() {
  final jobs = [
    job('GJOB15031', 'Office Support Staff', 'অফিস সহায়ক', '11', site: 'http://dcnoakhali.teletalk.com.bd/'),
    job('GJOB15028', 'Office Assistant-Cum-Computer Typist', 'অফিস সহকারী-কাম-কম্পিউটার মুদ্রাক্ষরিক', '10'),
    job('GJOB15027', 'Stenotypist-Cum-Computer Operator', 'সাঁটমুদ্রাক্ষরিক-কাম-কম্পিউটার অপারেটর', '09'),
    job('GJOB15026', 'Stenographer Cum-Computer Operator', 'সাঁটলিপিকার কাম-কম্পিউটার অপারেটর', '02'),
    job('GJOB15025', 'Head Assistant', 'প্রধান সহকারী', '08'),
    job('GJOB15024', 'Computer Operator', 'কম্পিউটার অপারেটর', '01'),
    job('GJOB15016', 'Sub Assistant Engineer(Computer/IT)', 'উপ-সহকারী প্রকৌশলী (কম্পিউটার/আইটি)', '08', site: 'http://bogmc.teletalk.com.bd/'),
  ].map(TeletalkJob.fromMap).toList();

  test('তারিখ: UTC → বাংলাদেশের তারিখ, পদসংখ্যা সংখ্যায়', () {
    final j = jobs[1];
    expect(j.deadline, DateTime.utc(2026, 11, 14));
    expect(j.published, DateTime.utc(2026, 10, 25));
    expect(j.vacancy, 10);
  });

  test('শুধু টার্গেট পদ; সাঁটলিপি/অন্য পদ বাদ; একই প্রতিষ্ঠানের পদ এক কার্ডে', () {
    final items = teletalkItems(jobs, profile, now: DateTime.utc(2026, 10, 21, 6));
    expect(items.length, 1);
    final it = items.first;
    expect(it.posts.length, 2);
    expect(it.posts.map((p) => p.title).toSet(), {'অফিস সহকারী-কাম-কম্পিউটার মুদ্রাক্ষরিক', 'কম্পিউটার অপারেটর'});
    expect(it.verdict, 'warn');
    expect(it.url, 'https://alljobs.teletalk.com.bd/jobs/government/1165?jobId=15024#teletalk');
    expect(it.deadline, DateTime(2026, 11, 14));
    expect(it.org.contains('কর অঞ্চল-৬'), true);
    // আবেদন এখনো শুরু হয়নি — সেটা জানানো হয়
    expect(it.posts.first.checks.any((c) => c.key == 'start'), true);
  });

  test('মেয়াদ শেষ হলে বাদ', () {
    expect(teletalkItems(jobs, profile, now: DateTime.utc(2026, 11, 20, 6)), isEmpty);
  });

  test('বিস্তারিত API-র বয়সসীমা: ১৮–৩২ → ✅; সীমা ২৫ → কার্ডে আসে না', () {
    final ok = {for (final j in jobs) j.primaryId: const TeletalkDetail(minAge: 18, maxAge: 32, adNo: '1-E-8/2026')};
    final items = teletalkItems(jobs, profile, now: DateTime.utc(2026, 10, 21, 6), details: ok);
    final age = items.first.posts.first.checks.firstWhere((c) => c.key == 'age');
    expect(age.s, 'ok');
    expect(items.first.posts.first.checks.any((c) => c.key == 'adno'), true);

    final tight = {for (final j in jobs) j.primaryId: const TeletalkDetail(minAge: 18, maxAge: 25)};
    expect(teletalkItems(jobs, profile, now: DateTime.utc(2026, 10, 21, 6), details: tight), isEmpty);
  });

  test('বিস্তারিত পেজের লিংক', () {
    expect(jobs[1].detailsUrl, 'https://alljobs.teletalk.com.bd/jobs/government/1165?jobId=15028');
  });
}
