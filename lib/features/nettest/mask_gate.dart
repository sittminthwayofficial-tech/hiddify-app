import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddify/features/nettest/facade_catalog.dart';

/// NetTest VPN v1.4 — DISGUISE door + lock gate.
///
/// Three independent pieces, all best-effort and isolated:
///  * [HoldGesture] — a 5-second continuous press with a progress
///    ring; releasing early resets. This is the hidden "door".
///  * [PinStore] — the app-PIN fallback store. The PIN itself is
///    NEVER stored: only a random 16-byte salt and a
///    PBKDF2-HMAC-SHA256 hash (100,000 iterations), verified with a
///    constant-time comparison. Consecutive failures trigger a
///    persisted lockout (30 s, doubling, capped at 300 s).
///  * [MaskGate.unlock] — the gate itself: system lock via
///    local_auth when the device supports it (biometric or device
///    credential); the app-PIN flow when local_auth is unavailable
///    or errors. A clean local_auth "false" (user cancel/fail)
///    keeps the caller locked out — no silent PIN bypass.

// ---------------------------------------------------------------------------
// PIN store
// ---------------------------------------------------------------------------

const _kPinSalt = 'nettest_pin_salt';
const _kPinHash = 'nettest_pin_hash';
const _kPinFailCount = 'nettest_pin_fail_count';
const _kPinLockoutLevel = 'nettest_pin_lockout_level';
const _kPinLockoutUntil = 'nettest_pin_lockout_until';
const _pinIterations = 100000;
const _pinMaxFails = 5;

