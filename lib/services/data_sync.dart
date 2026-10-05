import 'dart:async';
import 'package:flutter/foundation.dart';
import '../db/db_helper.dart';

/// অন্য Flutter engine (ভাসমান কুইক-অ্যাড বাবল) থেকে হওয়া ডাটা-পরিবর্তন মূল অ্যাপের স্ক্রিনে
/// পৌঁছে দেয়।
///
/// আগে শুধু plugin-এর shareData বার্তার উপর ভরসা ছিল — সেটা কখনো পৌঁছায় না (বাবল অ্যাপের
/// উপরে ভাসলে অ্যাপ "resume"ও হয় না), আর পৌঁছালেও শুধু ড্যাশবোর্ড রিফ্রেশ হতো; খোলা
/// প্রজেক্ট স্ক্রিন বা আজকের কার্ড নয়। এখন: অ্যাপ সামনে থাকলে প্রতি ২ সেকেন্ডে একটা সস্তা
/// কোয়েরি, ছাপ বদলালে [ideasChanged] বাড়ে — যে স্ক্রিন আইডিয়া দেখায় সে শুনে নিজে রিলোড করে।
class DataSync {
  static final ValueNotifier<int> ideasChanged = ValueNotifier(0);
  static Timer? _timer;
  static String? _last;
  static bool _busy = false;

  /// আইডিয়ার পরিবর্তন ঘটেছে কিনা এখনই যাচাই (বাবলের বার্তা বা অ্যাপ resume হলে ডাকা হয়)।
  static Future<void> check() async {
    if (_busy) return;
    _busy = true;
    try {
      final sig = await DBHelper.ideasSignature();
      if (_last != null && sig != _last) ideasChanged.value++;
      _last = sig;
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  static void start() {
    if (_timer != null) return;
    check();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => check());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
