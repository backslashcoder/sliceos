import 'package:file_selector/file_selector.dart';

const _videoTypes = XTypeGroup(
  label: 'Video',
  extensions: ['mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v'],
);

/// Shows the system file dialog. Returns null when the user cancels.
Future<String?> pickVideoFile() async =>
    (await openFile(acceptedTypeGroups: const [_videoTypes]))?.path;

/// Asks where to save an exported MP4. Returns null when the user cancels.
Future<String?> pickClipSaveLocation(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'MP4 video', extensions: ['mp4']),
    ],
  );
  final path = location?.path;
  if (path == null) return null;
  return path.toLowerCase().endsWith('.mp4') ? path : '$path.mp4';
}
