import 'package:flutter/services.dart';

/// A saved clip, its size after rotation.
class VideoClip {
  const VideoClip({required this.duration, required this.width, required this.height});
  final Duration duration;
  final int width, height;
  double get aspect => width / height;
}

/// One frame: the upright JPEG, its 32×18 gray thumbnail, and when it shows.
class VideoFrame {
  const VideoFrame({required this.jpeg, required this.thumb, required this.time});
  final Uint8List jpeg, thumb;
  final Duration time;
}

/// The Runner's own frame reader (AVAssetReader on iOS, MediaMetadataRetriever
/// on Android). One clip at a time; [open] closes any open one.
abstract final class VideoFrames {
  static const channel = MethodChannel('shuttle_live/video_frames');

  /// Throws a [PlatformException] (`unreadable`) if [path] isn't a readable video.
  static Future<VideoClip> open(String path) async {
    final m = (await channel.invokeMapMethod<String, Object?>('open', {'path': path}))!;
    return VideoClip(
      duration: Duration(microseconds: m['durationUs']! as int),
      width: m['width']! as int,
      height: m['height']! as int,
    );
  }

  /// The next frame in order, or null at the end of the clip.
  static Future<VideoFrame?> next() async {
    final m = await channel.invokeMapMethod<String, Object?>('next');
    if (m == null) return null;
    return VideoFrame(
      jpeg: m['jpeg']! as Uint8List,
      thumb: m['thumb']! as Uint8List,
      time: Duration(microseconds: m['timeUs']! as int),
    );
  }

  static Future<void> close() => channel.invokeMethod<void>('close');
}

/// Mean absolute difference of two equal-length gray thumbnails, 0–255.
double thumbDiff(Uint8List a, Uint8List b) {
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}

// ponytail: tuned on the owner's first clip (Task 7); broadcast cameras pan a little.
const cutThreshold = 40.0;

/// Tells the court view from a TV cut by comparing each frame's thumbnail with
/// the one taken when the court was set. Flips to off-court after 2 frames in a
/// row over [cutThreshold], and back after 3 in a row at or under it.
class CutDetector {
  CutDetector(this.reference);

  final Uint8List reference;
  bool offCourt = false;
  int _run = 0;

  /// Feeds one thumbnail; returns the new [offCourt].
  bool update(Uint8List thumb) {
    final over = thumbDiff(thumb, reference) > cutThreshold;
    if (over == offCourt) {
      _run = 0;
    } else if (++_run >= (offCourt ? 3 : 2)) {
      offCourt = over;
      _run = 0;
    }
    return offCourt;
  }
}
