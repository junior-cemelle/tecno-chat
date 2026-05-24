import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/platform/media_permissions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/call_model.dart';
import '../../providers/call_provider.dart';
import '../../providers/firestore_provider.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String callId;
  final String channelId;
  final bool isVideo;
  final bool isCaller;
  final String remoteUid; // Firebase UID del otro usuario

  const CallScreen({
    super.key,
    required this.callId,
    required this.channelId,
    required this.isVideo,
    required this.isCaller,
    required this.remoteUid,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  RtcEngine? _engine;
  int? _remoteAgoraUid;
  bool _localJoined = false;
  bool _callActive = false;
  bool _micMuted = false;
  bool _videoOff = false;
  bool _speakerOn = true;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  Timer? _ringingTimer;
  StreamSubscription<CallModel?>? _callSub;
  bool _ended = false;

  // Aspect ratio del video remoto, reportado por onVideoSizeChanged.
  // 16/9 mientras no llega el primer evento (mayoría de cámaras web/móviles).
  double _remoteAspect = 16 / 9;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _requestPermissions();
      _initAgora();
      _watchStatus();
    });
  }

  /// Solicita micrófono (y cámara si es videollamada) antes de inicializar
  /// Agora. En móvil el helper delega en Record; en web usa getUserMedia para
  /// disparar el diálogo del navegador de forma fiable.
  Future<void> _requestPermissions() async {
    await requestMediaPermissions(video: widget.isVideo);
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _timer?.cancel();
    _ringingTimer?.cancel();
    _engine?.leaveChannel();
    _engine?.release();
    super.dispose();
  }

  // ── Agora ──────────────────────────────────────────────────────────────────

  Future<void> _initAgora() async {
    final engine = createAgoraRtcEngine();
    await engine.initialize(const RtcEngineContext(
      appId: AppConstants.agoraAppId,
    ));

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (_, __) {
        if (!mounted) return;
        setState(() => _localJoined = true);
        // setEnableSpeakerphone solo es válido después de unirse al canal.
        // En web es no-op: el navegador gestiona la salida de audio.
        if (!kIsWeb) engine.setEnableSpeakerphone(_speakerOn);
      },
      onUserJoined: (_, remoteUid, __) {
        if (!mounted) return;
        setState(() {
          _remoteAgoraUid = remoteUid;
          _callActive = true;
        });
        _startTimer();
        _ringingTimer?.cancel();
      },
      onUserOffline: (_, __, ___) {
        if (mounted && !_ended) _finishCall(updateFirestore: false);
      },
      // Reporta el tamaño real del stream remoto (uid != 0) y del local
      // (uid == 0). Lo usamos para fijar el aspect ratio del AgoraVideoView
      // remoto y evitar que el SDK web lo recorte con object-fit: cover.
      onVideoSizeChanged: (_, __, uid, width, height, ___) {
        if (uid == 0 || width == 0 || height == 0 || !mounted) return;
        final ar = width / height;
        if ((ar - _remoteAspect).abs() > 0.01) {
          setState(() => _remoteAspect = ar);
        }
      },
      onError: (err, msg) => debugPrint('Agora error $err: $msg'),
    ));

    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.enableAudio();

    if (widget.isVideo) {
      await engine.enableVideo();
      await engine.startPreview();
    }

    await engine.joinChannel(
      token: '',
      channelId: widget.channelId,
      uid: 0,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );

    if (mounted) setState(() => _engine = engine);

    // Caller: timeout 60 s sin respuesta → missed
    if (widget.isCaller) {
      _ringingTimer = Timer(const Duration(seconds: 60), () {
        if (!_callActive && mounted) {
          ref
              .read(callServiceProvider)
              .updateStatus(widget.callId, CallStatus.missed);
          _finishCall(updateFirestore: false);
        }
      });
    }
  }

  void _watchStatus() {
    _callSub = ref
        .read(callServiceProvider)
        .watchCall(widget.callId)
        .listen((call) {
      if (call == null || _ended) return;
      final done = call.status == CallStatus.ended ||
          call.status == CallStatus.rejected ||
          call.status == CallStatus.missed;
      if (done && mounted) _finishCall(updateFirestore: false);
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _finishCall({required bool updateFirestore}) async {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    _ringingTimer?.cancel();
    if (updateFirestore) {
      if (_callActive) {
        await ref
            .read(callServiceProvider)
            .endCall(widget.callId, _elapsed.inSeconds);
      } else if (widget.isCaller) {
        await ref
            .read(callServiceProvider)
            .updateStatus(widget.callId, CallStatus.missed);
      }
    }
    await _engine?.leaveChannel();
    if (mounted) context.pop();
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────

  String get _elapsedText {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _statusLabel {
    if (_callActive) return _elapsedText;
    return widget.isCaller ? 'Llamando…' : 'Conectando…';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final remoteAsync = ref.watch(userProfileProvider(widget.remoteUid));
    final remoteName = switch (remoteAsync) {
      AsyncData(value: final u) when u != null => u.displayName,
      _ => 'Usuario',
    };
    final remotePhoto = switch (remoteAsync) {
      AsyncData(value: final u) when u != null && u.avatarUrl.isNotEmpty =>
        u.avatarUrl,
      _ => null,
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finishCall(updateFirestore: true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: widget.isVideo && _engine != null
            ? _buildVideo(remoteName, remotePhoto)
            : _buildAudio(remoteName, remotePhoto),
      ),
    );
  }

  // ── Video call layout ──────────────────────────────────────────────────────

  Widget _buildVideo(String name, String? photo) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fondo: video remoto o avatar si todavía no conecta.
        //
        // El `renderMode: renderModeFit` del VideoCanvas no se respeta en el
        // Agora Web SDK (aplica object-fit: cover internamente al <video>
        // HTML). Para forzar letterbox confiable cross-platform envolvemos
        // el AgoraVideoView en Center + AspectRatio con la relación real
        // del stream remoto (capturada por onVideoSizeChanged); así el
        // widget se dimensiona al tamaño del frame y queda fondo negro
        // alrededor cuando la ventana es más ancha o más alta.
        _remoteAgoraUid != null
            ? ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _remoteAspect,
                    child: AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: _engine!,
                        canvas: VideoCanvas(
                          uid: _remoteAgoraUid!,
                          renderMode: RenderModeType.renderModeFit,
                        ),
                        connection: RtcConnection(channelId: widget.channelId),
                      ),
                    ),
                  ),
                ),
              )
            : _Placeholder(name: name, photo: photo, status: _statusLabel),

        // PIP local (abajo-derecha)
        if (!_videoOff && _localJoined)
          Positioned(
            right: 16,
            bottom: 116,
            width: 88,
            height: 132,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AgoraVideoView(
                controller: VideoViewController(
                  rtcEngine: _engine!,
                  canvas: const VideoCanvas(uid: 0),
                ),
              ),
            ),
          ),

        // Header (nombre + estado)
        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  Text(_statusLabel,
                      style: GoogleFonts.poppins(
                          color: Colors.white.withAlpha(180), fontSize: 13)),
                ],
              ),
            ),
          ),
        ),

        // Controles (abajo)
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withAlpha(200),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Btn(
                    icon: _micMuted ? Icons.mic_off : Icons.mic,
                    label: _micMuted ? 'Activar mic' : 'Silenciar',
                    onTap: () {
                      setState(() => _micMuted = !_micMuted);
                      _engine?.muteLocalAudioStream(_micMuted);
                    },
                  ),
                  _Btn(
                    icon: _videoOff ? Icons.videocam_off : Icons.videocam,
                    label: _videoOff ? 'Cámara' : 'Apagar cam',
                    onTap: () {
                      setState(() => _videoOff = !_videoOff);
                      _engine?.enableLocalVideo(!_videoOff);
                    },
                  ),
                  // En web no hay forma fiable de cambiar entre cámaras
                  // (depende de los devices disponibles), así que ocultamos
                  // el botón en lugar de mostrarlo sin función.
                  if (!kIsWeb)
                    _Btn(
                      icon: Icons.flip_camera_ios_outlined,
                      label: 'Voltear',
                      onTap: () => _engine?.switchCamera(),
                    ),
                  _Btn(
                    icon: Icons.call_end,
                    label: 'Colgar',
                    color: AppColors.error,
                    onTap: () => _finishCall(updateFirestore: true),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Audio call layout ──────────────────────────────────────────────────────

  Widget _buildAudio(String name, String? photo) {
    return Column(
      children: [
        const Spacer(),
        SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarWidget(
                  photoUrl: photo, displayName: name, uid: widget.remoteUid, radius: 52),
              const SizedBox(height: 20),
              Text(name,
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(_statusLabel,
                  style: GoogleFonts.poppins(
                      color: Colors.white.withAlpha(180), fontSize: 15)),
            ],
          ),
        ),
        const Spacer(),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Btn(
                  icon: _micMuted ? Icons.mic_off : Icons.mic,
                  label: _micMuted ? 'Activar mic' : 'Silenciar',
                  onTap: () {
                    setState(() => _micMuted = !_micMuted);
                    _engine?.muteLocalAudioStream(_micMuted);
                  },
                ),
                // En web el navegador gestiona la salida de audio (no se
                // puede cambiar entre auricular/altavoz desde la app),
                // así que ocultamos el botón.
                if (!kIsWeb)
                  _Btn(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                    label: _speakerOn ? 'Auricular' : 'Altavoz',
                    onTap: () {
                      setState(() => _speakerOn = !_speakerOn);
                      _engine?.setEnableSpeakerphone(_speakerOn);
                    },
                  ),
                _Btn(
                  icon: Icons.call_end,
                  label: 'Colgar',
                  color: AppColors.error,
                  onTap: () => _finishCall(updateFirestore: true),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  final String name;
  final String? photo;
  final String status;
  const _Placeholder(
      {required this.name, this.photo, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF16213E),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AvatarWidget(
              photoUrl: photo, displayName: name, uid: '', radius: 52),
          const SizedBox(height: 16),
          Text(name,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(status,
              style: GoogleFonts.poppins(
                  color: Colors.white.withAlpha(160), fontSize: 14)),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _Btn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color ?? Colors.white.withAlpha(40);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.poppins(
                  color: Colors.white.withAlpha(200), fontSize: 10)),
        ],
      ),
    );
  }
}
