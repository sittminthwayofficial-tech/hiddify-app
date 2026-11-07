import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiddify/features/nettest/mask_gate.dart';
import 'package:hiddify/features/nettest/mask_root.dart';

/// NetTest VPN v1.4 — DISGUISE section.
///
/// There is NO visible entry to this page anywhere in the real UI.
/// The only way in is [MaskDoorEntry]: a 5-second continuous hold
/// on the header logo (wired in home_page.dart), followed by the
/// full lock gate (mask_gate.dart) — in both modes (mission item 5).
///
/// The page itself is deliberately bare: a blank title, one row
/// with a drawn mask glyph + an On/Off switch, and a Change PIN row
/// when an app PIN exists. No word on the page names what it does.

/// Wraps the real UI's header logo with the hidden-door hold.
/// Successful hold -> lock gate -> disguise section.
class MaskDoorEntry extends StatelessWidget {
  const MaskDoorEntry({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HoldGesture(
      ringSize: 30,
      onComplete: () async {
        final ok = await MaskGate.unlock(context);
        if (ok && context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MaskSectionPage()),
          );
        }
      },
      child: child,
    );
  }
}

/// Small theatre-mask glyph, drawn (not an emoji), gold on navy —
/// the same custom-painter approach as the Telegram plane glyph in
/// nettest_home_overlays.dart.
class MaskIconPainter extends CustomPainter {
  const MaskIconPainter({this.color = const Color(0xFFE8C476)});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..color = color
      ..strokeCap = StrokeCap.round;
    // Face outline: a rounded mask shape, wider at the top.
    final face = Path()
      ..moveTo(w * 0.10, h * 0.30)
      ..quadraticBezierTo(w * 0.10, h * 0.06, w * 0.50, h * 0.06)
      ..quadraticBezierTo(w * 0.90, h * 0.06, w * 0.90, h * 0.30)
      ..quadraticBezierTo(w * 0.90, h * 0.78, w * 0.50, h * 0.94)
      ..quadraticBezierTo(w * 0.10, h * 0.78, w * 0.10, h * 0.30)
      ..close();
    canvas.drawPath(face, stroke);
    // Eyes.
    final eye = Paint()..color = color;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.34, h * 0.40), width: w * 0.15, height: h * 0.09),
      eye,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.66, h * 0.40), width: w * 0.15, height: h * 0.09),
      eye,
    );
    // Smile arc.
    final smile = Path()
      ..moveTo(w * 0.32, h * 0.62)
      ..quadraticBezierTo(w * 0.50, h * 0.78, w * 0.68, h * 0.62);
    canvas.drawPath(smile, stroke);
  }

  @override
  bool shouldRepaint(covariant MaskIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class MaskSectionPage extends StatefulWidget {
  const MaskSectionPage({super.key});

  @override
  State<MaskSectionPage> createState() => _MaskSectionPageState();
}

class _MaskSectionPageState extends State<MaskSectionPage> {
  bool? _on;
  bool _hasPin = false;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var on = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      on = prefs.getBool(maskOnPrefKey) ?? false;
    } catch (_) {}
    final hasPin = await PinStore.hasPin();
    if (mounted) {
      setState(() {
        _on = on;
        _hasPin = hasPin;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    final root = MaskRootState.of(context);
    if (root != null) {
      await root.setMaskEnabled(value);
    } else {
      // Fallback if the root state is somehow unreachable: persist
      // the flag so the next cold start honours it.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(maskOnPrefKey, value);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _on = value;
        _note = 'Done';
      });
    }
  }

  Future<void> _changePin() async {
    final ok = await MaskGate.verifyIdentity(context);
    if (!ok || !mounted) return;
    final changed = await MaskGate.changePin(context);
    if (changed && mounted) setState(() => _note = 'Done');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = _on;
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: CustomPaint(
              size: const Size(24, 24),
              painter: const MaskIconPainter(),
            ),
          ),
        ],
      ),
      body: on == null
          ? const SizedBox()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A1F42),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CustomPaint(
                        size: const Size(26, 26),
                        painter: const MaskIconPainter(),
                      ),
                    ),
                  ),
                  title: Text(
                    on ? 'On' : 'Off',
                    style: theme.textTheme.titleMedium,
                  ),
                  trailing: Switch(value: on, onChanged: _toggle),
                ),
                if (_hasPin)
                  ListTile(
                    leading: const Icon(Icons.pin_outlined),
                    title: const Text('Change PIN'),
                    onTap: _changePin,
                  ),
                if (_note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      _note,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
    );
  }
}
