import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/features/nettest/dedication.dart';
import 'package:hiddify/features/nettest/nettest_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// NetTest VPN v1.3 — the two Home overlays Alex designed on
/// 2026-11-06. Both layers are fully isolated from the core connect
/// path and best-effort by construction (spec item 12's no-crash
/// rule): every failure degrades silently to "feature absent".
///
/// 1. CONTACT side button (00:39 correction + sidebutton previews):
///    a small pill docked on the RIGHT screen edge, always visible —
///    navy fill (30,36,76), violet outline, Telegram-blue circle with
///    a white plane. The contact itself stays hidden until the pill
///    is tapped; then a gold-bordered panel slides in from the right
///    over a dimmed background: "CONTACT US" label, the display name
///    "Thue Htet Aung" (the raw link is never shown), and a blue
///    "Open Telegram" button. Close via the × tab on the panel's
///    left edge or by tapping the dimmed area.
///
/// 2. MESSAGE BOX (00:27 design lock): a floating box at the top of
///    Home under the header, horizontally centred with the shell
///    rail compensated, capped at the content column width — dark
///    navy surface, champagne-gold border, gold circle "!" badge,
///    two-line text. Content comes from feed/notices.json in the
///    nettest repo. A notice slides in, stays 5 seconds, and is shown
///    ONCE per notice ID — the seen ID is stored locally (00:24).
///    Burmese text renders in Noto Sans Myanmar, English in Manrope.
///
///    NetTest VPN v1.3.1 — pre-connect delivery (Alex, 2026-11-06
///    02:25): the box UI and show-once behaviour above are unchanged;
///    only the FETCH layer grew. On his network the raw GitHub route
///    often only works once the VPN tunnel is up, so the box used to
///    appear only after connecting. Now: (a) the last fetched notice
///    is cached on-device and an unseen cached notice shows on Home
///    open BEFORE any network result; (b) the live fetch tries the
///    jsDelivr CDN mirror first, then raw GitHub (the raw copy is
///    fresher — if it carries a different ID it is processed too);
///    (c) if every source fails, the fetch retries at +15 s and
///    +45 s; (d) the fetch re-runs whenever the app resumes. Still
///    fully best-effort: every failure degrades silently.
class NettestHomeOverlays extends StatefulWidget {
  const NettestHomeOverlays({super.key});

  @override
  State<NettestHomeOverlays> createState() => _NettestHomeOverlaysState();
}

const _telegramUrl = 'https://t.me/kothuehtetaung';
// v1.3.1 dual source: jsDelivr CDN mirror first (reachable from
// Myanmar without a VPN), raw GitHub second (fresher — it is the
// origin the harvester/Alex pushes to).
const _noticesUrlJsDelivr =
    'https://cdn.jsdelivr.net/gh/sittminthwayofficial-tech/nettest@main/feed/notices.json';
const _noticesUrlRaw =
    'https://raw.githubusercontent.com/sittminthwayofficial-tech/nettest/main/feed/notices.json';
const _seenNoticeKey = 'nettest_notice_seen_id';
const _noticeCacheKey = 'nettest_notice_cache';
const _tgBlue = Color(0xFF2AABEE);
const _panelNavy = Color(0xFF1E244C); // (30, 36, 76)
const _boxNavy = Color(0xFF1A1F42);

bool _hasMyanmar(String s) => s.runes.any((r) => r >= 0x1000 && r <= 0x109F);
String _fontFor(String s) => _hasMyanmar(s) ? 'NotoSansMyanmar' : 'Manrope';

class _Notice {
  const _Notice(this.id, this.title, this.body);
  final String id;
  final String title;
  final String body;
}

/// The Telegram paper-plane glyph (Material has no Telegram icon) —
/// same polygon as the approved preview art.
class _PlanePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pts = <Offset>[
      Offset(0.10 * w, 0.52 * h),
      Offset(0.94 * w, 0.08 * h),
      Offset(0.68 * w, 0.94 * h),
      Offset(0.52 * w, 0.62 * h),
      Offset(0.32 * w, 0.76 * h),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _telegramBadge(double size) {
  return Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: _tgBlue, shape: BoxShape.circle),
    child: Center(
      child: CustomPaint(size: Size(size * 0.58, size * 0.58), painter: _PlanePainter()),
    ),
  );
}

