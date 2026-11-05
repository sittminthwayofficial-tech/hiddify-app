import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// NetTest VPN v1.1 — isolated data layer for stars, delay history,
/// session-quality log and RECOMMEND scoring.
///
/// STABILITY CONTRACT (spec item 12): this layer is best-effort only.
/// Every public method swallows its own errors; a failure here degrades
/// silently and can never affect connecting or the core.
///
/// DELETION SAFETY (spec item 13):
///  - Detailed session records are auto-deleted ONLY when they are BOTH
///    older than 30 days AND already folded into the per-node aggregate
///    (folding happens at write time, so age is the only gate left).
///  - Per-node aggregate summaries are NEVER auto-deleted.
///  - Records of starred nodes are exempt from auto-deletion.
///  - Nothing younger than 30 days is ever auto-deleted, regardless of size.
///  - The hard cap is a backstop only; sessions are a few hundred bytes.
class NettestStore {
  NettestStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kStars = 'nettest.stars.v1';
  static const _kDelay = 'nettest.delay.v1';
  static const _kSessions = 'nettest.sessions.v1';
  static const _kAggregates = 'nettest.aggregates.v1';
  static const _kManualPick = 'nettest.manualPick.v1';
  static const _kSeeded = 'nettest.seeded.v1';

  static const int _maxDelaySamplesPerTag = 40;
  static const int _maxDetailedSessions = 600;
  static const Duration _retention = Duration(days: 30);

