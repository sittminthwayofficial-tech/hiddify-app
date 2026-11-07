import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hiddify/features/nettest/mask_root.dart';

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
    // NetTest VPN v1.3 (feedback item 3): same shape, same colours —
    // quality polish only: a faint same-hue glow behind the bolt, a
    // subtle vertical sheen across it, and a lighter core in the dot,
    // so the emblem renders crisp and rich instead of flat.
    canvas.drawPath(
      path,
      Paint()
        ..color = nettestViolet.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.05 * s),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF9A75FF), nettestViolet],
        ).createShader(path.getBounds()),
    );
    final dotC = Offset(cx + 0.21 * s, cy - 0.30 * s);
    canvas.drawCircle(
      dotC,
      0.075 * s,
      Paint()
        ..color = nettestTeal.withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.04 * s),
    );
    canvas.drawCircle(dotC, 0.045 * s, Paint()..color = nettestTeal);
    canvas.drawCircle(
      dotC.translate(-0.013 * s, -0.013 * s),
      0.018 * s,
      Paint()..color = const Color(0xFF8FF5D2),
    );
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
///
/// NetTest VPN v1.3 (feedback item 4): the line's motion is driven by
/// its own [lineAnimation] and applied through an AnimatedBuilder whose
/// child (the line's Text) is built ONCE — per frame only a translate +
/// opacity wrapper rebuilds, and the static composition above is never
/// repainted, so the slide is a continuous 60 fps motion instead of
/// the old whole-tree rebuild that stuttered on device.
class DedicationSplash extends StatelessWidget {
  const DedicationSplash({super.key, required this.lineAnimation});

  /// 0..1 (already eased) — progress of the dedication line's slide + fade.
  final Animation<double> lineAnimation;

