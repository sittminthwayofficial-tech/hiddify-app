import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// NetTest VPN v1.1 — the dedication: "A gift for Daw Thae".
///
/// Locked design (Alex, 2026-11-05 20:09, layout v4): on the splash page
/// everything is STATIC except the dedication line, which slow-slides up
/// and fades in. Champagne gold (#E8C476) Noto Serif Display Italic on
/// ink navy (#0A0E27). The same signature closes the servers view
/// (Option 1: gold rules + diamonds flanking the line).

const nettestNavy = Color(0xFF0A0E27);
const nettestGold = Color(0xFFE8C476);
const nettestGoldDim = Color(0xFF967C46);
const nettestSoftViolet = Color(0xFFB79CFF);
const nettestViolet = Color(0xFF7C4DFF);
const nettestTeal = Color(0xFF2ED3A6);
const dedicationText = 'A gift for Daw Thae';
const dedicationFontFamily = 'NotoSerifDisplay';

class _BoltPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2;
    final cy = s / 2;
    final pts = <Offset>[
      Offset(cx + 0.08 * s, cy - 0.50 * s),
      Offset(cx - 0.30 * s, cy + 0.14 * s),
      Offset(cx - 0.02 * s, cy + 0.14 * s),
      Offset(cx - 0.08 * s, cy + 0.50 * s),
      Offset(cx + 0.30 * s, cy - 0.14 * s),
      Offset(cx + 0.02 * s, cy - 0.14 * s),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = nettestViolet);
    canvas.drawCircle(Offset(cx + 0.21 * s, cy - 0.30 * s), 0.045 * s, Paint()..color = nettestTeal);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Diamond extends StatelessWidget {
  const _Diamond({this.size = 7, this.color = nettestGold});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(width: size, height: size, color: color),
    );
  }
}

/// The static splash composition: glow, gold-ringed bolt emblem,
/// "NETTEST VPN" below the ring, gold rules + diamond, and the one
/// animated element — the dedication line sliding up into place.
class DedicationSplash extends StatelessWidget {
  const DedicationSplash({super.key, required this.lineProgress});

  /// 0..1 — progress of the dedication line's slow slide + fade.
  final double lineProgress;

  @override
  Widget build(BuildContext context) {
    final p = Curves.easeOutCubic.transform(lineProgress.clamp(0, 1));
    return ColoredBox(
      color: nettestNavy,
      child: Stack(
        children: [
          // soft glow rings, centered a little above middle
          Align(
            alignment: const Alignment(0, -0.14),
            child: Container(
              width: 340,
              height: 340,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFF161D42), Color(0xFF121838), Color(0x000A0E27)],
                  stops: [0.45, 0.75, 1],
                ),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: nettestGold, width: 1.6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(34),
                    child: CustomPaint(painter: _BoltPainter()),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'NETTEST VPN',
                  style: TextStyle(
                    color: nettestSoftViolet,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 74, height: 1.2, color: nettestGold),
                    const SizedBox(width: 14),
                    const _Diamond(size: 8),
                    const SizedBox(width: 14),
                    Container(width: 74, height: 1.2, color: nettestGold),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: Transform.translate(
                    offset: Offset(0, 40 * (1 - p)),
                    child: Opacity(
                      opacity: p,
                      child: Text(
                        dedicationText,
                        style: TextStyle(
                          fontFamily: dedicationFontFamily,
                          fontStyle: FontStyle.italic,
                          color: nettestGold,
                          fontSize: 29,
                          letterSpacing: 1.2 * p,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Align(
            alignment: Alignment(0, 0.96),
            child: Text(
              'v1.1',
              style: TextStyle(color: Color(0xFF9AA3C7), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the dedication splash over the app for ~2.9 s on cold start,
/// then fades out and never returns. A hard timer guarantees removal —
/// this widget can never trap the user on a splash screen (spec item 12).
class NettestSplashGate extends StatefulWidget {
  const NettestSplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<NettestSplashGate> createState() => _NettestSplashGateState();
}

class _NettestSplashGateState extends State<NettestSplashGate> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _fallback;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2900));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _dismiss();
    });
    _controller.forward();
    _fallback = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _dismiss() {
    if (!mounted || _gone) return;
    setState(() => _gone = true);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    return Stack(
      children: [
        IgnorePointer(child: widget.child),
        Positioned.fill(
          child: AbsorbPointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final v = _controller.value;
                final gateOpacity = v < 0.88 ? 1.0 : 1.0 - ((v - 0.88) / 0.12);
                final lineProgress = ((v - 0.08) / 0.78).clamp(0, 1).toDouble();
                return Opacity(
                  opacity: gateOpacity.clamp(0, 1),
                  child: DedicationSplash(lineProgress: lineProgress),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Option-1 footer signature for the servers view:
/// ◆ ——— *A gift for Daw Thae* ——— ◆
class DedicationSignature extends StatelessWidget {
  const DedicationSignature({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _Diamond(size: 6),
          const SizedBox(width: 12),
          Container(width: 52, height: 1.1, color: nettestGold),
          const SizedBox(width: 16),
          const Text(
            dedicationText,
            style: TextStyle(
              fontFamily: dedicationFontFamily,
              fontStyle: FontStyle.italic,
              color: nettestGold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 16),
          Container(width: 52, height: 1.1, color: nettestGold),
          const SizedBox(width: 12),
          const _Diamond(size: 6),
        ],
      ),
    );
  }
}
