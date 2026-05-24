import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math';

import 'package:image_picker/image_picker.dart';

const _videoMimeType = {
  'mp4': 'video/mp4',
  'mov': 'video/quicktime',
  'webm': 'video/webm',
  'ogg': 'video/ogg',
};

Future<XFile?> generateVideoThumbnail(XFile xfile) async {
  String? url;
  html.VideoElement? video;

  try {
    final videoBytes = await xfile.readAsBytes();
    final extension = xfile.name.contains('.')
        ? xfile.name.split('.').last.toLowerCase()
        : xfile.path.contains('.')
            ? xfile.path.split('.').last.toLowerCase()
            : 'mp4';
    final mimeType = _videoMimeType[extension] ?? 'video/mp4';
    final blob = html.Blob([videoBytes], mimeType);
    url = html.Url.createObjectUrlFromBlob(blob);
    video = html.VideoElement()
      ..src = url
      ..preload = 'metadata'
      ..crossOrigin = 'anonymous'
      ..muted = true
      ..autoplay = false
      ..style.display = 'none';

    html.document.body?.append(video);
    video.load();

    html.window.console.log('generateVideoThumbnail: waiting loadedmetadata for ${xfile.name}');
    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 10));

    final duration = video.duration;
    if (duration.isFinite && duration > 0.05) {
      video.currentTime = min(0.05, duration - 0.001);
      await video.onSeeked.first.timeout(const Duration(seconds: 10));
    }

    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width <= 0 || height <= 0) {
      html.window.console.warn('generateVideoThumbnail: invalid dimensions $width x $height for ${xfile.name}');
      return null;
    }

    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D.drawImageScaled(video, 0, 0, width.toDouble(), height.toDouble());
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.8);
    final base64Data = dataUrl.split(',').last;
    final imageBytes = base64Decode(base64Data);

    html.window.console.log('generateVideoThumbnail: created thumbnail for ${xfile.name}');
    return XFile.fromData(imageBytes, name: 'thumbnail.jpg', mimeType: 'image/jpeg');
  } catch (e, st) {
    html.window.console.error('generateVideoThumbnail failed for ${xfile.name}: $e');
    html.window.console.error(st.toString());
    return null;
  } finally {
    video?.remove();
    if (url != null) html.Url.revokeObjectUrl(url);
  }
}
