import 'package:sliceos_engine/sliceos_engine.dart';
import 'package:sliceos_engine/src/ffmpeg/ffmpeg_commands.dart';
import 'package:sliceos_engine/src/ffmpeg/ffmpeg_progress_parser.dart';
import 'package:sliceos_engine/src/ffmpeg/ffprobe_parser.dart';
import 'package:test/test.dart';

MediaInfo media({
  int width = 1920,
  int height = 1080,
  int rotation = 0,
  int durationMs = 60000,
  int audioTracks = 1,
}) => MediaInfo(
  path: 'in.mp4',
  formatName: 'mov,mp4',
  durationMs: durationMs,
  sizeBytes: 1,
  videoStreams: [
    VideoStreamInfo(
      index: 0,
      codec: 'h264',
      width: width,
      height: height,
      rotationDegrees: rotation,
      frameRate: 30,
      isVariableFrameRate: false,
    ),
  ],
  audioStreams: [
    for (var i = 0; i < audioTracks; i++)
      AudioStreamInfo(
        index: i + 1,
        codec: 'aac',
        channels: 2,
        sampleRate: 48000,
      ),
  ],
);

void main() {
  group('computeCrop', () {
    test('centres a 9:16 window in a 16:9 frame', () {
      final crop = computeCrop(
        sourceWidth: 1920,
        sourceHeight: 1080,
        aspectRatio: ClipAspectRatio.vertical9x16,
      );
      expect((crop.width, crop.height), (606, 1080));
      expect((crop.x, crop.y), (657, 0));
    });

    test('clamps the window inside the frame', () {
      final crop = computeCrop(
        sourceWidth: 1920,
        sourceHeight: 1080,
        aspectRatio: ClipAspectRatio.square1x1,
        crop: const CropConfig(centerX: 1, centerY: 0),
      );
      expect((crop.x, crop.y, crop.width, crop.height), (840, 0, 1080, 1080));
    });

    test('zoom shrinks the window and keeps even dimensions', () {
      final crop = computeCrop(
        sourceWidth: 1920,
        sourceHeight: 1080,
        aspectRatio: ClipAspectRatio.square1x1,
        crop: const CropConfig(zoom: 3),
      );
      expect((crop.width, crop.height), (360, 360));
      expect(crop.width.isEven && crop.height.isEven, isTrue);
    });
  });

  group('planRender', () {
    RenderPlan plan(
      RenderRequest request,
      MediaInfo info, {
      String encoder = 'libx264',
    }) => planRender(
      request,
      info,
      videoEncoder: encoder,
      outputPath: 'out.mp4.part',
    );

    test('builds a 1080x1920 vertical render from 4K', () {
      final result = plan(
        const RenderRequest(
          sourcePath: r'C:\my videos\tëst 视频.mp4',
          outputPath: 'out.mp4',
          startMs: 12345,
          endMs: 42345,
        ),
        media(width: 3840, height: 2160),
      );
      expect((result.outputWidth, result.outputHeight), (1080, 1920));
      expect(result.durationMs, 30000);
      final args = result.arguments;
      // The path is one argument: no shell quoting is involved.
      expect(args[args.indexOf('-i') + 1], r'C:\my videos\tëst 视频.mp4');
      expect(args[args.indexOf('-ss') + 1], '12.345');
      expect(args.indexOf('-ss'), lessThan(args.indexOf('-i')));
      expect(args[args.indexOf('-t') + 1], '30.000');
      expect(
        args[args.indexOf('-vf') + 1],
        'crop=1214:2160:1313:0,scale=1080:1920,setsar=1',
      );
      expect(args, containsAllInOrder(['-c:v', 'libx264']));
      expect(args.last, 'out.mp4.part');
    });

    test('never upscales beyond the cropped region', () {
      final result = plan(
        const RenderRequest(
          sourcePath: 'in.mp4',
          outputPath: 'out.mp4',
          startMs: 0,
          endMs: 5000,
        ),
        media(width: 1280, height: 720),
      );
      expect((result.outputWidth, result.outputHeight), (404, 718));
    });

    test('uses display dimensions for rotated phone footage', () {
      final result = plan(
        const RenderRequest(
          sourcePath: 'in.mp4',
          outputPath: 'out.mp4',
          startMs: 0,
          endMs: 5000,
        ),
        media(width: 1920, height: 1080, rotation: 90),
      );
      // Displayed as 1080x1920, so a 9:16 crop is nearly the full frame.
      expect((result.crop.width, result.crop.height), (1080, 1920));
      expect((result.outputWidth, result.outputHeight), (1080, 1920));
    });

    test('selects the requested audio track and omits audio when absent', () {
      const request = RenderRequest(
        sourcePath: 'in.mp4',
        outputPath: 'out.mp4',
        startMs: 0,
        endMs: 5000,
        audioTrack: 1,
      );
      expect(plan(request, media(audioTracks: 2)).arguments, contains('0:a:1'));
      expect(
        () => plan(request, media(audioTracks: 1)),
        throwsA(isA<InvalidRequestException>()),
      );
      final silent = plan(
        const RenderRequest(
          sourcePath: 'in.mp4',
          outputPath: 'o.mp4',
          startMs: 0,
          endMs: 5000,
        ),
        media(audioTracks: 0),
      ).arguments;
      expect(silent, isNot(contains('-c:a')));
    });

    test('uses a bitrate target for LGPL encoders', () {
      final args = plan(
        const RenderRequest(
          sourcePath: 'in.mp4',
          outputPath: 'o.mp4',
          startMs: 0,
          endMs: 5000,
        ),
        media(),
        encoder: 'h264_mf',
      ).arguments;
      expect(args, containsAllInOrder(['-c:v', 'h264_mf', '-b:v']));
      expect(args, isNot(contains('-crf')));
    });

    test('rejects ranges outside the media', () {
      for (final (start, end) in [
        (5000, 5000),
        (-1, 5000),
        (61000, 65000),
        (0, 61000),
      ]) {
        expect(
          () => plan(
            RenderRequest(
              sourcePath: 'in.mp4',
              outputPath: 'o.mp4',
              startMs: start,
              endMs: end,
            ),
            media(),
          ),
          throwsA(isA<InvalidRequestException>()),
          reason: '$start-$end',
        );
      }
    });
  });

  group('audioExtractionArguments', () {
    test('produces 16 kHz mono PCM', () {
      final args = audioExtractionArguments(
        const AudioExtractionRequest(sourcePath: 'in.mp4', outputPath: 'a.wav'),
        media(),
        outputPath: 'a.wav.part',
      );
      expect(
        args,
        containsAllInOrder(['-ac', '1', '-ar', '16000', '-c:a', 'pcm_s16le']),
      );
      expect(args, containsAllInOrder(['-f', 'wav', 'a.wav.part']));
    });

    test('rejects a source without audio', () {
      expect(
        () => audioExtractionArguments(
          const AudioExtractionRequest(
            sourcePath: 'in.mp4',
            outputPath: 'a.wav',
          ),
          media(audioTracks: 0),
          outputPath: 'a.wav.part',
        ),
        throwsA(isA<InvalidRequestException>()),
      );
    });
  });

  group('FfmpegProgressParser', () {
    test('emits one update per progress block', () {
      final parser = FfmpegProgressParser(totalMs: 10000);
      final updates = [
        for (final line in [
          'frame=30',
          'out_time_us=N/A',
          'speed=N/A',
          'progress=continue',
          'out_time_us=2500000',
          'speed=1.25x',
          'progress=continue',
          'out_time_us=9960000',
          'progress=end',
        ])
          ?parser.addLine(line),
      ];
      expect(updates.map((u) => u.fraction), [0.0, 0.25, 1.0]);
      expect(updates[1].speed, 1.25);
    });
  });

  group('parseFfprobeJson', () {
    test('reads streams, rotation, VFR and track tags', () {
      const json = '''
{
  "streams": [
    {"index": 0, "codec_name": "hevc", "codec_type": "video", "width": 3840,
     "height": 2160, "pix_fmt": "yuv420p", "r_frame_rate": "60/1",
     "avg_frame_rate": "5273/90", "bit_rate": "40000000",
     "disposition": {"attached_pic": 0},
     "side_data_list": [{"side_data_type": "Display Matrix", "rotation": -90}]},
    {"index": 1, "codec_name": "aac", "codec_type": "audio", "channels": 2,
     "sample_rate": "48000", "tags": {"language": "eng", "title": "Mic"}},
    {"index": 2, "codec_name": "aac", "codec_type": "audio", "channels": 6,
     "sample_rate": "44100", "tags": {"language": "hin"}},
    {"index": 3, "codec_name": "mjpeg", "codec_type": "video", "width": 600,
     "height": 600, "disposition": {"attached_pic": 1}},
    {"index": 4, "codec_type": "data"}
  ],
  "format": {"format_name": "mov,mp4,m4a,3gp,3g2,mj2", "duration": "3725.482000",
             "size": "18446744073", "bit_rate": "41000000"}
}''';
      final info = parseFfprobeJson(json, path: 'x.mp4');
      expect(info.durationMs, 3725482);
      expect(info.sizeBytes, 18446744073);
      expect(info.videoStreams, hasLength(1));
      final video = info.primaryVideo!;
      expect(video.rotationDegrees, 90);
      expect((video.displayWidth, video.displayHeight), (2160, 3840));
      expect(video.isVariableFrameRate, isTrue);
      expect(video.frameRate, closeTo(58.59, 0.01));
      expect(info.audioStreams.map((a) => a.language), ['eng', 'hin']);
      expect(info.audioStreams.first.title, 'Mic');
      expect(info.audioStreams.last.channels, 6);
    });

    test('reads the legacy rotate tag', () {
      const json = '''
{"streams": [{"index": 0, "codec_name": "h264", "codec_type": "video",
  "width": 1920, "height": 1080, "r_frame_rate": "30/1", "avg_frame_rate": "30/1",
  "tags": {"rotate": "270"}}],
 "format": {"format_name": "mp4", "duration": "1.0", "size": "10"}}''';
      final video = parseFfprobeJson(json, path: 'x.mp4').primaryVideo!;
      expect(video.rotationDegrees, 270);
      expect(video.isVariableFrameRate, isFalse);
    });

    test('rejects output without a format section', () {
      expect(
        () => parseFfprobeJson('{}', path: 'x.txt'),
        throwsA(isA<InvalidMediaException>()),
      );
      expect(
        () => parseFfprobeJson('not json', path: 'x.txt'),
        throwsA(isA<InvalidMediaException>()),
      );
    });
  });
}
