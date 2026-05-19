import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'video_player_screen.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/avatar_widget.dart';
import '../../data/models/message_model.dart';
import '../../data/services/storage_service.dart';
import '../../data/models/call_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/call_provider.dart';
import '../../providers/firestore_provider.dart';
import 'audio_bubble.dart';
import 'gif_picker_sheet.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String chatId;
  const ChatDetailScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailState();
}

class _ChatDetailState extends ConsumerState<ChatDetailScreen>
    with WidgetsBindingObserver {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _recorder = Record();
  final _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _uploading = false;

  // ── Estado de grabación de audio ──────────────────────────────────────────
  bool _recording = false;
  Duration _recordDuration = Duration.zero;
  List<double> _liveAmplitudes = [];
  Timer? _recordTimer;
  StreamSubscription<Amplitude>? _ampSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _markRead();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markRead();
  }

  Future<void> _markRead() async {
    if (_myUid.isEmpty) return;
    await ref
        .read(firestoreServiceProvider)
        .markMessagesAsRead(widget.chatId, _myUid);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _recorder.dispose();
    _recordTimer?.cancel();
    _ampSub?.cancel();
    super.dispose();
  }

  // ── Grabación de audio ───────────────────────────────────────────────────

  Future<void> _startRecord() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    setState(() {
      _recording = true;
      _recordDuration = Duration.zero;
      _liveAmplitudes = [];
    });

    await _recorder.start(
      path: path,
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      samplingRate: 44100,
    );

    // Contador de duración
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordDuration += const Duration(seconds: 1));
    });

    // Stream de amplitud para waveform en tiempo real
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 120))
        .listen((amp) {
      if (!mounted) return;
      final db = amp.current;
      final normalized = (db.isInfinite || db.isNaN)
          ? 0.05
          : ((db + 60) / 60).clamp(0.05, 1.0);
      setState(() => _liveAmplitudes.add(normalized));
    });
  }

  Future<void> _stopAndSend() async {
    _recordTimer?.cancel();
    await _ampSub?.cancel();
    final path = await _recorder.stop();
    final amplitudes = List<double>.from(_liveAmplitudes);

    setState(() { _recording = false; _liveAmplitudes = []; _recordDuration = Duration.zero; });

    if (path == null || _myUid.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final url = await StorageService().uploadChatMedia(
        chatId: widget.chatId,
        file: File(path),
        folder: 'audio',
      );
      await ref.read(firestoreServiceProvider).sendMessage(
        chatId: widget.chatId,
        senderId: _myUid,
        content: url,
        type: 'audio',
        waveformData: amplitudes,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al enviar audio: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _cancelRecord() async {
    _recordTimer?.cancel();
    await _ampSub?.cancel();
    // record 4.x no tiene cancel() — se detiene y se borra el archivo
    final path = await _recorder.stop();
    if (path != null) {
      try { await File(path).delete(); } catch (_) {}
    }
    if (mounted) {
      setState(() { _recording = false; _liveAmplitudes = []; _recordDuration = Duration.zero; });
    }
  }

  // ── Envío de texto / emoji ──────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _myUid.isEmpty) return;
    _textCtrl.clear();
    final type = _isEmojiOnly(text) ? 'emoji' : 'text';
    await ref.read(firestoreServiceProvider).sendMessage(
          chatId: widget.chatId,
          senderId: _myUid,
          content: text,
          type: type,
        );
    _scrollToBottom();
  }

  bool _isEmojiOnly(String text) {
    final s = text.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return false;
    return RegExp(
      r'^[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}'
      r'\u{FE00}-\u{FE0F}\u{1F1E0}-\u{1F1FF}'
      r'\u{200D}\u{20E3}]+$',
      unicode: true,
    ).hasMatch(s);
  }

  // ── Envío de media ──────────────────────────────────────────────────────────

  Future<void> _sendFile(File file, String folder, String type) async {
    if (_myUid.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final url = await StorageService().uploadChatMedia(
        chatId: widget.chatId,
        file: file,
        folder: folder,
      );
      await ref.read(firestoreServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderId: _myUid,
            content: url,
            type: type,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir archivo: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final xfile = await _picker.pickImage(
        source: source, imageQuality: 85, maxWidth: 1920);
    if (xfile != null) await _sendFile(File(xfile.path), 'images', 'image');
  }

  Future<void> _pickVideo() async {
    final xfile = await _picker.pickVideo(source: ImageSource.gallery);
    if (xfile == null) return;

    setState(() => _uploading = true);
    try {
      final storage = StorageService();

      // Subir video
      final videoUrl = await storage.uploadChatMedia(
        chatId: widget.chatId,
        file: File(xfile.path),
        folder: 'videos',
      );

      // Generar thumbnail del primer frame
      String? thumbUrl;
      final thumbPath = await VideoThumbnail.thumbnailFile(
        video: xfile.path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 400,
        quality: 80,
      );
      if (thumbPath != null) {
        thumbUrl = await storage.uploadChatMedia(
          chatId: widget.chatId,
          file: File(thumbPath),
          folder: 'thumbnails',
        );
      }

      await ref.read(firestoreServiceProvider).sendMessage(
            chatId: widget.chatId,
            senderId: _myUid,
            content: videoUrl,
            type: 'video',
            thumbnailUrl: thumbUrl,
          );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al subir video: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickGif() async {
    final gif = await showGifPicker(context);
    if (gif == null || !mounted) return;
    await ref.read(firestoreServiceProvider).sendMessage(
          chatId: widget.chatId,
          senderId: _myUid,
          content: gif.originalUrl,
          type: 'gif',
        );
    _scrollToBottom();
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttachmentSheet(
        onCamera: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
        onGallery: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
        onVideo: () { Navigator.pop(context); _pickVideo(); },
        onGif: () { Navigator.pop(context); _pickGif(); },
      ),
    );
  }

  Future<void> _startCall({
    required BuildContext context,
    required WidgetRef ref,
    required String callerId,
    required String receiverId,
    required bool isVideo,
  }) async {
    if (callerId.isEmpty || receiverId.isEmpty) return;
    final call = await ref.read(callServiceProvider).initiateCall(
          callerId: callerId,
          receiverId: receiverId,
          type: isVideo ? CallType.video : CallType.audio,
        );
    if (context.mounted) {
      context.push('/call', extra: {
        'callId': call.id,
        'channelId': call.channelId,
        'isVideo': isVideo,
        'isCaller': true,
        'remoteUid': receiverId,
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients && _scrollCtrl.position.pixels > 0) {
        _scrollCtrl.animateTo(
          0.0, // con reverse:true, 0.0 es el fondo (mensaje más reciente)
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatStreamProvider(widget.chatId));
    final msgsAsync = ref.watch(messagesStreamProvider(widget.chatId));

    return chatAsync.when(
      loading: () => const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: AppColors.green))),
      error: (_, _) =>
          const Scaffold(body: Center(child: Text('Error al cargar chat'))),
      data: (chat) {
        if (chat == null) {
          return const Scaffold(
              body: Center(child: Text('Chat no encontrado')));
        }

        final otherUid = chat.isGroup
            ? ''
            : chat.participantIds.firstWhere(
                (id) => id != _myUid,
                orElse: () => '',
              );

        final title = chat.isGroup
            ? (chat.groupName ?? 'Grupo')
            : switch (ref.watch(userProfileProvider(otherUid))) {
                AsyncData(value: final u) when u != null => u.displayName,
                _ => 'Usuario',
              };

        final photoUrl = chat.isGroup
            ? chat.groupAvatarUrl
            : switch (ref.watch(userProfileProvider(otherUid))) {
                AsyncData(value: final u)
                    when u != null && u.avatarUrl.isNotEmpty =>
                  u.avatarUrl,
                _ => null,
              };

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                AvatarWidget(
                  photoUrl: photoUrl,
                  displayName: title,
                  uid: chat.isGroup ? chat.id : otherUid,
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              if (chat.isGroup)
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Info del grupo',
                  onPressed: () =>
                      context.push('/group-info/${chat.id}'),
                ),
              // Llamadas solo en chats privados
              if (!chat.isGroup) ...[
                IconButton(
                  icon: const Icon(Icons.videocam_outlined),
                  tooltip: 'Videollamada',
                  onPressed: () => _startCall(
                    context: context,
                    ref: ref,
                    callerId: _myUid,
                    receiverId: otherUid,
                    isVideo: true,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.call_outlined),
                  tooltip: 'Llamada de voz',
                  onPressed: () => _startCall(
                    context: context,
                    ref: ref,
                    callerId: _myUid,
                    receiverId: otherUid,
                    isVideo: false,
                  ),
                ),
              ],
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: _MessageList(
                      msgsAsync: msgsAsync,
                      myUid: _myUid,
                      scrollCtrl: _scrollCtrl,
                      onLoaded: _scrollToBottom,
                      onNewMessages: _markRead,
                      isGroup: chat.isGroup,
                    ),
                  ),
                  _InputBar(
                    controller: _textCtrl,
                    onSend: _sendText,
                    onAttachment: _showAttachmentSheet,
                    isRecording: _recording,
                    liveAmplitudes: _liveAmplitudes,
                    recordDuration: _recordDuration,
                    onStartRecord: _startRecord,
                    onStopRecord: _stopAndSend,
                    onCancelRecord: _cancelRecord,
                  ),
                ],
              ),
              // Indicador de subida
              if (_uploading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withAlpha(100),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.green),
                          SizedBox(height: 12),
                          Text('Subiendo archivo...',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Lista de mensajes ─────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final AsyncValue<List<MessageModel>> msgsAsync;
  final String myUid;
  final ScrollController scrollCtrl;
  final VoidCallback onLoaded;
  final VoidCallback? onNewMessages;
  final bool isGroup;

  const _MessageList({
    required this.msgsAsync,
    required this.myUid,
    required this.scrollCtrl,
    required this.onLoaded,
    this.onNewMessages,
    this.isGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    return msgsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.green)),
      error: (_, _) =>
          const Center(child: Text('Error al cargar mensajes')),
      data: (msgs) {
        if (msgs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withAlpha(60)),
                const SizedBox(height: 12),
                Text('Di hola 👋',
                    style: GoogleFonts.poppins(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withAlpha(120))),
              ],
            ),
          );
        }

        if (onNewMessages != null) onNewMessages!();

        return ListView.builder(
          controller: scrollCtrl,
          reverse: true, // posición 0 = fondo = mensaje más reciente
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: msgs.length,
          itemBuilder: (_, i) {
            final n = msgs.length;
            // reverse:true → índice 0 es el más reciente
            final msg = msgs[n - 1 - i];
            final isMe = msg.senderId == myUid;

            // Mensaje anterior en tiempo (visualmente encima con lista invertida)
            final prevIdx = n - 2 - i;
            final hasPrev = prevIdx >= 0;

            final showDate =
                !hasPrev || !_sameDay(msgs[prevIdx].timestamp, msg.timestamp);
            final sameAsPrev = hasPrev &&
                msgs[prevIdx].senderId == msg.senderId &&
                !showDate;

            return Column(
              children: [
                if (showDate) _DateDivider(msg.timestamp),
                _MessageBubble(msg: msg, isMe: isMe, compact: sameAsPrev,
                    isGroup: isGroup, showSenderHeader: isGroup && !isMe && !sameAsPrev),
              ],
            );
          },
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Burbuja de mensaje ────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final bool compact;
  final bool isGroup;
  final bool showSenderHeader;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    this.compact = false,
    this.isGroup = false,
    this.showSenderHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = switch (msg.type) {
      MessageType.emoji => _EmojiOnlyBubble(msg: msg, isMe: isMe),
      MessageType.image || MessageType.gif => _ImageBubble(msg: msg, isMe: isMe),
      MessageType.video => _VideoBubble(msg: msg, isMe: isMe),
      MessageType.audio => AudioBubble(key: ValueKey(msg.id), msg: msg, isMe: isMe),
      _ => _TextBubble(msg: msg, isMe: isMe, compact: compact),
    };

    if (!showSenderHeader) return bubble;

    // En grupos: nombre del remitente encima de la burbuja
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _GroupSenderName(uid: msg.senderId),
        bubble,
      ],
    );
  }
}

