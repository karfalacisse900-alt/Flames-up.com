import '../rust/api/core.dart' as rust;
import '../rust/frb_generated.dart';
import 'native_models.dart';

class NativeCoreService {
  static Future<NativeCoreSnapshot> boot() async {
    await RustLib.init();

    final status = rust.initNativeCore();
    final ranked = rust.rankForYouItems(
      items: [
        rust.FeedSignal(
          id: 'fashion-drop',
          title: 'Streetwear drop in SoHo',
          category: 'fashion',
          location: 'SoHo',
          likes: 240,
          comments: 37,
          shares: 18,
          saves: 60,
          impressions: 4200,
          ageHours: 2.0,
          interestMatch: .95,
          distanceKm: 1.4,
        ),
        rust.FeedSignal(
          id: 'park-night',
          title: 'Late night picnic loop',
          category: 'social',
          location: 'Bryant Park',
          likes: 178,
          comments: 22,
          shares: 11,
          saves: 45,
          impressions: 3300,
          ageHours: .5,
          interestMatch: .74,
          distanceKm: 2.8,
        ),
        rust.FeedSignal(
          id: 'art-house',
          title: 'Gallery opening downtown',
          category: 'art',
          location: 'Lower East Side',
          likes: 198,
          comments: 31,
          shares: 14,
          saves: 58,
          impressions: 5100,
          ageHours: 5.5,
          interestMatch: .9,
          distanceKm: 1.7,
        ),
        rust.FeedSignal(
          id: 'club-pulse',
          title: 'Club set after midnight',
          category: 'nightlife',
          location: 'Manhattan',
          likes: 321,
          comments: 48,
          shares: 26,
          saves: 52,
          impressions: 8700,
          ageHours: 1.2,
          interestMatch: .88,
          distanceKm: 4.2,
        ),
      ],
    );

    return NativeCoreSnapshot(
      engineName: status.engineName,
      message: status.message,
      rustReady: status.rustReady,
      cppReady: status.cppReady,
      sampleScore: status.sampleScore,
      source: 'Rust + C++ native core',
      rankings: ranked
          .map(
            (item) => RankedPreviewItem(
              id: item.id,
              title: item.title,
              score: item.score,
              reason: item.reason,
            ),
          )
          .toList(),
    );
  }
}
