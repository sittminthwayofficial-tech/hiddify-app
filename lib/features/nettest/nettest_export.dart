import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/features/nettest/nettest_providers.dart';
import 'package:hiddify/features/nettest/nettest_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// NetTest VPN — one-tap ping-log export (spec items 1, 12).
/// Composes the on-device log (stars, delay tests, per-session quality
/// records, aggregates, current RECOMMEND) into a .txt and opens the
/// Android share sheet.
///
/// v1.2.1 — NEVER SILENT (device defect on a fresh-installed 1.2.0:
/// tapping Export produced nothing at all — no sheet, no file). The old
/// implementation wrapped the whole flow in one blanket try/catch
/// ("best-effort"), so ANY throw — store read, file write, or the
/// share_plus call — degraded to invisible nothing. The ladder now is:
///   1. compose defensively: if the store cannot be read, the export
///      still produces a file with headers + "no data yet";
///   2. write the .txt to a user-visible location (external files dir,
///      then app documents, then temp);
///   3. open the share sheet;
///   4. if sharing fails, keep the saved file and show a SnackBar with
///      its full path — the tap always produces visible feedback.
/// Still fully inside the isolated nettest layer (spec item 12): a
/// failure here can never affect connecting or the core.

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

String _emptyLogText(String note) {
  final buf = StringBuffer();
  buf.writeln('NetTest VPN — Ping & Session Log');
  buf.writeln('Exported: ${_fmtTime(DateTime.now().millisecondsSinceEpoch)}');
  buf.writeln('');
  buf.writeln('=== NO DATA YET ===');
  buf.writeln(note);
  return buf.toString();
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
    final a = raw is Map ? raw : const {};
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

/// One tap → share sheet with the log file attached; if the sheet
/// cannot be opened, the file is saved to a visible location and a
/// SnackBar says where. Never silent (v1.2.1).
Future<void> exportNettestLog(BuildContext context, WidgetRef ref) async {
  // ---- 1) compose (defensive: even a broken store yields a file)
  var text = '';
  try {
    NettestStore? store;
    try {
      store = ref.read(nettestStoreProvider);
    } catch (_) {
      store = null;
    }
    if (store == null) {
      text = _emptyLogText('No tests or sessions recorded yet (log store unavailable).');
    } else {
      try {
        text = buildNettestLogText(store);
      } catch (e) {
        text = _emptyLogText('No tests or sessions recorded yet (log read failed: $e).');
      }
    }
  } catch (e) {
    text = _emptyLogText('No tests or sessions recorded yet ($e).');
  }
  if (text.trim().isEmpty) {
    text = _emptyLogText('No tests or sessions recorded yet.');
  }

  // ---- 2) write the .txt (visible dir first)
  File? file;
  final dirs = <Directory?>[];
  try {
    dirs.add(await getExternalStorageDirectory());
  } catch (_) {}
  try {
    dirs.add(await getApplicationDocumentsDirectory());
  } catch (_) {}
  dirs.add(Directory.systemTemp);
  for (final dir in dirs) {
    if (dir == null) continue;
    try {
      final f = File('${dir.path}/nettest_ping_log.txt');
      await f.writeAsString(text, flush: true);
      file = f;
      break;
    } catch (_) {}
  }

  // ---- 3) share sheet. NOTE: this project's resolved share_plus has
  // no SharePlus/ShareParams API (v1.2.1's first build proved it at
  // compile time) — the static Share API is what compiles and shipped
  // in v1.1/v1.2. If it returns, the sheet was shown (a user dismissal
  // is his choice, not a failure); if it throws, step 4 takes over.
  Object? shareError;
  var shared = false;
  if (file != null) {
    try {
      await Share.shareXFiles([XFile(file.path, mimeType: 'text/plain')]);
      shared = true;
    } catch (e) {
      shareError = e;
    }
  }

  // ---- 4) never silent: announce the saved fallback
  if (!shared && context.mounted) {
    try {
      if (file != null && shareError != null) {
        // Annotate the saved copy so a future failure is diagnosable
        // from the file itself when Alex sends it over.
        try {
          await file.writeAsString('share error: $shareError\n\n$text', flush: true);
        } catch (_) {}
      }
      final where = file != null ? file.path : 'nowhere — saving failed ($shareError)';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Share unavailable — ping log saved to: $where'),
          duration: const Duration(seconds: 10),
        ),
      );
    } catch (_) {}
  }
}
