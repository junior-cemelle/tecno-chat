import 'package:flutter/material.dart';
import '../../presentation/chats/video_viewer_modal.dart';

/// En web: abre el video en un modal centrado sobre la página actual.
void launchVideoPlayer(BuildContext context, String url) {
  showVideoViewer(context, url);
}
