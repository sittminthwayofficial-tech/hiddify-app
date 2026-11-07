import 'package:flutter/services.dart';

/// NetTest VPN v1.4 — DISGUISE platform bridge.
///
/// The ONLY Dart side of the native disguise surface. Talks to the
/// small MaskChannel block on the Kotlin side (channel
/// "nettest/mask"):
///
///  * setSecure(on) — toggles WindowManager FLAG_SECURE on the
///    activity window, so Android Recents never snapshots the real
///    UI while it is on screen in masked mode.
///  * setMaskedIdentity(masked) — flips the two launcher
///    activity-aliases (AliasMain "NetTest VPN" <-> AliasMasked
///    "MovieLand") via PackageManager.setComponentEnabledSetting.
///
/// Everything here is best-effort polish: every call is wrapped and
/// failures are swallowed — the in-app mask behaviour never depends
/// on the native side answering.
class MaskPlatform {
  MaskPlatform._();

  static const MethodChannel _channel = MethodChannel('nettest/mask');

  /// FLAG_SECURE on/off for the current activity window.
  static Future<void> setSecure(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': on});
    } catch (_) {
      // Best-effort only (spec item 7).
    }
  }

  /// Launcher identity: masked=true -> "MovieLand" alias enabled,
  /// main alias disabled; masked=false -> the reverse.
  static Future<void> setMaskedIdentity(bool masked) async {
    try {
      await _channel.invokeMethod<void>('setMaskedIdentity', {'masked': masked});
    } catch (_) {
      // Best-effort only (spec item 6).
    }
  }
}
