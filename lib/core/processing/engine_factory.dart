import 'dart:io';

import 'package:sliceos_engine/sliceos_engine.dart';

/// Picks the processing engine for the current platform. This is the only
/// place in the app that knows which concrete engine is in use.
VideoEngine createVideoEngine() =>
    Platform.isAndroid ? AndroidVideoEngine() : WindowsVideoEngine();
