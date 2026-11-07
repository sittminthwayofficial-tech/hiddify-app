import 'dart:async';

import 'package:flutter/material.dart';

import 'package:hiddify/features/nettest/facade_catalog.dart';
import 'package:hiddify/features/nettest/mask_gate.dart';

/// NetTest VPN v1.4 — DISGUISE facade ("MovieLand").
///
/// A fully offline, inert streaming-app facade. All content comes
/// from facade_catalog.dart and bundled assets — no network, no
/// state outside this widget tree, and no vocabulary anywhere that
/// hints at the app underneath. Navigation is state-based (no
/// Navigator interplay with the host app): home tabs, a detail page
/// and a player page that always ends in a "cannot load" message,
/// which is unremarkable on Myanmar networks.
///
/// The only way out is the hidden door: [onDoorHold] fires after a
/// 5-second continuous hold on the header logo (see mask_gate.dart).

const _facadeBg = Color(0xFF0B0F24);
const _facadeSurface = Color(0xFF161B36);
const _facadeGold = Color(0xFFE8C476);
const _facadeTextDim = Color(0xFF9AA3C4);

class FacadeApp extends StatefulWidget {
  const FacadeApp({super.key, required this.onDoorHold});

  /// Fired when the hidden-door hold completes on the header logo.
  final VoidCallback onDoorHold;

  @override
  State<FacadeApp> createState() => _FacadeAppState();
}

enum _FacadeRoute { tabs, detail, player, premium, faq }

class _FacadeAppState extends State<FacadeApp> {
  _FacadeRoute _route = _FacadeRoute.tabs;
  FacadeItem? _selected;

  void _openDetail(FacadeItem item) {
    setState(() {
      _selected = item;
      _route = _FacadeRoute.detail;
    });
  }

  void _openPlayer(FacadeItem item) {
    setState(() {
      _selected = item;
      _route = _FacadeRoute.player;
    });
  }

  void _backToTabs() {
    setState(() {
      _route = _FacadeRoute.tabs;
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _facadeBg,
        colorScheme: const ColorScheme.dark(
          surface: _facadeSurface,
          primary: _facadeGold,
          onSurface: Colors.white,
        ),
        fontFamily: 'Manrope',
        appBarTheme: const AppBarTheme(
          backgroundColor: _facadeBg,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            fontFamily: 'Manrope',
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: _facadeSurface,
          indicatorColor: Color(0xFF2A3160),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Manrope'),
          ),
          iconTheme: WidgetStatePropertyAll(IconThemeData(color: Colors.white)),
        ),
      ),
      child: switch (_route) {
        _FacadeRoute.tabs => _FacadeTabs(
            onDoorHold: widget.onDoorHold,
            onOpenDetail: _openDetail,
            onOpenPlayer: _openPlayer,
            onOpenPremium: () => setState(() => _route = _FacadeRoute.premium),
            onOpenFaq: () => setState(() => _route = _FacadeRoute.faq),
          ),
        _FacadeRoute.detail => _FacadeDetail(
            item: _selected!,
            onBack: _backToTabs,
            onPlay: () => _openPlayer(_selected!),
          ),
        _FacadeRoute.player => _FacadePlayer(
            item: _selected!,
            onBack: () => setState(() => _route = _FacadeRoute.detail),
          ),
        _FacadeRoute.premium => _FacadePremium(onBack: _backToTabs),
        _FacadeRoute.faq => _FacadeFaq(onBack: _backToTabs),
      },
    );
  }
}

/// The drawn brand mark: a gold ring with a white play triangle —
/// deliberately unrelated to the NetTest bolt.
class FacadeLogo extends StatelessWidget {
  const FacadeLogo({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PlayMarkPainter(),
    );
  }
}