  // ---------------------------------------------------------------- stars
  Set<String> readStars() {
    try {
      final raw = _prefs.getStringList(_kStars);
      return raw == null ? <String>{} : raw.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> writeStars(Set<String> stars) async {
    try {
      await _prefs.setStringList(_kStars, stars.toList());
    } catch (_) {}
  }

  // ---------------------------------------------------------------- delays
  /// tag -> list of {'t': epochMs, 'd': delayMs}, oldest first.
  Map<String, List<Map<String, int>>> readDelays() {
    try {
      final raw = _prefs.getString(_kDelay);
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((tag, list) {
        final samples = (list as List)
            .whereType<Map>()
            .map((e) => {'t': (e['t'] as num).toInt(), 'd': (e['d'] as num).toInt()})
            .toList();
        return MapEntry(tag, samples);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> addDelaySample(String tag, int delayMs) async {
    if (tag.isEmpty || delayMs <= 0 || delayMs > 65000) return;
    try {
      final all = readDelays();
      final list = all.putIfAbsent(tag, () => []);
      final now = DateTime.now().millisecondsSinceEpoch;
      // Throttle: at most one sample per tag per 5 seconds.
      if (list.isNotEmpty && now - list.last['t']! < 5000 && list.last['d'] == delayMs) return;
      list.add({'t': now, 'd': delayMs});
      if (list.length > _maxDelaySamplesPerTag) {
        list.removeRange(0, list.length - _maxDelaySamplesPerTag);
      }
      await _prefs.setString(_kDelay, jsonEncode(all));
    } catch (_) {}
  }

  int? lastDelay(String tag) {
    final list = readDelays()[tag];
    if (list == null || list.isEmpty) return null;
    return list.last['d'];
  }

  // ---------------------------------------------------------------- sessions
  List<Map<String, dynamic>> readSessions() {
    try {
      final raw = _prefs.getString(_kSessions);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> readAggregates() {
    try {
      final raw = _prefs.getString(_kAggregates);
      if (raw == null) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Folds the session into the per-node aggregate (never deleted) and
  /// appends the detailed record, applying the spec-13 rotation.
  Future<void> addSession(Map<String, dynamic> session) async {
    try {
      final tag = session['tag'] as String? ?? '';
      if (tag.isEmpty) return;

      // 1) Fold into aggregate first — aggregates are permanent.
      final aggregates = readAggregates();
      final agg = Map<String, dynamic>.from(aggregates[tag] as Map? ?? {});
      agg['sessions'] = (agg['sessions'] as num? ?? 0).toInt() + 1;
      if (session['ok'] == true) agg['ok'] = (agg['ok'] as num? ?? 0).toInt() + 1;
      if (session['good'] == true) agg['good'] = (agg['good'] as num? ?? 0).toInt() + 1;
      if (session['bad'] == true) agg['bad'] = (agg['bad'] as num? ?? 0).toInt() + 1;
      agg['down'] = (agg['down'] as num? ?? 0).toInt() + (session['down'] as num? ?? 0).toInt();
      agg['up'] = (agg['up'] as num? ?? 0).toInt() + (session['up'] as num? ?? 0).toInt();
      agg['drops'] = (agg['drops'] as num? ?? 0).toInt() + (session['drops'] as num? ?? 0).toInt();
      agg['lastEnd'] = session['end'];
      aggregates[tag] = agg;
      await _prefs.setString(_kAggregates, jsonEncode(aggregates));

      // 2) Detailed record + safe rotation.
      final sessions = readSessions();
      sessions.add(session);
      final stars = readStars();
      final cutoff = DateTime.now().subtract(_retention).millisecondsSinceEpoch;
      sessions.removeWhere((s) {
        final end = (s['end'] as num? ?? 0).toInt();
        final sTag = s['tag'] as String? ?? '';
        // Only >30d, non-starred records may leave; they are already folded.
        return end < cutoff && !stars.contains(sTag);
      });
      if (sessions.length > _maxDetailedSessions) {
        // Backstop: still only >30d non-starred records may be dropped,
        // oldest first. Young or starred records are never touched.
        var excess = sessions.length - _maxDetailedSessions;
        sessions.removeWhere((s) {
          if (excess <= 0) return false;
          final end = (s['end'] as num? ?? 0).toInt();
          final sTag = s['tag'] as String? ?? '';
          if (end < cutoff && !stars.contains(sTag)) {
            excess--;
            return true;
          }
          return false;
        });
      }
      await _prefs.setString(_kSessions, jsonEncode(sessions));
    } catch (_) {}
  }

  // ---------------------------------------------------------------- misc flags
  bool manualPick(String profileId) {
    try {
      return _prefs.getBool('$_kManualPick.$profileId') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setManualPick(String profileId) async {
    try {
      await _prefs.setBool('$_kManualPick.$profileId', true);
    } catch (_) {}
  }

  bool get seeded {
    try {
      return _prefs.getBool(_kSeeded) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> markSeeded() async {
    try {
      await _prefs.setBool(_kSeeded, true);
    } catch (_) {}
  }
}

/// A "good" session per Alex's verdict (2026-11-05 20:24):
/// connects, real traffic flows at usable speed, stays up.
/// A session that connected but carried ~zero traffic is BAD
/// ("connects but unusable") and demotes the node.
Map<String, dynamic> finalizeSession({
  required String tag,
  required int startMs,
  required int endMs,
  required bool reachedConnected,
  int? ttfbMs,
  int down = 0,
  int up = 0,
  int drops = 0,
  int? delayBefore,
  int? delayAfter,
}) {
  final durMs = endMs - startMs;
  final total = down + up;
  final avgBps = durMs > 0 ? total * 1000 ~/ durMs : 0;
  final bad = reachedConnected && total < 10240; // connected but ~no traffic
  final good =
      reachedConnected &&
      !bad &&
      total >= 51200 &&
      avgBps >= 10240 &&
      durMs >= 20000 &&
      drops == 0;
  return {
    'tag': tag,
    'start': startMs,
    'end': endMs,
    'ok': reachedConnected,
    'ttfbMs': ttfbMs,
    'down': down,
    'up': up,
    'avgBps': avgBps,
    'durMs': durMs,
    'drops': drops,
    'delayBefore': delayBefore,
    'delayAfter': delayAfter,
    'bad': bad,
    'good': good,
  };
}

/// RECOMMEND scoring over aggregates + recent detail + delay history.
/// Returns up to [limit] tags, best first. Pure and total: never throws.
List<String> recommendTags(
  NettestStore store, {
  int limit = 3,
  Set<String>? restrictTo,
}) {
  try {
    final aggregates = store.readAggregates();
    final delays = store.readDelays();
    final sessions = store.readSessions();
    final tags = <String>{...aggregates.keys, ...delays.keys};
    if (restrictTo != null) tags.retainAll(restrictTo);

    double scoreOf(String tag) {
      final agg = aggregates[tag] as Map?;
      final sessionsCount = (agg?['sessions'] as num? ?? 0).toDouble();
      final ok = (agg?['ok'] as num? ?? 0).toDouble();
      final good = (agg?['good'] as num? ?? 0).toDouble();
      final bad = (agg?['bad'] as num? ?? 0).toDouble();
      var score = 0.0;
      if (sessionsCount > 0) {
        score += 40 * (ok / sessionsCount);
        score += 40 * (good / sessionsCount);
        score -= 18 * bad;
      }
      final samples = delays[tag];
      if (samples != null && samples.isNotEmpty) {
        final recent = samples.length > 10 ? samples.sublist(samples.length - 10) : samples;
        final values = recent.map((e) => e['d']!).toList()..sort();
        final median = values[values.length ~/ 2];
        score += 20 * (1 - (median.clamp(0, 2000) / 2000));
        score += 5; // has any delay data at all
      } else if (sessionsCount == 0) {
        return -1; // no data — never recommend
      }
      // Latest detailed session being bad halves the score (fresh evidence).
      for (var i = sessions.length - 1; i >= 0; i--) {
        if (sessions[i]['tag'] == tag) {
          if (sessions[i]['bad'] == true) score *= 0.5;
          if (sessions[i]['good'] == true) score += 5;
          break;
        }
      }
      return score;
    }

    final scored = tags.map((t) => MapEntry(t, scoreOf(t))).where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  } catch (_) {
    return [];
  }
}
