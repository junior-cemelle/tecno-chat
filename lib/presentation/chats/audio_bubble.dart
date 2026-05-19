import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/message_model.dart';

class AudioBubble extends StatefulWidget {
  final MessageModel msg;
  final bool isMe;
  const AudioBubble({super.key, required this.msg, required this.isMe});

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  bool _playing = false;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  @override
  void didUpdateWidget(AudioBubble old) {
    super.didUpdateWidget(old);
    if (old.msg.content != widget.msg.content) {
      _player.stop();
      setState(() {
        _position = Duration.zero;
        _total = Duration.zero;
        _playing = false;
        _loading = true;
        _error = false;
      });
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final dur = await _player.setUrl(widget.msg.content);
      if (mounted) setState(() { _total = dur ?? Duration.zero; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
      return;
    }

    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s.playing);
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.stop();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_error) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progress =>
      _total.inMilliseconds > 0
          ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMe = widget.isMe;
    final bubbleColor = isMe ? AppColors.green : cs.surfaceContainerHighest;
    final onBubble = isMe ? Colors.white : cs.onSurface;
    final timeColor = isMe ? Colors.white.withAlpha(160) : cs.onSurface.withAlpha(120);
    final activeWave = isMe ? Colors.white : AppColors.green;
    final inactiveWave = isMe ? Colors.white.withAlpha(80) : cs.onSurface.withAlpha(60);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
          minWidth: 200,
        ),
        margin: EdgeInsets.only(
          top: 4, bottom: 1,
          left: isMe ? 48 : 0,
          right: isMe ? 0 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Botón play/pause
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: onBubble.withAlpha(20),
                    ),
                    child: _loading
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: onBubble),
                          )
                        : _error
                            ? Icon(Icons.error_outline, color: onBubble, size: 20)
                            : Icon(
                                _playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: onBubble,
                                size: 22,
                              ),
                  ),
                ),
                const SizedBox(width: 8),

                // Waveform con progress
                Expanded(
                  child: GestureDetector(
                    onTapDown: (d) => _seekFromTap(d, context),
                    child: SizedBox(
                      height: 32,
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          data: widget.msg.waveformData,
                          progress: _progress,
                          activeColor: activeWave,
                          inactiveColor: inactiveWave,
                        ),
                        size: const Size(double.infinity, 32),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 2),

            // Tiempo + estado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _playing ? _fmt(_position) : _fmt(_total),
                  style: GoogleFonts.poppins(fontSize: 10, color: timeColor),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('HH:mm').format(widget.msg.timestamp),
                      style: GoogleFonts.poppins(fontSize: 10, color: timeColor),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 3),
                      _StatusIcon(status: widget.msg.status, color: timeColor),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _seekFromTap(TapDownDetails details, BuildContext context) {
    if (_total == Duration.zero) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    // Aproximamos la zona del waveform (después del botón ~56px)
    final waveStart = 56.0;
    final waveWidth = box.size.width - waveStart - 18;
    final tapX = details.localPosition.dx - waveStart;
    final ratio = (tapX / waveWidth).clamp(0.0, 1.0);
    _player.seek(Duration(
        milliseconds: (ratio * _total.inMilliseconds).round()));
  }
}

// ── Painter del waveform ──────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  const _WaveformPainter({
    required this.data,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  static const _barCount = 40;
  static const _minBarHeightRatio = 0.15;

  @override
  void paint(Canvas canvas, Size size) {
    final samples = _normalize(_resample(data, _barCount));
    final totalW = size.width;
    final barW = totalW / _barCount * 0.55;
    final gap = totalW / _barCount * 0.45;

    for (int i = 0; i < _barCount; i++) {
      final ratio = samples[i].clamp(_minBarHeightRatio, 1.0);
      final barH = ratio * size.height;
      final x = i * (barW + gap);
      final y = (size.height - barH) / 2;

      final paint = Paint()
        ..color = (i / _barCount) <= progress ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  // Reduce o expande la lista de amplitudes al tamaño objetivo
  List<double> _resample(List<double> src, int target) {
    if (src.isEmpty) {
      // Sin datos: genera un patrón genérico con aleatoriedad seeded
      final rng = math.Random(42);
      return List.generate(target, (_) => 0.2 + rng.nextDouble() * 0.6);
    }
    if (src.length == target) return src;
    final result = <double>[];
    for (int i = 0; i < target; i++) {
      final start = (i * src.length / target).floor();
      final end = ((i + 1) * src.length / target).ceil().clamp(0, src.length);
      final chunk = src.sublist(start, end);
      result.add(chunk.reduce((a, b) => a + b) / chunk.length);
    }
    return result;
  }

  List<double> _normalize(List<double> data) {
    final maxVal = data.reduce(math.max);
    if (maxVal == 0) return data;
    return data.map((v) => v / maxVal).toList();
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.data != data;
}

// ── Status icon ───────────────────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final Color color;
  const _StatusIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sent => Icon(Icons.check, size: 12, color: color),
      MessageStatus.delivered => Icon(Icons.done_all, size: 12, color: color),
      MessageStatus.read =>
        Icon(Icons.done_all, size: 12, color: Colors.lightBlueAccent),
    };
  }
}