// Nombre del remitente para mensajes de grupo (color determinístico por UID)
class _GroupSenderName extends ConsumerWidget {
  final String uid;
  const _GroupSenderName({required this.uid});

  static const _palette = [
    Color(0xFF1E88E5), // blue
    Color(0xFF43A047), // green
    Color(0xFFE53935), // red
    Color(0xFF8E24AA), // purple
    Color(0xFFFF8F00), // amber
    Color(0xFF00ACC1), // cyan
    Color(0xFFD81B60), // pink
    Color(0xFF6D4C41), // brown
  ];

  Color _colorFor(String uid) =>
      _palette[uid.codeUnits.fold(0, (s, c) => s + c) % _palette.length];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = switch (ref.watch(userProfileProvider(uid))) {
      AsyncData(value: final u) when u != null => u.displayName,
      _ => '…',
    };
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 2, top: 4),
      child: Text(
        name,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _colorFor(uid),
        ),
      ),
    );
  }
}

// Burbuja de texto ─────────────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  final bool compact;
  const _TextBubble(
      {required this.msg, required this.isMe, required this.compact});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bubbleColor = isMe ? AppColors.green : cs.surfaceContainerHighest;
    final textColor = isMe ? Colors.white : cs.onSurface;
    final timeColor =
        isMe ? Colors.white.withAlpha(160) : cs.onSurface.withAlpha(120);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: EdgeInsets.only(
            top: compact ? 1 : 4,
            bottom: 1,
            left: isMe ? 48 : 0,
            right: isMe ? 0 : 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg.content,
                style: GoogleFonts.poppins(fontSize: 14, color: textColor)),
            const SizedBox(height: 2),
            _TimeRow(
                timestamp: msg.timestamp,
                status: msg.status,
                isMe: isMe,
                color: timeColor),
          ],
        ),
      ),
    );
  }
}

