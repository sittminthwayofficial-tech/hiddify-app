import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'nettest_store.dart';

/// NetTest VPN v1.1 — providers for the isolated star / log / recommend
/// layer. Everything here is best-effort (spec item 12): no throw ever
/// escapes into the app; failures degrade to "feature quietly absent".

/// Set by the connection notifier when the *user* initiates a disconnect,
/// so the session log can tell a clean stop from a drop.
class NettestHooks {
  static bool userDisconnectInitiated = false;
}

final nettestStoreProvider = Provider<NettestStore>((ref) {
  return NettestStore(ref.watch(sharedPreferencesProvider).requireValue);
});

// ------------------------------------------------------------------ stars
class NettestStars extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    try {
      return ref.watch(nettestStoreProvider).readStars();
    } catch (_) {
      return <String>{};
    }
  }

  /// Tap to star, tap again to unstar (spec item 11). Unstarring removes
  /// the node from the STARRED section and the store immediately.
  void toggle(String tag) {
    try {
      if (tag.isEmpty) return;
      final next = {...state};
      if (!next.remove(tag)) next.add(tag);
      state = next;
      unawaited(ref.read(nettestStoreProvider).writeStars(next));
    } catch (_) {}
  }
}

final nettestStarsProvider = NotifierProvider<NettestStars, Set<String>>(NettestStars.new);

// ------------------------------------------------------- parsed (offline) list
const _groupTypes = {'selector', 'urltest', 'balancer'};
const _hiddenTypes = {'direct', 'block', 'dns'};

/// Builds the server list for [profileId] from the locally generated
/// config — no connection needed (spec item 3: servers always visible).
Future<List<OutboundInfo>> nettestParseProfileProxies(Ref ref, String profileId) async {
  try {
    final repo = ref.read(profileRepositoryProvider).requireValue;
    final either = await repo.generateConfig(profileId).run();
    final content = either.getOrElse((_) => '');
    if (content.isEmpty) return [];
    final decoded = jsonDecode(content) as Map<String, dynamic>;
    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return [];
    final store = ref.read(nettestStoreProvider);
    final result = <OutboundInfo>[];
    for (final raw in outbounds) {
      if (raw is! Map) continue;
      final tag = raw['tag']?.toString() ?? '';
      final type = raw['type']?.toString() ?? '';
      if (tag.isEmpty || _hiddenTypes.contains(type) || _groupTypes.contains(type)) continue;
      result.add(
        OutboundInfo(
          tag: tag,
          type: type,
          tagDisplay: tag,
          urlTestDelay: store.lastDelay(tag) ?? 0,
        ),
      );
    }
    return result;
  } catch (_) {
    return [];
  }
}

final nettestParsedProxiesProvider = FutureProvider.autoDispose<List<OutboundInfo>>((ref) async {
  try {
    final profile = await ref.watch(activeProfileProvider.future);
    if (profile == null) return [];
    return nettestParseProfileProxies(ref, profile.id);
  } catch (_) {
    return [];
  }
});

final nettestParsedProxiesForProfileProvider = FutureProvider.autoDispose
    .family<List<OutboundInfo>, String>((ref, profileId) => nettestParseProfileProxies(ref, profileId));