  @override
  Widget build(BuildContext context) {
    // NetTest VPN v1.2 — responsive: the locked composition is scaled
    // by the screen's shortest side (design baseline 400dp) and capped,
    // so it sits centered and proportionate on small phones and
    // tablets alike — never stretched, never clipped (patch list b).
    return LayoutBuilder(
      builder: (context, constraints) {
        final s = (constraints.biggest.shortestSide / 400).clamp(0.72, 1.3).toDouble();
        return ColoredBox(
          color: nettestNavy,
          child: Stack(
            children: [
              // soft glow rings, centered a little above middle
              // NetTest VPN v1.3.1: the whole STATIC composition (this
              // glow + the emblem/title/rules block below) sits behind
              // RepaintBoundarys, so the gradient and blur layers
              // rasterize ONCE and are never repainted per frame while
              // the dedication line slides. The line itself stays
              // outside every RepaintBoundary.
              RepaintBoundary(
                child: Align(
                  alignment: const Alignment(0, -0.14),
                  child: Container(
                    width: 340 * s,
                    height: 340 * s,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xFF161D42), Color(0xFF121838), Color(0x000A0E27)],
                        stops: [0.45, 0.75, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 148 * s,
                            height: 148 * s,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: nettestGold, width: 1.6),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(34 * s),
                              child: CustomPaint(painter: _BoltPainter()),
                            ),
                          ),
                          SizedBox(height: 20 * s),
                          Text(
                            'NETTEST VPN',
                            style: TextStyle(
                              color: nettestSoftViolet,
                              fontSize: 15 * s,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 8 * s,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          SizedBox(height: 30 * s),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 74 * s, height: 1.2, color: nettestGold),
                              SizedBox(width: 14 * s),
                              _Diamond(size: 8 * s),
                              SizedBox(width: 14 * s),
                              Container(width: 74 * s, height: 1.2, color: nettestGold),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 14 * s),
                    SizedBox(
                      height: 44 * s,
                      child: AnimatedBuilder(
                        animation: lineAnimation,
                        child: Text(
                          dedicationText,
                          style: TextStyle(
                            fontFamily: dedicationFontFamily,
                            fontStyle: FontStyle.italic,
                            color: nettestGold,
                            fontSize: 29 * s,
                            letterSpacing: 1.2 * s,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        builder: (context, child) {
                          final p = lineAnimation.value.clamp(0, 1).toDouble();
                          return Transform.translate(
                            offset: Offset(0, 40 * s * (1 - p)),
                            child: Opacity(opacity: p, child: child),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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

class _NettestSplashGateState extends State<NettestSplashGate> with TickerProviderStateMixin {
  /// Overall gate timing: fade-out window + dismissal, as before.
  late final AnimationController _gate;

  /// NetTest VPN v1.3 (feedback item 4): the dedication line gets its
  /// OWN controller — 1.5 s, easeOutCubic, started after the first
  /// frame so it never competes with the startup-heavy first build.
  /// The splash composition is passed to the gate's AnimatedBuilder as
  /// its cached child, so per-frame work is two opacity/transform
  /// wrappers only — the slide runs at a continuous 60 fps.
  late final AnimationController _line;
  late final Animation<double> _lineAnim;
  Timer? _fallback;
  Timer? _mountTimer;
  bool _gone = false;

  /// NetTest VPN v1.3.1 — deferred child mount. Device diagnosis
  /// (2026-11-06) CONFIRMED the slide stutter is startup contention:
  /// the whole app used to build underneath the splash during the
  /// slide window. The child now stays OUT of the tree until the
  /// line slide completes (~1.55 s), then mounts UNDER the splash
  /// and builds while the (static) splash covers it, until the gate
  /// lifts on the unchanged 2.9 s / 4 s timings.
  bool _childMounted = false;

  @override
  void initState() {
    super.initState();
    _gate = AnimationController(vsync: this, duration: const Duration(milliseconds: 2900));
    _gate.addStatusListener((status) {
      if (status == AnimationStatus.completed) _dismiss();
    });
    _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _line.addStatusListener((status) {
      if (status == AnimationStatus.completed) _mountChild();
    });
    _lineAnim = CurvedAnimation(parent: _line, curve: Curves.easeOutCubic);
    _gate.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _line.forward();
      // Belt-and-braces alongside the slide-completion listener:
      // mount the child ~1.55 s after the slide starts, whichever
      // path fires first (the call is idempotent).
      _mountTimer = Timer(const Duration(milliseconds: 1550), _mountChild);
    });
    _fallback = Timer(const Duration(seconds: 4), _dismiss);
  }

  void _mountChild() {
    if (!mounted || _childMounted) return;
    setState(() => _childMounted = true);
  }

  void _dismiss() {
    if (!mounted || _gone) return;
    setState(() => _gone = true);
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _mountTimer?.cancel();
    _gate.dispose();
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NetTest VPN v1.4: while the real UI is shown as an unlocked
    // DISGUISE session, MaskRoot suppresses the splash entirely —
    // it must never replay over an unlock.
    if (MaskScope.suppressSplashOf(context)) return widget.child;
    if (_gone) return widget.child;
    return Stack(
      children: [
        // Absent from the tree during the slide window (see
        // _childMounted above); once mounted it builds under the
        // splash, input still blocked by the splash's AbsorbPointer.
        if (_childMounted) IgnorePointer(child: widget.child),
        Positioned.fill(
          child: AbsorbPointer(
            child: AnimatedBuilder(
              animation: _gate,
              child: DedicationSplash(lineAnimation: _lineAnim),
              builder: (context, child) {
                final v = _gate.value;
                // NetTest VPN v1.3.1: NO full-screen Opacity during
                // the slide window — a per-frame opacity over the
                // whole splash forces a full-screen layer save on
                // every frame of the slide. The splash is built
                // directly until the outro; only the final ~200 ms
                // of the 2900 ms gate (v >= 0.931) fades.
                if (v < 0.931) return child!;
                final gateOpacity = 1.0 - ((v - 0.931) / 0.069);
                return Opacity(
                  opacity: gateOpacity.clamp(0, 1),
                  child: child,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Option-1 footer signature for the servers view.
///
/// NetTest VPN v1.3 (Alex, 2026-11-06 01:11/01:14 — signature
/// geometry): the same composition as the splash — two SHORT gold
/// rules hugging ONE centre diamond on a line of their own, and the
/// dedication text CLOSE under the rules (small gap). Not the old
/// wide single row with the rules spread far apart.
class DedicationSignature extends StatelessWidget {
  const DedicationSignature({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 64, height: 1.2, color: nettestGold),
              const SizedBox(width: 12),
              const _Diamond(size: 8),
              const SizedBox(width: 12),
              Container(width: 64, height: 1.2, color: nettestGold),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            dedicationText,
            style: TextStyle(
              fontFamily: dedicationFontFamily,
              fontStyle: FontStyle.italic,
              color: nettestGold,
              fontSize: 16,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