String _hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _hexDecode(String hex) {
  final out = <int>[];
  for (var i = 0; i + 1 < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}

/// PBKDF2-HMAC-SHA256, run in a background isolate via [compute].
List<int> _pbkdf2(Map<String, Object> args) {
  final password = args['password'] as List<int>;
  final salt = args['salt'] as List<int>;
  final iterations = args['iterations'] as int;
  const dkLen = 32;
  final hmac = Hmac(sha256, password);
  final out = <int>[];
  var block = 1;
  while (out.length < dkLen) {
    final initial = <int>[
      ...salt,
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];
    var u = hmac.convert(initial).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
    block++;
  }
  return out.sublist(0, dkLen);
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

class PinStore {
  PinStore._();

  static Future<bool> hasPin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_kPinHash) ?? '').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Creates or replaces the stored PIN (salt + hash only).
  static Future<void> setPin(String pin) async {
    final salt = List<int>.generate(16, (_) => math.Random.secure().nextInt(256));
    final hash = await compute(_pbkdf2, <String, Object>{
      'password': Uint8List.fromList(pin.codeUnits),
      'salt': salt,
      'iterations': _pinIterations,
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinSalt, _hexEncode(salt));
    await prefs.setString(_kPinHash, _hexEncode(hash));
    await prefs.remove(_kPinFailCount);
    await prefs.remove(_kPinLockoutLevel);
    await prefs.remove(_kPinLockoutUntil);
  }

  /// Milliseconds of lockout remaining (0 = not locked out).
  static Future<int> lockoutRemainingMs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_kPinLockoutUntil) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      return until > now ? until - now : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Verifies a PIN and applies the failure/lockout bookkeeping.
  /// Returns true only on an exact match while not locked out.
  static Future<bool> verify(String pin) async {
    try {
      if (await lockoutRemainingMs() > 0) return false;
      final prefs = await SharedPreferences.getInstance();
      final saltHex = prefs.getString(_kPinSalt) ?? '';
      final hashHex = prefs.getString(_kPinHash) ?? '';
      if (saltHex.isEmpty || hashHex.isEmpty) return false;
      final computed = await compute(_pbkdf2, <String, Object>{
        'password': Uint8List.fromList(pin.codeUnits),
        'salt': _hexDecode(saltHex),
        'iterations': _pinIterations,
      });
      final ok = _constantTimeEquals(computed, _hexDecode(hashHex));
      if (ok) {
        await prefs.remove(_kPinFailCount);
        await prefs.remove(_kPinLockoutLevel);
        await prefs.remove(_kPinLockoutUntil);
        return true;
      }
      final fails = (prefs.getInt(_kPinFailCount) ?? 0) + 1;
      if (fails >= _pinMaxFails) {
        final level = prefs.getInt(_kPinLockoutLevel) ?? 0;
        final seconds = math.min(30 << level, 300);
        await prefs.setInt(
          _kPinLockoutUntil,
          DateTime.now().millisecondsSinceEpoch + seconds * 1000,
        );
        await prefs.setInt(_kPinLockoutLevel, level + 1);
        await prefs.setInt(_kPinFailCount, 0);
      } else {
        await prefs.setInt(_kPinFailCount, fails);
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Hold-to-open gesture (the hidden door)
// ---------------------------------------------------------------------------

/// Wraps [child] with a continuous-press detector: the press must be
/// held for [duration] (default 5 s); releasing early resets the
/// progress ring to zero. On completion, [onComplete] fires once.
class HoldGesture extends StatefulWidget {
  const HoldGesture({
    super.key,
    required this.child,
    required this.onComplete,
    this.duration = const Duration(seconds: 5),
    this.ringSize = 44,
  });

  final Widget child;
  final VoidCallback onComplete;
  final Duration duration;
  final double ringSize;

  @override
  State<HoldGesture> createState() => _HoldGestureState();
}

class _HoldGestureState extends State<HoldGesture> {
  Timer? _timer;
  double _progress = 0;
  bool _fired = false;

  void _start() {
    _timer?.cancel();
    _fired = false;
    final start = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final p = elapsed / widget.duration.inMilliseconds;
      if (p >= 1) {
        _timer?.cancel();
        setState(() => _progress = 0);
        if (!_fired) {
          _fired = true;
          widget.onComplete();
        }
      } else {
        setState(() => _progress = p);
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    if (mounted && !_fired) setState(() => _progress = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_progress > 0)
            SizedBox(
              width: widget.ringSize,
              height: widget.ringSize,
              child: CircularProgressIndicator(
                value: _progress,
                strokeWidth: 2.5,
                color: const Color(0xFFE8C476),
                backgroundColor: const Color(0x33E8C476),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The gate
// ---------------------------------------------------------------------------

class MaskGate {
  MaskGate._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Runs the lock. Returns true when the caller may proceed.
  ///
  /// Order (mission item 3): system lock via local_auth when the
  /// device supports it; app-PIN flow when local_auth reports
  /// unavailable / no credential / throws. local_auth returning a
  /// clean false (cancel or failed attempts) => false, no fallback.
  static Future<bool> unlock(BuildContext context) async {
    var usePin = false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (supported) {
        try {
          final ok = await _auth.authenticate(
            localizedReason: 'Unlock $facadeBrandName',
            options: const AuthenticationOptions(
              biometricOnly: false,
              stickyAuth: true,
            ),
          );
          return ok;
        } on PlatformException {
          // NotAvailable / NotEnrolled / PasscodeNotSet / errors ->
          // the app-PIN flow is the specified fallback.
          usePin = true;
        }
      } else {
        usePin = true;
      }
    } catch (_) {
      usePin = true;
    }
    if (!usePin || !context.mounted) return false;
    return _pinFlow(context);
  }

  /// Forces identity proof for a sensitive change (e.g. Change PIN):
  /// same resolution order as [unlock].
  static Future<bool> verifyIdentity(BuildContext context) => unlock(context);

  /// Shows the PIN page in "set a new PIN" mode. Assumes the caller
  /// has already gated entry (see the disguise section).
  static Future<bool> changePin(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PinPadPage(mode: PinPadMode.create)),
    );
    return result ?? false;
  }

  static Future<bool> _pinFlow(BuildContext context) async {
    final exists = await PinStore.hasPin();
    if (!context.mounted) return false;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PinPadPage(mode: exists ? PinPadMode.verify : PinPadMode.create),
      ),
    );
    return result ?? false;
  }
}

enum PinPadMode { create, verify }

/// Facade-styled numeric PIN pad. The only text on the page is the
/// brand name — nothing hints at what the PIN protects.
class PinPadPage extends StatefulWidget {
  const PinPadPage({super.key, required this.mode});

  final PinPadMode mode;

  @override
  State<PinPadPage> createState() => _PinPadPageState();
}

class _PinPadPageState extends State<PinPadPage> {
  String _entry = '';
  String? _firstEntry;
  String _hint = '';
  bool _busy = false;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  static const _bg = Color(0xFF0B0F24);
  static const _gold = Color(0xFFE8C476);

  @override
  void initState() {
    super.initState();
    if (widget.mode == PinPadMode.verify) _refreshLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockout() async {
    final ms = await PinStore.lockoutRemainingMs();
    if (!mounted) return;
    setState(() => _lockoutSeconds = (ms / 1000).ceil());
    if (ms > 0) {
      _lockoutTimer?.cancel();
      _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          if (_lockoutSeconds > 0) _lockoutSeconds--;
        });
        if (_lockoutSeconds <= 0) _lockoutTimer?.cancel();
      });
    }
  }

  void _onDigit(String d) {
    if (_busy || _lockoutSeconds > 0 || _entry.length >= 6) return;
    setState(() {
      _entry += d;
      _hint = '';
    });
    if (_entry.length >= 4) {
      // Auto-submit once a plausible PIN is complete (4–6 digits):
      // submit at 6 immediately, or when the user pauses — simplest
      // robust rule: submit when the pad's OK key is tapped, or at 6.
      if (_entry.length == 6) _submit();
    }
  }

  void _onDelete() {
    if (_busy || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _submit() async {
    if (_busy || _entry.length < 4) return;
    setState(() => _busy = true);
    try {
      if (widget.mode == PinPadMode.create) {
        if (_firstEntry == null) {
          setState(() {
            _firstEntry = _entry;
            _entry = '';
            _hint = 'Enter again to confirm';
            _busy = false;
          });
          return;
        }
        if (_entry != _firstEntry) {
          setState(() {
            _firstEntry = null;
            _entry = '';
            _hint = 'PINs did not match. Try again.';
            _busy = false;
          });
          return;
        }
        await PinStore.setPin(_entry);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final ok = await PinStore.verify(_entry);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _entry = '';
        _busy = false;
        _hint = 'Incorrect PIN';
      });
      await _refreshLockout();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _hint = 'Something went wrong. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          facadeBrandName,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 36),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _entry.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? _gold : Colors.transparent,
                    border: Border.all(color: _gold, width: 1.4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 20,
              child: Text(
                _lockoutSeconds > 0
                    ? 'Try again in $_lockoutSeconds s'
                    : _hint,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            const Spacer(),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', '<'],
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final key in row)
                    SizedBox(
                      width: 84,
                      height: 64,
                      child: key == ''
                          ? const SizedBox()
                          : TextButton(
                              onPressed: () =>
                                  key == '<' ? _onDelete() : _onDigit(key),
                              child: key == '<'
                                  ? const Icon(Icons.backspace_outlined,
                                      color: Colors.white, size: 24)
                                  : Text(
                                      key,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: (_entry.length >= 4 && !_busy && _lockoutSeconds == 0)
                  ? _submit
                  : null,
              child: const Text(
                'OK',
                style: TextStyle(color: _gold, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
