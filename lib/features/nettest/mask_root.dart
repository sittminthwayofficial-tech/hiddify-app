import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddify/features/nettest/facade.dart';
import 'package:hiddify/features/nettest/mask_gate.dart';
import 'package:hiddify/features/nettest/mask_platform.dart';

/// NetTest VPN v1.4 — DISGUISE root switch.
///
/// The ONE place the disguise system plugs into the app: app.dart
/// wraps the normal tree in [MaskRoot] and everything else follows
/// from the persisted `nettest_mask_on` flag.
///
///  * Mask OFF (default) -> the child tree is rendered untouched:
///    the app behaves exactly like v1.3.1.
///  * Mask ON -> the MovieLand facade is the root. The hidden-door
///    hold runs the lock gate (mask_gate.dart); success swaps the
///    root to the real UI for this session.
///  * Relock: backgrounding the app while the real UI is shown
///    swaps straight back to the facade (so the Recents snapshot
///    only ever shows the facade) and stamps the time. Re-entry
///    within 60 s needs the door hold only; after that (or on any
///    cold start) the full lock is required. FLAG_SECURE is held
///    for exactly the time the real UI is visible in masked mode.
///
/// The subtree can reach this state via [MaskRootState.of] (the
/// disguise section uses it to flip the mask flag). Any failure in
/// the disguise layer degrades to the plain child tree.

const maskOnPrefKey = 'nettest_mask_on';

/// Carried down to the dedication splash gate: while the real UI is
/// shown as an unlocked masked session, the splash must not replay.
class MaskScope extends InheritedWidget {
  const MaskScope({super.key, required this.suppressSplash, required super.child});

  final bool suppressSplash;

  static bool suppressSplashOf(BuildContext context) {
    try {
      return context
              .dependOnInheritedWidgetOfExactType<MaskScope>()
              ?.suppressSplash ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  bool updateShouldNotify(MaskScope oldWidget) =>
      oldWidget.suppressSplash != suppressSplash;
}

class MaskRoot extends StatefulWidget {
  const MaskRoot({super.key, required this.child});

  final Widget child;

  @override
  State<MaskRoot> createState() => MaskRootState();
}

class MaskRootState extends State<MaskRoot> with WidgetsBindingObserver {
  /// null = still reading prefs (brief navy placeholder, matching
  /// the native splash colour so the seam is invisible).
  bool? _maskOn;
  bool _unlocked = false;

  /// In-memory only: a cold start must always demand the full lock,
  /// so the background stamp is never persisted.
  int _backgroundedAtMs = 0;

  static MaskRootState? of(BuildContext context) {
    try {
      return context.findAncestorStateOfType<MaskRootState>();
    } catch (_) {
      return null;
    }
  }

  bool get maskOn => _maskOn ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    var on = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      on = prefs.getBool(maskOnPrefKey) ?? false;
    } catch (_) {
      on = false;
    }
    if (mounted) setState(() => _maskOn = on);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Relock (mission item 4): the moment the app leaves the
    // foreground with the real UI up, fall back to the facade.
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.hidden) &&
        _maskOn == true &&
        _unlocked) {
      _backgroundedAtMs = DateTime.now().millisecondsSinceEpoch;
      MaskPlatform.setSecure(false);
      if (mounted) setState(() => _unlocked = false);
    }
  }

  bool get _graceValid =>
      _backgroundedAtMs > 0 &&
      DateTime.now().millisecondsSinceEpoch - _backgroundedAtMs < 60000;

  /// The facade's hidden door fired: grace -> straight in, else the
  /// full lock gate.
  Future<void> _onDoorHold() async {
    if (_graceValid) {
      _enterRealUi();
      return;
    }
    if (!mounted) return;
    final ok = await MaskGate.unlock(context);
    if (ok && mounted) _enterRealUi();
  }

  void _enterRealUi() {
    MaskPlatform.setSecure(true);
    setState(() => _unlocked = true);
  }

  /// Flips the persisted mask flag (called by the disguise section,
  /// which is itself behind the lock gate).
  ///
  /// Turning ON while the real UI is on screen keeps the real UI
  /// for this session (mission item 5: the facade takes over on the
  /// next background/cold start). Turning OFF drops every disguise
  /// behaviour immediately.
  Future<void> setMaskEnabled(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(maskOnPrefKey, on);
    } catch (_) {}
    await MaskPlatform.setMaskedIdentity(on);
    if (!mounted) return;
    if (on) {
      setState(() {
        _maskOn = true;
        _unlocked = true; // stay in the real UI for this session
      });
      MaskPlatform.setSecure(true);
    } else {
      MaskPlatform.setSecure(false);
      setState(() {
        _maskOn = false;
        _unlocked = false;
        _backgroundedAtMs = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = _maskOn;
    if (on == null) {
      return const ColoredBox(color: Color(0xFF0A0E27));
    }
    if (!on) {
      return MaskScope(suppressSplash: false, child: widget.child);
    }
    if (_unlocked) {
      return MaskScope(suppressSplash: true, child: widget.child);
    }
    return FacadeApp(onDoorHold: _onDoorHold);
  }
}