// Burbuja emoji grande ────────────────────────────────────────────────────────

class _EmojiOnlyBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  const _EmojiOnlyBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = msg.content.runes.length;
    final fontSize = count <= 2 ? 48.0 : count <= 5 ? 36.0 : 28.0;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            top: 4, bottom: 1, left: isMe ? 48 : 8, right: isMe ? 8 : 48),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg.content, style: TextStyle(fontSize: fontSize)),
            const SizedBox(height: 2),
            _TimeRow(
                timestamp: msg.timestamp,
                status: msg.status,
                isMe: isMe,
                color: cs.onSurface.withAlpha(100)),
          ],
        ),
      ),
    );
  }
}

// Burbuja imagen / GIF ────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  const _ImageBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.65;
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxW),
        margin: EdgeInsets.only(
            top: 4, bottom: 1, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          child: Stack(
            children: [
              CachedNetworkImage(
                imageUrl: msg.content,
                width: maxW,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                  width: maxW,
                  height: 180,
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.green, strokeWidth: 2)),
                ),
                errorWidget: (_, _, _) => Container(
                  width: maxW,
                  height: 120,
                  color: cs.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
              // Hora superpuesta en esquina inferior
              Positioned(
                bottom: 6,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(130),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _TimeRow(
                    timestamp: msg.timestamp,
                    status: msg.status,
                    isMe: isMe,
                    color: Colors.white.withAlpha(220),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Burbuja video ───────────────────────────────────────────────────────────────

class _VideoBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMe;
  const _VideoBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.of(context).size.width * 0.65;
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isMe ? 16 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 16),
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(url: msg.content),
          ),
        ),
        child: Container(
          width: maxW,
          height: 160,
          margin: EdgeInsets.only(
              top: 4, bottom: 1, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: radius,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Fondo negro base
                Positioned.fill(
                  child: Container(color: Colors.black87),
                ),
                // Thumbnail con Positioned.fill para constraints fiables
                if (msg.thumbnailUrl != null)
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: msg.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: Colors.black87),
                    ),
                  ),
                // Overlay oscuro para legibilidad del icono
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withAlpha(70),
                  ),
                ),
                const Icon(Icons.play_circle_fill_rounded,
                    size: 56, color: Colors.white),
                Positioned(
                  bottom: 6,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(130),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _TimeRow(
                      timestamp: msg.timestamp,
                      status: msg.status,
                      isMe: isMe,
                      color: Colors.white.withAlpha(220),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Fila de hora + ticks ────────────────────────────────────────────────────────

class _TimeRow extends StatelessWidget {
  final DateTime timestamp;
  final MessageStatus status;
  final bool isMe;
  final Color color;

  const _TimeRow({
    required this.timestamp,
    required this.status,
    required this.isMe,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(DateFormat('HH:mm').format(timestamp),
            style: GoogleFonts.poppins(fontSize: 10, color: color)),
        if (isMe) ...[
          const SizedBox(width: 3),
          _StatusIcon(status: status, color: color),
        ],
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final Color color;
  const _StatusIcon({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MessageStatus.sent => Icon(Icons.check, size: 12, color: color),
      MessageStatus.delivered =>
        Icon(Icons.done_all, size: 12, color: color),
      MessageStatus.read =>
        Icon(Icons.done_all, size: 12, color: Colors.lightBlueAccent),
    };
  }
}

// ── Separador de fecha ────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final DateTime date;
  const _DateDivider(this.date);

  String _label() {
    final now = DateTime.now();
    if (_sameDay(date, now)) return 'Hoy';
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) return 'Ayer';
    return DateFormat('d MMM yyyy', 'es').format(date);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.onSurface.withAlpha(30))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_label(),
                style: GoogleFonts.poppins(
                    fontSize: 11, color: cs.onSurface.withAlpha(120))),
          ),
          Expanded(child: Divider(color: cs.onSurface.withAlpha(30))),
        ],
      ),
    );
  }
}

