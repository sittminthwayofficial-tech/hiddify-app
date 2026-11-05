import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/nettest/nettest_export.dart';
import 'package:hiddify/features/nettest/nettest_layout.dart';
import 'package:hiddify/features/nettest/nettest_servers_slivers.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// NetTest VPN servers view. The list itself lives in
/// [NettestServersSlivers] — shared with the home page (v1.1.1: the
/// list is on the home screen too, visible immediately at app open).
/// This page keeps its own chrome: title, one-tap export, sort menu
/// and the delay-test FAB (shown once the core is live).
class ProxiesOverviewPage extends HookConsumerWidget {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final live = ref.watch(proxiesOverviewNotifierProvider);
    final group = live.valueOrNull;
    final isLive = group != null;
    final rootGroupTag = group?.tag ?? 'select';

    final sortBy = ref.watch(proxiesSortNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.proxies.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Export ping logs',
            onPressed: () => exportNettestLog(context, ref),
          ),
          PopupMenuButton<ProxiesSort>(
            initialValue: sortBy,
            onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
            icon: const Icon(FluentIcons.arrow_sort_24_regular),
            tooltip: t.pages.proxies.sort,
            itemBuilder: (context) {
              return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
            },
          ),
          const Gap(8),
        ],
      ),
      floatingActionButton: isLive
          ? FloatingActionButton(
              onPressed: () async =>
                  await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(rootGroupTag),
              tooltip: t.pages.proxies.testDelay,
              child: const Icon(FluentIcons.flash_24_filled),
            )
          : null,
      // NetTest VPN v1.2: same centered, width-capped column as home —
      // rows never stretch edge-to-edge on tablets (patch list item d).
      body: nettestCenteredColumn(
        context,
        child: const CustomScrollView(
          slivers: [
            NettestServersSlivers(),
          ],
        ),
      ),
    );
  }
}
