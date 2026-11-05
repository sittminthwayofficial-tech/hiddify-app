import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/nettest/dedication.dart';
import 'package:hiddify/features/nettest/nettest_export.dart';
import 'package:hiddify/features/nettest/nettest_providers.dart';
import 'package:hiddify/features/nettest/nettest_store.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

/// NetTest VPN — the shared server-list slivers, used by BOTH the home
/// page (v1.1.1: the list lives on the home screen, visible immediately
/// at app open — Alex's spec items 3/4/9) and the standalone proxies
/// page. One implementation, one store — no duplication.
///
///  - the server list renders WITHOUT connecting first (parsed locally
///    from the active profile's generated config; live core data takes
///    over automatically once connected)
///  - order: ⭐ STARRED (his picks, always on top) → RECOMMEND (top 3
///    from on-device data) → the tested list fastest-first, all expanded
///  - v1.2.1 (Alex, 2026-11-06): ALL SERVERS renders only nodes whose
///    latest delay test succeeded AND came back under 800 ms. Untested,
///    no-reply and >=800 ms nodes are NOT rendered at all — a node
///    joins (or rejoins) the visible list automatically when a later
///    test lands under the threshold (supersedes the v1.1 item-9
///    "show no-reply greyed at the bottom" rule). Display-only: hidden
///    nodes keep being delay-tested in the background, and the
///    store/log/export still contain everything. STARRED stays visible
///    regardless of delay — his picks are exempt from both filters.
///  - one-tap ping-log export + the Option-1 dedication signature
///  - v1.3 (Alex, 2026-11-06 01:09): ALL SERVERS is collapsible —
///    collapsed it shows only the best 5 (RECOMMEND picks are already
///    excluded above, so nothing duplicates), the rest sit behind a
///    "Show all servers" flip row; expanded shows everything with a
///    "Show less" flip row. The dedication signature sits directly
///    below the flip row when collapsed and travels to the very
///    bottom of the full list when expanded.
class NettestServersSlivers extends HookConsumerWidget {
  const NettestServersSlivers({super.key});

  /// v1.3: how many ALL SERVERS rows show in the collapsed state.
  static const int collapsedCount = 5;

  static bool _noReply(OutboundInfo i) => i.urlTestDelay == 0 || i.urlTestDelay > 65000;

  /// v1.2.1: ALL SERVERS shows a node only when it has a successful
  /// delay sample under Alex's 800 ms threshold.
  static const int maxVisibleDelayMs = 800;
  static bool _visibleInAll(OutboundInfo i) => !_noReply(i) && i.urlTestDelay < maxVisibleDelayMs;

