import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sliceos/app/app.dart';
import 'package:sliceos/core/database/app_database.dart';
import 'package:sliceos/features/projects/project_repository.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import 'fake_video_engine.dart';

Future<void> pumpApp(
  WidgetTester tester,
  VideoEngine engine,
  Size size, {
  AppDatabase? database,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SliceOsApp(engine: engine, database: database ?? AppDatabase.inMemory()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop layout shows the sidebar and dashboard empty state', (
    tester,
  ) async {
    await pumpApp(tester, FakeVideoEngine(), const Size(1280, 800));
    expect(find.text('SliceOS'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('No projects yet'), findsOneWidget);
  });

  testWidgets('phone layout uses bottom navigation', (tester) async {
    await pumpApp(tester, FakeVideoEngine(), const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a video to begin'), findsOneWidget);
  });

  testWidgets('import explains when the engine is unavailable', (tester) async {
    // The real Android engine, which is not implemented yet.
    await pumpApp(tester, AndroidVideoEngine(), const Size(400, 800));
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(find.text('Video processing is not available'), findsOneWidget);
    expect(find.text('Choose video'), findsNothing);
  });

  testWidgets('settings lists engine capabilities', (tester) async {
    await pumpApp(tester, FakeVideoEngine(), const Size(1280, 800));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Processing engine'), findsOneWidget);
    expect(find.text('libx264'), findsOneWidget);
  });

  testWidgets('dashboard lists saved projects and opens one', (tester) async {
    final database = AppDatabase.inMemory();
    await ProjectRepository(database)
        .create(name: 'Podcast episode 12', media: sampleMedia);

    await pumpApp(
      tester,
      FakeVideoEngine(),
      const Size(1280, 800),
      database: database,
    );
    expect(find.text('No projects yet'), findsNothing);
    // The fake path does not exist on disk, so the source is reported missing.
    expect(find.text('Source video not found'), findsOneWidget);

    await tester.tap(find.text('Podcast episode 12'));
    await tester.pumpAndSettle();
    expect(find.text('Locate video'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
  });
}