class _NettestHomeOverlaysState extends State<NettestHomeOverlays>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _panelCtrl;
  late final Animation<double> _panelAnim;
  late final AnimationController _noticeCtrl;
  late final Animation<double> _noticeAnim;
  bool _panelOpen = false;
  _Notice? _notice;
  Timer? _noticeTimer;
  List<Timer> _noticeRetryTimers = [];
  bool _checkingNotice = false;

  @override
  void initState() {
    super.initState();
    _panelCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _panelAnim = CurvedAnimation(parent: _panelCtrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    _noticeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _noticeAnim = CurvedAnimation(parent: _noticeCtrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotice());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noticeTimer?.cancel();
    for (final t in _noticeRetryTimers) {
      t.cancel();
    }
    _panelCtrl.dispose();
    _noticeCtrl.dispose();
    super.dispose();
  }

  // v1.3.1: re-run the notice fetch whenever the app comes back to
  // the foreground — a notice published while the app sat in the
  // background lands without a cold start.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkNotice();
    }
  }

  // ------------------------------------------------------------------
  // Message Box fetch layer (v1.3.1): cache first, dual-source live
  // fetch, +15 s / +45 s retries. Show once per ID, 5 s — unchanged.
  // ------------------------------------------------------------------
  Future<void> _checkNotice() async {
    if (_checkingNotice) return;
    _checkingNotice = true;
    try {
      // 1. Cache first: a notice fetched during an earlier (possibly
      //    connected) session shows pre-connect, before any network
      //    result comes back.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_noticeCacheKey);
        if (cached != null && cached.isNotEmpty) {
          final decoded = jsonDecode(cached);
          if (decoded is Map) {
            await _considerNotice(decoded, fromCache: true);
          }
        }
      } catch (_) {}
      // 2. Live fetch from both sources.
      final ok = await _fetchNotices();
      if (!ok) _scheduleNoticeRetries();
    } catch (_) {
      // No network, bad file, anything — the box simply never appears.
    } finally {
      _checkingNotice = false;
    }
  }

  void _scheduleNoticeRetries() {
    if (_noticeRetryTimers.any((t) => t.isActive)) return;
    _noticeRetryTimers = [
      Timer(const Duration(seconds: 15), () => _fetchNotices()),
      Timer(const Duration(seconds: 45), () => _fetchNotices()),
    ];
  }

  /// Tries jsDelivr first, then raw GitHub (raw is processed second
  /// because it is fresher — a different ID there wins the cache).
  /// Returns true if at least one source answered.
  Future<bool> _fetchNotices() async {
    var anySuccess = false;
    try {
      final a = await _fetchNoticeJson(_noticesUrlJsDelivr);
      if (a != null) {
        anySuccess = true;
        await _considerNotice(a);
      }
      final b = await _fetchNoticeJson(_noticesUrlRaw);
      if (b != null) {
        anySuccess = true;
        await _considerNotice(b);
      }
    } catch (_) {}
    return anySuccess;
  }

  Future<Map<String, dynamic>?> _fetchNoticeJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final raw = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The one place every notice (cached or fresh) is judged: empty
  /// ID clears the cache and shows nothing; expired is ignored; a
  /// valid fresh notice replaces the cache; an unseen one shows —
  /// unless a box is already on screen, in which case the fresher
  /// one simply stays cached for the next check.
  Future<void> _considerNotice(Map<dynamic, dynamic> decoded, {bool fromCache = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = (decoded['id'] ?? '').toString().trim();
      if (id.isEmpty) {
        if (!fromCache) {
          try {
            await prefs.remove(_noticeCacheKey);
          } catch (_) {}
        }
        return;
      }
      final title = (decoded['title'] ?? '').toString().trim();
      final body = (decoded['body'] ?? '').toString().trim();
      final expires = (decoded['expires'] ?? '').toString().trim();
      if (title.isEmpty && body.isEmpty) return;
      if (expires.isNotEmpty) {
        final expiry = DateTime.tryParse(expires);
        if (expiry != null && expiry.isBefore(DateTime.now())) return;
      }
      if (!fromCache) {
        try {
          await prefs.setString(_noticeCacheKey, jsonEncode(decoded));
        } catch (_) {}
      }
      final seen = prefs.getString(_seenNoticeKey) ?? '';
      if (id == seen) return;
      if (!mounted || _notice != null) return;
      setState(() => _notice = _Notice(id, title, body));
      await _noticeCtrl.forward();
      // Shown once: record the ID as seen the moment it displayed.
      try {
        await prefs.setString(_seenNoticeKey, id);
      } catch (_) {}
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 5), _hideNotice);
    } catch (_) {}
  }

  Future<void> _hideNotice() async {
    try {
      if (!mounted) return;
      await _noticeCtrl.reverse();
      if (mounted) setState(() => _notice = null);
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Contact panel
  // ------------------------------------------------------------------
  void _togglePanel() {
    setState(() => _panelOpen = !_panelOpen);
    if (_panelOpen) {
      _panelCtrl.forward();
    } else {
      _panelCtrl.reverse();
    }
  }

  Future<void> _openTelegram() async {
    try {
      await launchUrl(Uri.parse(_telegramUrl), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _noticeBox(_Notice notice) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero).animate(_noticeAnim),
      child: FadeTransition(
        opacity: _noticeAnim,
        child: Container(
          decoration: BoxDecoration(
            color: _boxNavy,
            border: Border.all(color: nettestGold, width: 1.5),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6)),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: nettestGold, width: 1.6),
                ),
                child: const Center(
                  child: Text(
                    '!',
                    style: TextStyle(
                      color: nettestGold,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Manrope',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (notice.title.isNotEmpty)
                      Text(
                        notice.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: _fontFor(notice.title),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    if (notice.body.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: notice.title.isNotEmpty ? 4 : 2),
                        child: Text(
                          notice.body,
                          style: TextStyle(
                            color: const Color(0xFFC6CBE4),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            fontFamily: _fontFor(notice.body),
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactPanel() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 302,
          decoration: BoxDecoration(
            color: _panelNavy,
            border: Border.all(color: nettestGold, width: 1.5),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CONTACT US',
                style: TextStyle(
                  color: nettestGold,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                  fontFamily: 'Manrope',
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _telegramBadge(54),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thue Htet Aung',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Manrope',
                          decoration: TextDecoration.none,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Telegram',
                        style: TextStyle(
                          color: Color(0xFF9AA3C4),
                          fontSize: 13,
                          fontFamily: 'Manrope',
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Material(
                color: _tgBlue,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _openTelegram,
                  child: const SizedBox(
                    height: 48,
                    child: Center(
                      child: Text(
                        'Open Telegram',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Manrope',
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: -15,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTap: _togglePanel,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(color: Color(0xFF343A64), shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 17, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sideButton() {
    return GestureDetector(
      onTap: _togglePanel,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 124,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 34,
              height: 118,
              decoration: BoxDecoration(
                color: _panelNavy,
                border: Border.all(color: nettestViolet, width: 1.8),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            _telegramBadge(46),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    return Stack(
      children: [
        // Contact side pill — docked on the right edge, always visible.
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: Center(child: _sideButton()),
        ),
        // Dim + contact panel (present only while opening/open/closing).
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _panelAnim,
            builder: (context, _) {
              final v = _panelAnim.value;
              if (v <= 0) return const SizedBox.shrink();
              return Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _togglePanel,
                      child: ColoredBox(color: Colors.black.withValues(alpha: 0.55 * v)),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(345 * (1 - v), 0),
                        child: Opacity(opacity: v, child: _contactPanel()),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        // Message Box — top of Home, centred on the content column.
        if (notice != null)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rail = nettestRailWidth(context);
                final avail = constraints.maxWidth - rail;
                final width = avail > 632 ? 600.0 : (avail - 32).clamp(0, 600).toDouble();
                return Padding(
                  padding: EdgeInsets.only(right: rail),
                  child: Center(
                    child: SizedBox(width: width, child: _noticeBox(notice)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