  static int _byDelay(OutboundInfo a, OutboundInfo b) {
    final ai = _noReply(a) ? 1 << 30 : a.urlTestDelay;
    final bi = _noReply(b) ? 1 << 30 : b.urlTestDelay;
    return ai.compareTo(bi);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final live = ref.watch(proxiesOverviewNotifierProvider);
    final parsed = ref.watch(nettestParsedProxiesProvider);
    final stars = ref.watch(nettestStarsProvider);
    NettestStore? store;
    try {
      store = ref.read(nettestStoreProvider);
    } catch (_) {
      store = null;
    }

    final activeProfile = ref.watch(activeProfileProvider).valueOrNull;
    final allProfiles = ref.watch(profilesNotifierProvider).valueOrNull ?? const <ProfileEntity>[];
    ProfileEntity? nettestProfile;
    for (final p in allProfiles) {
      if (p is RemoteProfileEntity && p.url.contains('working_app')) {
        nettestProfile = p;
        break;
      }
    }
    final activeIsNettest = nettestProfile != null && activeProfile?.id == nettestProfile.id;

    // ---- item universe: live core group when available, else parsed list
    List<OutboundInfo> items = const [];
    String rootGroupTag = 'select';
    String selectedTag = '';
    var isLive = false;
    if (live case AsyncData(value: final group?)) {
      items = group.items;
      rootGroupTag = group.tag;
      selectedTag = group.selected;
      isLive = true;
    } else if (parsed.valueOrNull != null) {
      items = [...parsed.valueOrNull!]..sort(_byDelay);
    }

    final leafTags = items.where((i) => !i.isGroup).map((i) => i.tag).toSet();

    // ---- sections
    final starredItems = items.where((i) => stars.contains(i.tag)).toList()..sort(_byDelay);
    var recommendItems = <OutboundInfo>[];
    if (store != null) {
      final recTags = recommendTags(store, limit: 3, restrictTo: leafTags)
          .where((tag) => !stars.contains(tag))
          .toList();
      recommendItems = recTags
          .map((tag) => items.where((i) => i.tag == tag).firstOrNull)
          .whereType<OutboundInfo>()
          .toList();
    }
    // ---- v1.2 RECOMMEND honesty: until at least one recommended node
    // has a completed recorded session behind it, the picks come from
    // the app's own delay tests only — say so in the header.
    var recommendTestBased = false;
    if (store != null && recommendItems.isNotEmpty) {
      try {
        final aggs = store.readAggregates();
        recommendTestBased = !recommendItems.any(
          (i) => ((aggs[i.tag] as Map?)?['sessions'] as num? ?? 0) > 0,
        );
      } catch (_) {
        recommendTestBased = false;
      }
    }

    final sectionTags = {...starredItems.map((i) => i.tag), ...recommendItems.map((i) => i.tag)};
    final rest = items.where((i) => !sectionTags.contains(i.tag)).toList();
    // v1.2.1: untested / no-reply / >=800 ms nodes are hidden from
    // ALL SERVERS (display filter only — testing continues regardless).
    final mainItems = rest.where(_visibleInAll).toList()..sort(_byDelay);
    // v1.3: collapsed shows only the best [collapsedCount] of those.
    final expanded = useState(false);
    final hasMore = mainItems.length > collapsedCount;
    final visibleMainItems =
        (expanded.value || !hasMore) ? mainItems : mainItems.sublist(0, collapsedCount);

    // ---- item 10: with another key active, his NetTest starred best-3
    // stays visible as a compact strip above everything.
    var importedStrip = const <OutboundInfo>[];
    if (!activeIsNettest && nettestProfile != null && stars.isNotEmpty) {
      final ntItems = ref.watch(nettestParsedProxiesForProfileProvider(nettestProfile.id)).valueOrNull;
      if (ntItems != null) {
        importedStrip = ntItems.where((i) => stars.contains(i.tag)).toList()..sort(_byDelay);
        if (importedStrip.length > 3) importedStrip = importedStrip.sublist(0, 3);
      }
    }

    Future<void> onTapItem(OutboundInfo item) async {
      try {
        if (isLive) {
          final pid = activeProfile?.id;
          if (pid != null) store?.setManualPick(pid);
          await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(rootGroupTag, item.tag);
        } else {
          // Not connected yet: tapping a server connects (list goes live).
          await ref.read(connectionNotifierProvider.notifier).toggleConnection();
        }
      } catch (_) {}
    }

    Widget sectionHeader(String label, {IconData? icon, Color? color, String? note}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color ?? theme.colorScheme.primary),
              const Gap(6),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: color ?? theme.colorScheme.primary,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (note != null) ...[
              const Gap(8),
              Text(
                note,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget tileFor(OutboundInfo item) {
      return ProxyTile(
        item,
        selected: selectedTag == item.tag,
        onTap: () => onTapItem(item),
      );
    }

    // v1.3: the flip row under ALL SERVERS — a full-width violet
    // outline pill; the chevron flips with the state (Alex's mock).
    Widget flipRow() {
      final isOpen = expanded.value;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => expanded.value = !isOpen,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                border: Border.all(color: nettestViolet, width: 1.6),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isOpen ? 'Show less' : 'Show all servers',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const Gap(6),
                  Icon(
                    isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (items.isEmpty && importedStrip.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Text(
            live.isLoading || parsed.isLoading ? '…' : t.pages.proxies.empty,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return MultiSliver(
      children: [
        if (importedStrip.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: sectionHeader(
              'YOUR NETTEST BEST',
              icon: Icons.star_rounded,
              color: const Color(0xFFFFC94D),
            ),
          ),
          SliverList.builder(
            itemCount: importedStrip.length,
            itemBuilder: (context, index) => tileFor(importedStrip[index]),
          ),
        ],
        if (starredItems.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: sectionHeader(
              'STARRED',
              icon: Icons.star_rounded,
              color: const Color(0xFFFFC94D),
            ),
          ),
          SliverList.builder(
            itemCount: starredItems.length,
            itemBuilder: (context, index) => tileFor(starredItems[index]),
          ),
        ],
        if (recommendItems.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: sectionHeader(
              'RECOMMEND',
              icon: Icons.recommend_rounded,
              note: recommendTestBased ? 'TEST-BASED' : null,
            ),
          ),
          SliverList.builder(
            itemCount: recommendItems.length,
            itemBuilder: (context, index) => tileFor(recommendItems[index]),
          ),
        ],
        SliverToBoxAdapter(child: sectionHeader('ALL SERVERS')),
        SliverList.builder(
          itemCount: visibleMainItems.length,
          itemBuilder: (context, index) => tileFor(visibleMainItems[index]),
        ),
        // v1.3: flip row (only when there is anything more to show),
        // then the signature directly below it — collapsed it sits
        // right under the expander; expanded it lands at the very
        // bottom of the full list (Alex, 2026-11-06 01:09). The
        // export button keeps its place under the signature.
        if (hasMore) SliverToBoxAdapter(child: flipRow()),
        const SliverToBoxAdapter(child: DedicationSignature()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: FilledButton.icon(
              onPressed: () => exportNettestLog(context, ref),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Export ping logs'),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 84)),
      ],
    );
  }
}