// ── Input bar con emoji picker y grabación ────────────────────────────────────

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttachment;
  final VoidCallback onStartRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onCancelRecord;
  final bool isRecording;
  final List<double> liveAmplitudes;
  final Duration recordDuration;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onAttachment,
    required this.onStartRecord,
    required this.onStopRecord,
    required this.onCancelRecord,
    required this.isRecording,
    required this.liveAmplitudes,
    required this.recordDuration,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _focusNode = FocusNode();
  bool _showEmoji = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmoji) {
        setState(() => _showEmoji = false);
      }
    });
  }

  @override
  void didUpdateWidget(_InputBar old) {
    super.didUpdateWidget(old);
    // Ocultar emoji picker cuando inicia grabación
    if (widget.isRecording && !old.isRecording && _showEmoji) {
      setState(() => _showEmoji = false);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      Future.delayed(const Duration(milliseconds: 100),
          () => setState(() => _showEmoji = true));
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        SafeArea(
          bottom: !_showEmoji,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 4,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            // ── Modo grabación ───────────────────────────────────────────
            child: widget.isRecording
                ? Row(
                    children: [
                      // Cancelar
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error),
                        onPressed: widget.onCancelRecord,
                        tooltip: 'Cancelar',
                      ),
                      // Waveform en tiempo real
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: CustomPaint(
                            painter: _LiveWaveformPainter(
                              amplitudes: widget.liveAmplitudes,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Duración
                      Text(
                        _fmtDuration(widget.recordDuration),
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.error),
                      ),
                      const SizedBox(width: 4),
                      // Enviar grabación
                      CircleAvatar(
                        backgroundColor: AppColors.green,
                        child: IconButton(
                          icon: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                          onPressed: widget.onStopRecord,
                        ),
                      ),
                    ],
                  )
                // ── Modo normal ──────────────────────────────────────────
                : Row(
                    children: [
                      // Emoji
                      IconButton(
                        icon: Icon(
                          _showEmoji
                              ? Icons.keyboard_rounded
                              : Icons.emoji_emotions_outlined,
                          color: cs.onSurface.withAlpha(160),
                        ),
                        onPressed: _toggleEmoji,
                      ),
                      // Campo de texto
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          focusNode: _focusNode,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 5,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: 'Mensaje',
                            hintStyle: GoogleFonts.poppins(fontSize: 14),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => widget.onSend(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Adjuntar
                      IconButton(
                        icon: Icon(Icons.attach_file_rounded,
                            color: cs.onSurface.withAlpha(160)),
                        onPressed: widget.onAttachment,
                      ),
                      // Micrófono (texto vacío) o Enviar (texto con contenido)
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: widget.controller,
                        builder: (_, val, _) => val.text.trim().isEmpty
                            ? IconButton(
                                icon: Icon(Icons.mic_rounded,
                                    color: AppColors.green, size: 28),
                                onPressed: widget.onStartRecord,
                                tooltip: 'Grabar audio',
                              )
                            : CircleAvatar(
                                backgroundColor: AppColors.green,
                                child: IconButton(
                                  icon: const Icon(Icons.send_rounded,
                                      color: Colors.white, size: 20),
                                  onPressed: widget.onSend,
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ),

        // Emoji picker
        Offstage(
          offstage: !_showEmoji || widget.isRecording,
          child: SizedBox(
            height: 280,
            child: EmojiPicker(
              textEditingController: widget.controller,
              config: Config(
                height: 280,
                checkPlatformCompatibility: true,
                emojiViewConfig:
                    EmojiViewConfig(emojiSizeMax: 28, backgroundColor: cs.surface),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: cs.surface,
                  iconColor: cs.onSurface.withAlpha(100),
                  iconColorSelected: AppColors.green,
                  indicatorColor: AppColors.green,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: cs.surface,
                  buttonIconColor: cs.onSurface.withAlpha(150),
                ),
                skinToneConfig: const SkinToneConfig(),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: cs.surface,
                  buttonIconColor: cs.onSurface.withAlpha(150),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Waveform animado durante grabación (últimas N amplitudes)
class _LiveWaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;
  const _LiveWaveformPainter({required this.amplitudes, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 40;
    final src = amplitudes.length > barCount
        ? amplitudes.sublist(amplitudes.length - barCount)
        : amplitudes;

    final barW = size.width / barCount * 0.55;
    final gap = size.width / barCount * 0.45;
    final paint = Paint()..color = color..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final val = i < src.length ? src[i] : 0.08;
      final barH = (val.clamp(0.08, 1.0) * size.height);
      final x = i * (barW + gap);
      final y = (size.height - barH) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barW, barH), const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LiveWaveformPainter old) => old.amplitudes != amplitudes;
}

// ── Sheet de adjuntos ─────────────────────────────────────────────────────────

class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onVideo;
  final VoidCallback onGif;

  const _AttachmentSheet({
    required this.onCamera,
    required this.onGallery,
    required this.onVideo,
    required this.onGif,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withAlpha(50),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MediaOption(
                icon: Icons.camera_alt_rounded,
                label: 'Cámara',
                color: Colors.deepPurple,
                onTap: onCamera,
              ),
              _MediaOption(
                icon: Icons.photo_rounded,
                label: 'Galería',
                color: Colors.blue,
                onTap: onGallery,
              ),
              _MediaOption(
                icon: Icons.videocam_rounded,
                label: 'Video',
                color: Colors.red,
                onTap: onVideo,
              ),
              _MediaOption(
                icon: Icons.gif_box_rounded,
                label: 'GIF',
                color: Colors.green,
                onTap: onGif,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MediaOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withAlpha(30),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: GoogleFonts.poppins(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
