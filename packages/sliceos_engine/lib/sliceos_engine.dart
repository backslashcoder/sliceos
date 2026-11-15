/// SliceOS processing engine.
///
/// UI and business logic depend only on [VideoEngine] and the shared models.
/// Platform adapters ([WindowsVideoEngine], [AndroidVideoEngine]) hide all
/// native process and library details.
library;

export 'src/android/android_video_engine.dart';
export 'src/errors.dart';
export 'src/ffmpeg/ffmpeg_binaries.dart';
export 'src/highlights/candidate_validator.dart';
export 'src/highlights/heuristic_highlight_detector.dart';
export 'src/models/clip.dart';
export 'src/models/clip_candidate.dart';
export 'src/models/media_info.dart';
export 'src/models/processing_job.dart';
export 'src/models/requests.dart';
export 'src/models/transcript.dart';
export 'src/transcript/subtitle_parser.dart';
export 'src/video_engine.dart';
export 'src/windows/windows_video_engine.dart';
