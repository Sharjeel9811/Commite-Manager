import 'package:committee_manager/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Boots the real app on a real device and proves it survives start-up.
///
/// Every other test in this project runs against fakes and an in-memory
/// database, so none of them can catch the failure that actually stops people
/// shipping: a crash in the composition root, a database that will not open on a
/// device filesystem, or a provider that throws while wiring itself up. This
/// test does none of that stubbing. If the app cannot start, this fails.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app starts and renders its first screen', (
    WidgetTester tester,
  ) async {
    await app.main();

    // `pumpAndSettle` cannot be used here: the welcome screen has a focused
    // text field, and its cursor blinks forever, so the frame scheduler never
    // goes quiet and `pumpAndSettle` times out on a perfectly healthy app.
    // Pumping a fixed number of frames waits for start-up without that trap.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 500));

    final Finder welcome = find.textContaining('Welcome', findRichText: true);
    final Finder getStarted = find.textContaining('Get Started');
    final Finder committee = find.textContaining('Committee', findRichText: true);
    final MaterialApp app_ = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(
      welcome.evaluate().isNotEmpty ||
          getStarted.evaluate().isNotEmpty ||
          committee.evaluate().isNotEmpty,
      isTrue,
      reason: 'no recognisable first screen was found',
    );
    expect(app_.title, isNotEmpty, reason: 'the app should name itself');
  });

  testWidgets('the first screen survives a frame with no exceptions', (
    WidgetTester tester,
  ) async {
    await app.main();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Any error during those pumps would already have failed the test above;
    // this one exists to catch an error that only appears on a later frame.
    expect(tester.takeException(), isNull);
  });
}