class _PlayMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.46;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.07
        ..color = _facadeGold,
    );
    final tri = Path()
      ..moveTo(c.dx - r * 0.30, c.dy - r * 0.42)
      ..lineTo(c.dx - r * 0.30, c.dy + r * 0.42)
      ..lineTo(c.dx + r * 0.48, c.dy)
      ..close();
    canvas.drawPath(tri, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Tabs shell (Home / Movies / Series / More)
// ---------------------------------------------------------------------------

class _FacadeTabs extends StatefulWidget {
  const _FacadeTabs({
    required this.onDoorHold,
    required this.onOpenDetail,
    required this.onOpenPlayer,
    required this.onOpenPremium,
    required this.onOpenFaq,
  });

  final VoidCallback onDoorHold;
  final void Function(FacadeItem) onOpenDetail;
  final void Function(FacadeItem) onOpenPlayer;
  final VoidCallback onOpenPremium;
  final VoidCallback onOpenFaq;

  @override
  State<_FacadeTabs> createState() => _FacadeTabsState();
}

class _FacadeTabsState extends State<_FacadeTabs> {
  int _tab = 0;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _facadeBg,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            HoldGesture(
              onComplete: widget.onDoorHold,
              ringSize: 44,
              child: const FacadeLogo(size: 34),
            ),
            const SizedBox(width: 10),
            const Text(facadeBrandName),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _HomeTab(
            query: _query,
            onQueryChanged: (q) => setState(() => _query = q),
            onOpenDetail: widget.onOpenDetail,
            onOpenPlayer: widget.onOpenPlayer,
          ),
          _GridTab(
            items: facadeCatalog.where((i) => i.kind == FacadeKind.movie).toList(),
            onOpenDetail: widget.onOpenDetail,
          ),
          _GridTab(
            items: facadeCatalog.where((i) => i.kind == FacadeKind.series).toList(),
            onOpenDetail: widget.onOpenDetail,
          ),
          _MoreTab(onOpenPremium: widget.onOpenPremium, onOpenFaq: widget.onOpenFaq),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.movie_rounded), label: 'Movies'),
          NavigationDestination(icon: Icon(Icons.tv_rounded), label: 'Series'),
          NavigationDestination(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.query,
    required this.onQueryChanged,
    required this.onOpenDetail,
    required this.onOpenPlayer,
  });

  final String query;
  final ValueChanged<String> onQueryChanged;
  final void Function(FacadeItem) onOpenDetail;
  final void Function(FacadeItem) onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      final results = facadeCatalog
          .where((i) => i.title.toLowerCase().contains(q))
          .toList();
      return Column(
        children: [
          _SearchBar(query: query, onQueryChanged: onQueryChanged),
          Expanded(
            child: results.isEmpty
                ? const Center(
                    child: Text(
                      'No results found',
                      style: TextStyle(color: _facadeTextDim),
                    ),
                  )
                : _PosterGrid(items: results, onOpenDetail: onOpenDetail),
          ),
        ],
      );
    }
    final trending = facadeCatalog.where((i) => i.trending).toList();
    final movies = facadeCatalog.where((i) => i.kind == FacadeKind.movie).toList();
    final series = facadeCatalog.where((i) => i.kind == FacadeKind.series).toList();
    final featured = facadeCatalog.firstWhere((i) => i.id == 6);
    return ListView(
      children: [
        _SearchBar(query: query, onQueryChanged: onQueryChanged),
        GestureDetector(
          onTap: () => onOpenDetail(featured),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  Image.asset(
                    facadeBannerAsset,
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: FilledButton.icon(
                      onPressed: () => onOpenPlayer(featured),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Watch Now'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _facadeGold,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _PosterRow(title: 'Trending Now', items: trending, onOpenDetail: onOpenDetail),
        _PosterRow(title: 'Movies', items: movies, onOpenDetail: onOpenDetail),
        _PosterRow(title: 'Series', items: series, onOpenDetail: onOpenDetail),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.query, required this.onQueryChanged});

  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        onChanged: onQueryChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search movies & series',
          hintStyle: const TextStyle(color: _facadeTextDim),
          prefixIcon: const Icon(Icons.search_rounded, color: _facadeTextDim),
          filled: true,
          fillColor: _facadeSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
        ),
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  const _PosterRow({required this.title, required this.items, required this.onOpenDetail});

  final String title;
  final List<FacadeItem> items;
  final void Function(FacadeItem) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 216,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => SizedBox(
              width: 118,
              child: _PosterCard(
                item: items[i],
                onTap: () => onOpenDetail(items[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.item, required this.onTap});

  final FacadeItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Image.asset(item.posterAsset, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          Text(
            '${item.year}  •  ★ ${item.rating.toStringAsFixed(1)}',
            style: const TextStyle(color: _facadeTextDim, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _GridTab extends StatelessWidget {
  const _GridTab({required this.items, required this.onOpenDetail});

  final List<FacadeItem> items;
  final void Function(FacadeItem) onOpenDetail;

  @override
  Widget build(BuildContext context) => _PosterGrid(items: items, onOpenDetail: onOpenDetail);
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items, required this.onOpenDetail});

  final List<FacadeItem> items;
  final void Function(FacadeItem) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => _PosterCard(
        item: items[i],
        onTap: () => onOpenDetail(items[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail + player
// ---------------------------------------------------------------------------

class _FacadeDetail extends StatelessWidget {
  const _FacadeDetail({required this.item, required this.onBack, required this.onPlay});

  final FacadeItem item;
  final VoidCallback onBack;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _facadeBg,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        title: const Text(''),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(item.posterAsset, width: 190, height: 285, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _chip('${item.year}'),
              _chip('★ ${item.rating.toStringAsFixed(1)}'),
              _chip(item.genre),
              if (item.kind == FacadeKind.series) _chip('Series'),
              if (item.myanmarSub) _chip('မြန်မာ စာတန်းထိုး'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            item.synopsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _facadeTextDim, fontSize: 14.5, height: 1.45),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
            style: FilledButton.styleFrom(
              backgroundColor: _facadeGold,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (item.kind == FacadeKind.series) ...[
            const SizedBox(height: 24),
            const Text(
              'Episodes',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (var e = 1; e <= 8; e++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline_rounded, color: _facadeTextDim),
                title: Text('Episode $e', style: const TextStyle(color: Colors.white, fontSize: 14.5)),
                trailing: const Text('45 min', style: TextStyle(color: _facadeTextDim, fontSize: 12)),
                onTap: onPlay,
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _facadeSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
    );
  }
}

class _FacadePlayer extends StatefulWidget {
  const _FacadePlayer({required this.item, required this.onBack});

  final FacadeItem item;
  final VoidCallback onBack;

  @override
  State<_FacadePlayer> createState() => _FacadePlayerState();
}

class _FacadePlayerState extends State<_FacadePlayer> {
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  void _startLoad() {
    _timer?.cancel();
    setState(() => _loading = true);
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onBack),
        title: Text(widget.item.title, style: const TextStyle(fontSize: 16)),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: _loading
                  ? const CircularProgressIndicator(color: _facadeGold)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Cannot load video. Check your connection and try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _startLoad,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _facadeGold,
                              side: const BorderSide(color: _facadeGold),
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// More tab + static pages
// ---------------------------------------------------------------------------

class _MoreTab extends StatelessWidget {
  const _MoreTab({required this.onOpenPremium, required this.onOpenFaq});

  final VoidCallback onOpenPremium;
  final VoidCallback onOpenFaq;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        const ListTile(
          leading: FacadeLogo(size: 40),
          title: Text(facadeBrandName, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
          subtitle: Text('Watch movies & series', style: TextStyle(color: _facadeTextDim)),
        ),
        const Divider(color: _facadeSurface),
        ListTile(
          leading: const Icon(Icons.workspace_premium_rounded, color: _facadeGold),
          title: const Text('Premium', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Ad-free, HD quality', style: TextStyle(color: _facadeTextDim)),
          trailing: const Icon(Icons.chevron_right_rounded, color: _facadeTextDim),
          onTap: onOpenPremium,
        ),
        ListTile(
          leading: const Icon(Icons.help_outline_rounded, color: _facadeTextDim),
          title: const Text('Help & FAQ', style: TextStyle(color: Colors.white)),
          trailing: const Icon(Icons.chevron_right_rounded, color: _facadeTextDim),
          onTap: onOpenFaq,
        ),
        const ListTile(
          leading: Icon(Icons.info_outline_rounded, color: _facadeTextDim),
          title: Text('About', style: TextStyle(color: Colors.white)),
          subtitle: Text(
            '$facadeBrandName — your pocket cinema. New titles every week.',
            style: TextStyle(color: _facadeTextDim),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Text('Version 1.0', style: TextStyle(color: _facadeTextDim, fontSize: 12)),
        ),
      ],
    );
  }
}

class _FacadePremium extends StatelessWidget {
  const _FacadePremium({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _facadeBg,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        title: const Text('Premium'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _plan(context, 'Monthly', '3,000 Ks / month'),
          _plan(context, 'Yearly', '25,000 Ks / year'),
          const SizedBox(height: 8),
          const Text(
            'Premium removes ads and unlocks HD quality on all titles.',
            style: TextStyle(color: _facadeTextDim, fontSize: 13.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _plan(BuildContext context, String name, String price) {
    return Card(
      color: _facadeSurface,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        subtitle: Text(price, style: const TextStyle(color: _facadeTextDim)),
        trailing: FilledButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment is not available right now.')),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: _facadeGold,
            foregroundColor: Colors.black,
          ),
          child: const Text('Subscribe'),
        ),
      ),
    );
  }
}

class _FacadeFaq extends StatelessWidget {
  const _FacadeFaq({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    const qa = [
      ('Why does a video fail to load?', 'Video loading depends on your internet connection. Check your connection and try again, or try a different title.'),
      ('How often are new titles added?', 'New movies and series are added every week.'),
      ('Can I watch offline?', 'Offline downloads are available with Premium.'),
      ('Which languages are supported?', 'Many titles include Burmese subtitles — look for the subtitle tag on the title page.'),
    ];
    return Scaffold(
      backgroundColor: _facadeBg,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
        title: const Text('Help & FAQ'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (q, a) in qa) ...[
            Text(q, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text(a, style: const TextStyle(color: _facadeTextDim, fontSize: 14, height: 1.45)),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
