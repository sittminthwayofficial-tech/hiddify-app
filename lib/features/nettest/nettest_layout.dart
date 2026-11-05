import 'package:flutter/material.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';

/// NetTest VPN v1.2 — responsive layout helpers.
///
/// The app shell (MyAdaptiveLayout) puts a left NavigationRail beside
/// the content on tablet/desktop breakpoints, which shifts every page's
/// content right of the true screen center (Alex, 2026-11-05 23:26:
/// "UI တွေ center မှာ ရှိ မနေဘူး"). [nettestCenteredColumn] caps the
/// content column at [maxWidth] AND balances the rail with an equal
/// right inset, so the column sits on the real screen center on phones
/// (no rail, no inset), tablets and wide screens alike — nothing
/// stretches edge-to-edge.

/// Width of the shell's left NavigationRail at the current breakpoint
/// (0 on mobile, where the shell uses a bottom NavigationBar instead).
double nettestRailWidth(BuildContext context) {
  final bp = Breakpoint(context);
  if (bp.isMobile()) return 0;
  if (bp.isTablet()) return 72;
  return 256; // extended rail on desktop-width windows
}

/// Centers [child] on the true screen center with its width capped.
Widget nettestCenteredColumn(
  BuildContext context, {
  required Widget child,
  double maxWidth = 600,
}) {
  final rail = nettestRailWidth(context);
  return Padding(
    padding: EdgeInsets.only(right: rail),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}
