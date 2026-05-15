import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/main.dart';
import 'package:mobile_flutter/src/native_core/native_models.dart';

void main() {
  testWidgets('Flames Flutter shell renders native status', (tester) async {
    await tester.pumpWidget(
      FlamesMobileApp(
        snapshotFuture: Future.value(
          const NativeCoreSnapshot(
            engineName: 'Test Native Core',
            message: 'Ready',
            rustReady: true,
            cppReady: true,
            sampleScore: .72,
            source: 'test',
            rankings: [
              RankedPreviewItem(
                id: 'one',
                title: 'Streetwear drop in SoHo',
                score: .91,
                reason: 'fashion + fresh signal',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Flames'), findsOneWidget);
    expect(find.text('Test Native Core'), findsOneWidget);
    expect(find.text('Streetwear drop in SoHo'), findsWidgets);
  });
}
