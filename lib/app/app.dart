import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sliceos_engine/sliceos_engine.dart';

import '../core/database/app_database.dart';
import '../features/import_video/video_file_picker.dart';
import '../features/import_video/video_import_cubit.dart';
import '../features/projects/project_cubit.dart';
import '../features/projects/project_repository.dart';
import '../features/rendering/render_cubit.dart';
import '../features/settings/settings_cubit.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class SliceOsApp extends StatefulWidget {
  const SliceOsApp({super.key, required this.engine, required this.database});

  final VideoEngine engine;
  final AppDatabase database;

  @override
  State<SliceOsApp> createState() => _SliceOsAppState();
}

class _SliceOsAppState extends State<SliceOsApp> {
  final _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    widget.engine.dispose();
    widget.database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsCubit(engine)..load()),
        BlocProvider(
          create: (_) => VideoImportCubit(engine, pickVideo: pickVideoFile),
        ),
        BlocProvider(create: (_) => RenderCubit(engine)),
        BlocProvider(
          create: (_) => ProjectCubit(
            ProjectRepository(widget.database),
            engine,
            pickVideo: pickVideoFile,
          )..load(),
        ),
      ],
      child: MaterialApp.router(
        title: 'SliceOS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
      ),
    );
  }
}
