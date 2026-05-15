import 'package:flutter/material.dart';

import 'src/native_core/native_core_service.dart';
import 'src/native_core/native_models.dart';

void main() {
  runApp(const FlamesMobileApp());
}

class FlamesMobileApp extends StatelessWidget {
  const FlamesMobileApp({super.key, this.snapshotFuture});

  final Future<NativeCoreSnapshot>? snapshotFuture;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flames Mobile',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F8F3),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF34D34A),
          brightness: Brightness.light,
        ),
        fontFamily: 'Arial',
      ),
      home: FlamesHomePage(
        snapshotFuture: snapshotFuture ?? NativeCoreService.boot(),
      ),
    );
  }
}

class FlamesHomePage extends StatelessWidget {
  const FlamesHomePage({super.key, required this.snapshotFuture});

  final Future<NativeCoreSnapshot> snapshotFuture;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<NativeCoreSnapshot>(
          future: snapshotFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;

            return CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _TopBar()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                    child: data == null
                        ? const _LoadingCore()
                        : _ForYouExperience(snapshot: data),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF34D34A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: const Icon(Icons.local_fire_department, color: Colors.black),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Flames',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () {},
                icon: const Icon(Icons.notifications_none),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black),
                onPressed: () {},
                icon: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              _TabPill(label: 'World Board', active: false),
              SizedBox(width: 10),
              _TabPill(label: 'For You', active: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: active ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: .12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.black,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LoadingCore extends StatelessWidget {
  const _LoadingCore();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 520,
      alignment: Alignment.center,
      child: const CircularProgressIndicator(color: Colors.black),
    );
  }
}

class _ForYouExperience extends StatelessWidget {
  const _ForYouExperience({required this.snapshot});

  final NativeCoreSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final top = snapshot.rankings.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NativeCoreBanner(snapshot: snapshot),
        const SizedBox(height: 16),
        _HeroPost(item: top),
        const SizedBox(height: 18),
        const Text(
          'Native ranking preview',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        ...snapshot.rankings.map((item) => _RankingTile(item: item)),
      ],
    );
  }
}

class _NativeCoreBanner extends StatelessWidget {
  const _NativeCoreBanner({required this.snapshot});

  final NativeCoreSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.engineName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              _StatusDot(label: 'Rust', on: snapshot.rustReady),
              const SizedBox(width: 8),
              _StatusDot(label: 'C++', on: snapshot.cppReady),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            snapshot.message,
            style: TextStyle(color: Colors.black.withValues(alpha: .62), height: 1.35),
          ),
          const SizedBox(height: 12),
          Text(
            '${snapshot.source} • score ${(snapshot.sampleScore * 100).toStringAsFixed(1)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? const Color(0xFF34D34A) : const Color(0xFFE9E9E4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black, width: .9),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _HeroPost extends StatelessWidget {
  const _HeroPost({required this.item});

  final RankedPreviewItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 560,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://images.unsplash.com/photo-1517457373958-b7bdd4587205?auto=format&fit=crop&w=900&q=80',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: Color(0xFF1B1B1B)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: .12),
                  Colors.black.withValues(alpha: .02),
                  Colors.black.withValues(alpha: .76),
                ],
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 18,
            right: 18,
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, color: Colors.black),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: const Color(0xFF34D34A),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 1.2),
                        ),
                        child: const Icon(Icons.add, size: 13, color: Colors.black),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Rosalie Wise\nWeb Design',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ),
              ],
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 31,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.reason,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _ActionButton(icon: Icons.favorite, label: '532', onPressed: () {}),
                    const SizedBox(width: 10),
                    _ActionButton(icon: Icons.mode_comment, label: '42', onPressed: () {}),
                    const Spacer(),
                    _ActionButton(icon: Icons.bookmark, label: '', filled: true, onPressed: () {}),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor:
            filled ? const Color(0xFF34D34A) : Colors.white.withValues(alpha: .22),
        foregroundColor: filled ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 13 : 15, vertical: 12),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: label.isEmpty ? const SizedBox.shrink() : Text(label),
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.item});

  final RankedPreviewItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: .07)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF34D34A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black, width: 1.2),
            ),
            child: Text(
              '${(item.score * 100).round()}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  item.reason,
                  style: TextStyle(color: Colors.black.withValues(alpha: .55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
