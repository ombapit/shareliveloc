import 'dart:async';
import 'dart:convert';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';
import '../models/group.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/message_storage.dart';
import '../services/user_service.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  final Group group;
  const ChatScreen({super.key, required this.group});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  List<ChatMessage> _messages = [];
  String? _userName;
  bool _loading = true;
  bool _sending = false;
  bool _emojiOpen = false;
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(() {
      if (_inputFocus.hasFocus && _emojiOpen) {
        setState(() => _emojiOpen = false);
      }
    });
    _init();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _init() async {
    final cached = await MessageStorage.load(widget.group.id);
    final name = await UserService.getName();
    if (!mounted) return;
    setState(() {
      _userName = name;
      _messages = cached;
      _loading = false;
    });
    _scrollToBottom(animate: false);

    _connectWebSocket();
    _syncFromServer();
  }

  Future<void> _syncFromServer() async {
    final cutoff = await MessageStorage.getCutoff(widget.group.id);
    final latestLocal = _messages.isEmpty ? null : _messages.last.id;
    int? since;
    if (cutoff != null && latestLocal != null) {
      since = cutoff > latestLocal ? cutoff : latestLocal;
    } else {
      since = cutoff ?? latestLocal;
    }

    final serverMessages =
        await ApiService.getMessages(widget.group.id, since: since);
    if (!mounted || serverMessages.isEmpty) return;

    final existingIds = _messages.map((m) => m.id).toSet();
    final newOnes =
        serverMessages.where((m) => !existingIds.contains(m.id)).toList();
    if (newOnes.isEmpty) return;

    final combined = [..._messages, ...newOnes];
    combined.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    setState(() {
      _messages = combined;
    });
    await MessageStorage.save(widget.group.id, _messages);
    _scrollToBottom();
  }

  void _connectWebSocket() {
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(
      Uri.parse('${AppConfig.wsUrl}/ws/location/${widget.group.id}'),
    );
    _channel!.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          if (msg['type'] == 'message') {
            _handleIncoming(ChatMessage.fromWsBroadcast(msg));
          }
        } catch (_) {}
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  void _handleIncoming(ChatMessage chatMsg) {
    if (!mounted) return;
    if (_messages.any((m) => m.id == chatMsg.id)) return;
    setState(() {
      _messages.add(chatMsg);
    });
    MessageStorage.save(widget.group.id, _messages);
    _scrollToBottom();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animate) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _promptSetName({bool edit = false}) async {
    final controller = TextEditingController(text: _userName ?? '');
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: edit,
      builder: (ctx) => PopScope(
        canPop: edit,
        child: AlertDialog(
          title: Text(edit ? 'Edit Nama' : 'Set Nama Anda'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Masukkan nama Anda',
              border: OutlineInputBorder(),
            ),
            maxLength: 30,
          ),
          actions: [
            if (edit)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Batal'),
              ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(ctx, value);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (name != null && name.isNotEmpty) {
      await UserService.setName(name);
      if (mounted) setState(() => _userName = name);
    }
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty) return;

    if (_userName == null) {
      await _promptSetName();
      if (_userName == null) return;
    }

    setState(() => _sending = true);
    _inputController.clear();

    final sent = await ApiService.sendMessage(
      groupId: widget.group.id,
      senderName: _userName!,
      content: content,
    );

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (sent != null && !_messages.any((m) => m.id == sent.id)) {
        _messages.add(sent);
      }
    });
    if (sent != null) {
      await MessageStorage.save(widget.group.id, _messages);
    }
    _scrollToBottom();

    if (sent == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengirim pesan')),
      );
    }
  }

  Future<void> _clearLocal() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bersihkan Chat?'),
        content: const Text(
          'Pesan akan dihapus dari perangkat Anda saja. '
          'Pesan di server tetap tersimpan dan anggota grup lain masih bisa melihatnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Bersihkan'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final cutoffId = _messages.isEmpty
        ? (await MessageStorage.getCutoff(widget.group.id))
        : _messages.map((m) => m.id).reduce((a, b) => a > b ? a : b);

    await MessageStorage.clear(widget.group.id, cutoffId: cutoffId);
    if (!mounted) return;
    setState(() {
      _messages = [];
    });
  }

  void _toggleEmoji() {
    setState(() => _emojiOpen = !_emojiOpen);
    if (_emojiOpen) {
      // Hide keyboard
      _inputFocus.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      _inputFocus.requestFocus();
    }
  }

  void _onEmojiSelected(Category? category, Emoji emoji) {
    _inputController
      ..text = _inputController.text + emoji.emoji
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: _inputController.text.length),
      );
  }

  void _onBackspacePressed() {
    final text = _inputController.text;
    if (text.isEmpty) return;
    final newText = text.characters.skipLast(1).toString();
    _inputController
      ..text = newText
      ..selection =
          TextSelection.fromPosition(TextPosition(offset: newText.length));
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_emojiOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _emojiOpen) {
          setState(() => _emojiOpen = false);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.chatBackground,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.group.name, style: const TextStyle(fontSize: 16)),
              if (_userName != null)
                Text(
                  'Anda: $_userName',
                  style: const TextStyle(fontSize: 11),
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Edit Nama',
              onPressed: () => _promptSetName(edit: true),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear') _clearLocal();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(
                        Icons.cleaning_services_outlined,
                        size: 20,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Bersihkan Chat',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            'Belum ada pesan.\nMulai percakapan!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(12),
                          itemCount: _messages.length,
                          itemBuilder: (ctx, i) {
                            final msg = _messages[i];
                            final isMe = msg.senderName == _userName;
                            return _buildBubble(msg, isMe);
                          },
                        ),
            ),
            _buildInputBar(),
            if (_emojiOpen)
              SizedBox(
                height: 280,
                child: EmojiPicker(
                  onEmojiSelected: _onEmojiSelected,
                  onBackspacePressed: _onBackspacePressed,
                  config: Config(
                    height: 280,
                    emojiViewConfig: const EmojiViewConfig(
                      columns: 8,
                      emojiSizeMax: 28,
                      backgroundColor: Color(0xFFF0F0F0),
                    ),
                    categoryViewConfig: const CategoryViewConfig(
                      backgroundColor: Color(0xFFF0F0F0),
                      indicatorColor: AppTheme.primary,
                      iconColorSelected: AppTheme.primary,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      backgroundColor: Color(0xFFE0E0E0),
                      buttonColor: Color(0xFFE0E0E0),
                      buttonIconColor: AppTheme.primaryDark,
                      showBackspaceButton: true,
                    ),
                    searchViewConfig: const SearchViewConfig(
                      backgroundColor: Color(0xFFE0E0E0),
                      buttonIconColor: AppTheme.primaryDark,
                      hintText: 'Cari emoji',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg, bool isMe) {
    final bubbleColor = isMe ? AppTheme.bubbleOut : AppTheme.bubbleIn;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(8),
            topRight: const Radius.circular(8),
            bottomLeft: isMe ? const Radius.circular(8) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                msg.senderName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDeeper,
                ),
              ),
            Text(
              msg.content,
              style: const TextStyle(color: Colors.black87, fontSize: 15),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatTime(msg.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      color: AppTheme.chatBackground,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _toggleEmoji,
                      icon: Icon(
                        _emojiOpen
                            ? Icons.keyboard_outlined
                            : Icons.emoji_emotions_outlined,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: _userName == null
                              ? 'Tap untuk atur nama...'
                              : 'Ketik pesan',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                        onTap: () {
                          if (_userName == null) _promptSetName();
                          if (_emojiOpen) {
                            setState(() => _emojiOpen = false);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: AppTheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending ? null : _send,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
