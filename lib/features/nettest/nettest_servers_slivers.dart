import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
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
///    from on-device data) → the full list fastest-first → no-reply
///    greyed at the end; nothing hidden behind a tap, all expanded
///  - one-tap ping-log export + the Option-1 dedication signature at
///    the very bottom of the scroll
class NettestServersSlivers extends HookConsumerWidget {
  const NettestServersSlivers({super.key});

  static bool _noReply(OutboundInfo i) => i.urlTestDelay == 0 || i.urlTestDelay > 65000;

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
    final noReplyItems = rest.where(_noReply).toList();
    final mainItems = rest.where((i) => !_noReply(i)).toList();

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

    Widget tileFor(OutboundInfo item, {bool greyed = false}) {
      final tile = ProxyTile(
        item,
        selected: selectedTag == item.tag,
        onTap: () => onTapItem(item),
      );
      return greyed ? Opacity(opacity: 0.5, child: tile) : tile;
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
          itemCount: mainItems.length,
          itemBuilder: (context, index) => tileFor(mainItems[index]),
        ),
        if (noReplyItems.isNotEmpty) ...[
          SliverToBoxAdapter(child: sectionHeader('NO REPLY / NOT TESTED YET')),
          SliverList.builder(
            itemCount: noReplyItems.length,
            itemBuilder: (context, index) => tileFor(noReplyItems[index], greyed: true),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: FilledButton.icon(
              onPressed: () => exportNettestLog(ref),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Export ping logs'),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: DedicationSignature()),
        const SliverToBoxAdapter(child: SizedBox(height: 84)),
      ],
    );
  }
}
