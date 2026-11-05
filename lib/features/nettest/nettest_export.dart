import 'dart:io';

import 'package:hiddify/features/nettest/nettest_providers.dart';
import 'package:hiddify/features/nettest/nettest_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// NetTest VPN v1.1 — one-tap ping-log export (spec items 1, 12).
/// Composes the on-device log (stars, delay tests, per-session quality
/// records, aggregates, current RECOMMEND) into a .txt and opens the
/// Android share sheet. Best-effort: any failure ends silently.

String _fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String buildNettestLogText(NettestStore store) {
  final buf = StringBuffer();
  buf.writeln('NetTest VPN — Ping & Session Log');
  buf.writeln('Exported: ${_fmtTime(DateTime.now().millisecondsSinceEpoch)}');
  buf.writeln('');

  final stars = store.readStars();
  buf.writeln('=== STARRED (${stars.length}) ===');
  if (stars.isEmpty) buf.writeln('(none)');
  for (final tag in stars) {
    buf.writeln(tag);
  }
  buf.writeln('');

  final delays = store.readDelays();
  buf.writeln('=== DELAY TESTS (recent per node) ===');
  if (delays.isEmpty) buf.writeln('(no tests recorded yet)');
  delays.forEach((tag, samples) {
    final recent = samples.length > 8 ? samples.sublist(samples.length - 8) : samples;
    final parts = recent.map((s) => '${s['d']}ms @${_fmtTime(s['t']!)}').join(' · ');
    buf.writeln('$tag — $parts');
  });
  buf.writeln('');

  final sessions = store.readSessions();
  buf.writeln('=== SESSIONS (${sessions.length}) ===');
  buf.writeln(
    'node | start | duration | connected | time-to-first-traffic | down | up | avg speed | drops | delay before | delay after | verdict',
  );
  for (final s in sessions) {
    final durS = ((s['durMs'] as num? ?? 0) / 1000).toStringAsFixed(0);
    final verdict = s['bad'] == true
        ? 'BAD (connected, no traffic)'
        : s['good'] == true
        ? 'GOOD'
        : s['ok'] == true
        ? 'ok'
        : 'FAILED';
    buf.writeln(
      [
        s['tag'],
        _fmtTime((s['start'] as num? ?? 0).toInt()),
        '${durS}s',
        s['ok'] == true ? 'yes' : 'no',
        s['ttfbMs'] == null ? '-' : '${s['ttfbMs']}ms',
        _fmtBytes((s['down'] as num? ?? 0).toInt()),
        _fmtBytes((s['up'] as num? ?? 0).toInt()),
        '${_fmtBytes((s['avgBps'] as num? ?? 0).toInt())}/s',
        s['drops'],
        s['delayBefore'] == null ? '-' : '${s['delayBefore']}ms',
        s['delayAfter'] == null ? '-' : '${s['delayAfter']}ms',
        verdict,
      ].join(' | '),
    );
  }
  buf.writeln('');

  final aggregates = store.readAggregates();
  buf.writeln('=== PER-NODE SUMMARY (all time, never auto-deleted) ===');
  if (aggregates.isEmpty) buf.writeln('(none)');
  aggregates.forEach((tag, raw) {
    final a = raw as Map;
    buf.writeln(
      '$tag — sessions ${a['sessions']}, connected ${a['ok']}, good ${a['good']}, bad ${a['bad']}, '
      'traffic ${_fmtBytes((a['down'] as num? ?? 0).toInt())} down / ${_fmtBytes((a['up'] as num? ?? 0).toInt())} up, drops ${a['drops']}',
    );
  });
  buf.writeln('');

  final recs = recommendTags(store, limit: 3);
  buf.writeln('=== RECOMMEND (current top 3) ===');
  if (recs.isEmpty) buf.writeln('(not enough data yet)');
  for (var i = 0; i < recs.length; i++) {
    buf.writeln('${i + 1}. ${recs[i]}');
  }
  return buf.toString();
}

/// One tap → share sheet with the log file attached.
Future<void> exportNettestLog(WidgetRef ref) async {
  try {
    final store = ref.read(nettestStoreProvider);
    final text = buildNettestLogText(store);
    final file = File('${Directory.systemTemp.path}/nettest_ping_log.txt');
    await file.writeAsString(text);
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/plain')]);
  } catch (_) {
    // Best-effort only (spec item 12).
  }
}
