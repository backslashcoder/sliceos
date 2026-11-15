import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/theme/app_theme.dart';
import 'core/database/app_database.dart';
import 'core/processing/engine_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppDatabase database;
  try {
    final directory = await getApplicationSupportDirectory();
    await Directory(directory.path).create(recursive: true);
    database = AppDatabase.open(p.join(directory.path, 'sliceos.db'));
  } on Object catch (error) {
    runApp(_StartupFailure(message: '$error'));
    return;
  }
  runApp(SliceOsApp(engine: createVideoEngine(), database: database));
}

/// Shown instead of the app when the local library cannot be opened. The
/// database file is left untouched so nothing is lost.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SliceOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'SliceOS could not open your project library',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
