class NativeCoreSnapshot {
  const NativeCoreSnapshot({
    required this.engineName,
    required this.message,
    required this.rustReady,
    required this.cppReady,
    required this.sampleScore,
    required this.rankings,
    required this.source,
  });

  final String engineName;
  final String message;
  final bool rustReady;
  final bool cppReady;
  final double sampleScore;
  final List<RankedPreviewItem> rankings;
  final String source;
}

class RankedPreviewItem {
  const RankedPreviewItem({
    required this.id,
    required this.title,
    required this.score,
    required this.reason,
  });

  final String id;
  final String title;
  final double score;
  final String reason;
}
