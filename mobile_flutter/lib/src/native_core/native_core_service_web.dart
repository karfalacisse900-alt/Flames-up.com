import 'native_models.dart';

class NativeCoreService {
  static Future<NativeCoreSnapshot> boot() async {
    final rankings = _rankFallback(_sampleItems);

    return NativeCoreSnapshot(
      engineName: 'Flames Native Core',
      message: 'Web preview is using the Dart mirror. Rust/C++ activates on mobile and desktop builds.',
      rustReady: false,
      cppReady: false,
      sampleScore: rankings.first.score,
      rankings: rankings,
      source: 'Flutter web preview',
    );
  }
}

const _sampleItems = [
  _PreviewSignal('fashion-drop', 'Streetwear drop in SoHo', 'fashion', 0.95, 2.0, 0.8, 1.4),
  _PreviewSignal('park-night', 'Late night picnic loop', 'social', 0.74, 0.5, 0.72, 2.8),
  _PreviewSignal('art-house', 'Gallery opening downtown', 'art', 0.68, 5.5, 0.9, 1.7),
  _PreviewSignal('club-pulse', 'Club set after midnight', 'nightlife', 0.88, 1.2, 0.66, 4.2),
];

List<RankedPreviewItem> _rankFallback(List<_PreviewSignal> items) {
  final ranked = items.map((item) {
    final recency = 1 / (1 + item.ageHours / 12);
    final proximity = 1 / (1 + item.distanceKm / 8);
    final score = item.affinity * .46 + item.engagement * .28 + recency * .16 + proximity * .10;

    return RankedPreviewItem(
      id: item.id,
      title: item.title,
      score: score,
      reason: '${item.category} + fresh signal',
    );
  }).toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  return ranked;
}

class _PreviewSignal {
  const _PreviewSignal(
    this.id,
    this.title,
    this.category,
    this.affinity,
    this.ageHours,
    this.engagement,
    this.distanceKm,
  );

  final String id;
  final String title;
  final String category;
  final double affinity;
  final double ageHours;
  final double engagement;
  final double distanceKm;
}