// ------------------------------------------------------------- runtime tracker
/// Background auto-log (spec items 6, 12): listens to connection state,
/// the active proxy and delay-test results; records per-node sessions
/// with connect success, time-to-first-traffic, volume, duration, drops
/// and delay before/after. Also applies the Auto Connect default
/// (select the "lowest" balancer) unless the user picked a node manually.
final nettestRuntimeProvider = Provider<void>((ref) {
  try {
    final store = ref.read(nettestStoreProvider);

    var pendingStart = 0; // ms, connect attempt began
    String? expectedTag; // leaf selected when the attempt began
    var sessionStart = 0;
    String? sessionTag;
    var baseUp = 0;
    var baseDown = 0;
    var lastUp = 0;
    var lastDown = 0;
    int? firstTrafficAt;
    int? lastSessionDelay;
    var autoLowestDone = false;
    OutboundGroup? lastGroup;

    String? activeProfileId() {
      try {
        return ref.read(activeProfileProvider).valueOrNull?.id;
      } catch (_) {
        return null;
      }
    }

    Future<void> finalize({required bool reachedConnected, required int endMs}) async {
      try {
        final tag = sessionTag ?? expectedTag;
        if (tag == null || tag.isEmpty) return;
        final down = (lastDown - baseDown).clamp(0, 1 << 62);
        final up = (lastUp - baseUp).clamp(0, 1 << 62);
        final clean = NettestHooks.userDisconnectInitiated;
        final session = finalizeSession(
          tag: tag,
          startMs: reachedConnected ? sessionStart : pendingStart,
          endMs: endMs,
          reachedConnected: reachedConnected,
          ttfbMs: firstTrafficAt != null && sessionStart > 0 ? firstTrafficAt! - sessionStart : null,
          down: down,
          up: up,
          drops: reachedConnected && !clean ? 1 : 0,
          delayBefore: store.lastDelay(tag),
          delayAfter: lastSessionDelay,
        );
        await store.addSession(session);
      } catch (_) {}
    }

    ref.listen(connectionNotifierProvider, (prev, next) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (next is AsyncError) {
          // A failed attempt surfaces as AsyncError, not Disconnected.
          if (sessionStart > 0) {
            unawaited(finalize(reachedConnected: true, endMs: now));
          } else if (pendingStart > 0) {
            unawaited(finalize(reachedConnected: false, endMs: now));
          }
          pendingStart = 0;
          sessionStart = 0;
          sessionTag = null;
          expectedTag = null;
          firstTrafficAt = null;
          lastSessionDelay = null;
          baseUp = baseDown = lastUp = lastDown = 0;
          autoLowestDone = false;
          NettestHooks.userDisconnectInitiated = false;
          return;
        }
        final status = next.valueOrNull;
        if (status is Connecting) {
          if (pendingStart == 0 && sessionStart == 0) {
            pendingStart = now;
            final sel = lastGroup?.selected ?? '';
            expectedTag = (sel.isNotEmpty && !_groupTypes.contains(_typeOf(lastGroup, sel)))
                ? sel
                : null;
          }
        } else if (status is Connected) {
          if (sessionStart == 0) {
            sessionStart = now;
            if (pendingStart == 0) pendingStart = now;
          }
        } else if (status is Disconnected) {
          if (sessionStart > 0) {
            unawaited(finalize(reachedConnected: true, endMs: now));
          } else if (pendingStart > 0) {
            unawaited(finalize(reachedConnected: false, endMs: now));
          }
          pendingStart = 0;
          sessionStart = 0;
          sessionTag = null;
          expectedTag = null;
          firstTrafficAt = null;
          lastSessionDelay = null;
          baseUp = baseDown = lastUp = lastDown = 0;
          autoLowestDone = false;
          NettestHooks.userDisconnectInitiated = false;
        }
      } catch (_) {}
    });

    ref.listen(activeProxyNotifierProvider, (prev, next) {
      try {
        final info = next.valueOrNull;
        if (info == null || sessionStart == 0) return;
        if (sessionTag == null) {
          sessionTag = info.tag;
          baseUp = lastUp = info.upload.toInt();
          baseDown = lastDown = info.download.toInt();
        } else if (info.tag == sessionTag) {
          lastUp = info.upload.toInt();
          lastDown = info.download.toInt();
        } else {
          return;
        }
        if (info.urlTestDelay > 0) {
          lastSessionDelay = info.urlTestDelay;
          unawaited(store.addDelaySample(info.tag, info.urlTestDelay));
        }
        final total = (lastUp - baseUp) + (lastDown - baseDown);
        if (firstTrafficAt == null && total > 0) {
          firstTrafficAt = DateTime.now().millisecondsSinceEpoch;
        }
      } catch (_) {}
    });

    ref.listen(proxiesOverviewNotifierProvider, (prev, next) {
      try {
        final group = next.valueOrNull;
        if (group == null) return;
        lastGroup = group;
        for (final item in group.items) {
          if (item.urlTestDelay > 0) {
            unawaited(store.addDelaySample(item.tag, item.urlTestDelay));
          }
        }
        // Auto Connect default: pick the "lowest" balancer once per
        // connection, unless the user picked a node by hand (spec item 4).
        final connected = ref.read(connectionNotifierProvider).valueOrNull is Connected;
        if (connected && !autoLowestDone) {
          autoLowestDone = true;
          final hasLowest = group.items.any((i) => i.tag == 'lowest');
          final profileId = activeProfileId();
          if (hasLowest && group.selected != 'lowest' && !(profileId != null && store.manualPick(profileId))) {
            unawaited(() async {
              try {
                await ref.read(proxyRepositoryProvider).selectProxy(group.tag, 'lowest').run();
              } catch (_) {}
            }());
          }
        }
      } catch (_) {}
    });
  } catch (_) {}
});

String? _typeOf(OutboundGroup? group, String tag) {
  if (group == null) return null;
  for (final item in group.items) {
    if (item.tag == tag) return item.type;
  }
  return null;
}
