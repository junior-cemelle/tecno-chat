import 'package:flutter/material.dart';
import '../../presentation/chats/video_player_screen.dart';

void launchVideoPlayer(BuildContext context, String url) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => VideoPlayerScreen(url: url),
  ));
}
