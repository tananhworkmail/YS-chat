import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';

enum _PanelMode { chats, contacts }

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  final _contactSearchController = TextEditingController();
  final _audioRecorder = AudioRecorder();
  _PanelMode _panelMode = _PanelMode.chats;
  bool _recording = false;
  ChatMessage? _replyingTo;

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    _contactSearchController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final text = _messageController.text;
    _messageController.clear();
    final replyTo = _replyingTo;
    setState(() => _replyingTo = null);
    await context.read<AppState>().sendText(text, replyTo: replyTo);
  }

  Future<void> _pickFiles(FileType type) async {
    final result = await FilePicker.pickFiles(type: type, allowMultiple: true);
    final files = result?.paths.whereType<String>().map(File.new).toList() ??
        const <File>[];
    if (files.isEmpty || !mounted) return;
    final replyTo = _replyingTo;
    setState(() => _replyingTo = null);
    await context.read<AppState>().sendFiles(files,
        type: type == FileType.image ? 'image' : 'file', replyTo: replyTo);
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _audioRecorder.stop();
      setState(() => _recording = false);
      if (path != null && mounted) {
        await context.read<AppState>().sendFiles([File(path)], type: 'voice');
      }
      return;
    }

    if (!await _audioRecorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/ys-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    setState(() => _recording = true);
  }

  Future<void> _startDirectChat([String? keyword]) async {
    final value = (keyword ?? _searchController.text).trim();
    if (value.isEmpty) return;
    final state = context.read<AppState>();
    final users = await state.apiClient.searchUsers(value);
    if (!mounted) return;
    final selected = await showModalBottomSheet<ChatUser>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _UserSearchSheet(users: users),
    );
    if (selected != null && mounted) {
      await state.openDirectConversation(selected.userid);
      setState(() => _panelMode = _PanelMode.chats);
    }
  }

  Future<void> _showProfileSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProfileSheet(),
    );
  }

  Future<void> _downloadAttachment(ChatAttachment attachment) async {
    final url =
        context.read<AppState>().apiClient.absoluteUrl(attachment.fileUrl);
    final directory =
        await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    final filename = _safeDownloadName(attachment);
    final destination = '${directory.path}${Platform.pathSeparator}$filename';
    try {
      await Dio().download(url, destination);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Da tai ve $filename')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tai file khong thanh cong')),
      );
    }
  }

  Future<void> _openForwardSheet(ChatMessage message) async {
    final state = context.read<AppState>();
    final target = await showModalBottomSheet<ChatConversation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ForwardSheet(
        conversations: state.conversations,
        currentUserid: state.tokenStore.userid ?? '',
        currentConversationId: state.selectedConversation?.id ?? 0,
      ),
    );
    if (target == null || !mounted) return;
    await state.forwardMessage(target, message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Da chuyen tiep tin nhan')),
    );
  }

  Future<void> _showInfoPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InfoPanel(onDownload: _downloadAttachment),
    );
  }

  Future<void> _openPollSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PollCreateSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentUserid = state.tokenStore.userid ?? '';

    return Scaffold(
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final panel = _SidePanel(
                mode: _panelMode,
                searchController: _searchController,
                contactSearchController: _contactSearchController,
                currentUserid: currentUserid,
                onSearchUser: _startDirectChat,
                onModeChanged: (mode) => setState(() => _panelMode = mode),
              );
              final thread = _Thread(
                currentUserid: currentUserid,
                messageController: _messageController,
                recording: _recording,
                wide: wide,
                onBack: () =>
                    context.read<AppState>().clearSelectedConversation(),
                replyingTo: _replyingTo,
                onCancelReply: () => setState(() => _replyingTo = null),
                onReply: (message) => setState(() => _replyingTo = message),
                onForward: _openForwardSheet,
                onDownload: _downloadAttachment,
                onInfo: _showInfoPanel,
                onCreatePoll: _openPollSheet,
                onSend: _sendText,
                onPickFiles: () => _pickFiles(FileType.any),
                onPickImages: () => _pickFiles(FileType.image),
                onRecord: _toggleRecording,
              );

              if (wide) {
                return Row(
                  children: [
                    _AppRail(
                      mode: _panelMode,
                      onModeChanged: (mode) =>
                          setState(() => _panelMode = mode),
                      onProfile: () => _showProfileSheet(context),
                    ),
                    SizedBox(width: 340, child: panel),
                    const VerticalDivider(width: 1),
                    Expanded(child: thread),
                  ],
                );
              }

              final showThread = _panelMode == _PanelMode.chats &&
                  state.selectedConversation != null;
              if (showThread) return thread;

              return Column(
                children: [
                  Expanded(child: panel),
                  _MobileRail(
                    mode: _panelMode,
                    onModeChanged: (mode) => setState(() => _panelMode = mode),
                    onProfile: () => _showProfileSheet(context),
                  ),
                ],
              );
            },
          ),
          const _CallPanel(),
        ],
      ),
    );
  }
}

class _AppRail extends StatelessWidget {
  const _AppRail({
    required this.mode,
    required this.onModeChanged,
    required this.onProfile,
  });

  final _PanelMode mode;
  final ValueChanged<_PanelMode> onModeChanged;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      color: AppColors.brandDark,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: SafeArea(
        child: Column(
          children: [
            const BrandLogo(size: 40, padding: 5, shadow: false),
            const SizedBox(height: 28),
            _RailButton(
              tooltip: 'Tin nhan',
              icon: Icons.chat_bubble_outline,
              active: mode == _PanelMode.chats,
              onTap: () => onModeChanged(_PanelMode.chats),
            ),
            const SizedBox(height: 10),
            _RailButton(
              tooltip: 'Danh ba',
              icon: Icons.groups_outlined,
              active: mode == _PanelMode.contacts,
              onTap: () => onModeChanged(_PanelMode.contacts),
            ),
            const Spacer(),
            _RailButton(
                tooltip: 'Ho so',
                icon: Icons.account_circle_outlined,
                onTap: onProfile),
          ],
        ),
      ),
    );
  }
}

class _MobileRail extends StatelessWidget {
  const _MobileRail({
    required this.mode,
    required this.onModeChanged,
    required this.onProfile,
  });

  final _PanelMode mode;
  final ValueChanged<_PanelMode> onModeChanged;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.brandDark,
          boxShadow: [
            BoxShadow(
              color: const Color(0xff0f172a).withValues(alpha: 0.18),
              blurRadius: 34,
              offset: const Offset(0, -14),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _RailButton(
              tooltip: 'Tin nhan',
              icon: Icons.chat_bubble_outline,
              active: mode == _PanelMode.chats,
              onTap: () => onModeChanged(_PanelMode.chats),
            ),
            _RailButton(
              tooltip: 'Danh ba',
              icon: Icons.groups_outlined,
              active: mode == _PanelMode.contacts,
              onTap: () => onModeChanged(_PanelMode.contacts),
            ),
            _RailButton(
                tooltip: 'Ho so',
                icon: Icons.account_circle_outlined,
                onTap: onProfile),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color:
                  active ? Colors.white : Colors.white.withValues(alpha: 0.78),
              size: 22),
        ),
      ),
    );
  }
}

class _CallPanel extends StatelessWidget {
  const _CallPanel();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.callState == 'idle') return const SizedBox.shrink();

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff0f172a).withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone_in_talk_outlined,
                    color: AppColors.brand),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.callPeerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.ink, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      state.callState == 'active'
                          ? 'Dang goi ${_formatDuration(state.callDuration)}'
                          : state.callStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (state.callState == 'incoming') ...[
                _CallButton(
                  icon: Icons.call,
                  color: const Color(0xff16a34a),
                  onTap: () => context.read<AppState>().acceptIncomingCall(),
                ),
                const SizedBox(width: 6),
                _CallButton(
                  icon: Icons.call_end,
                  color: AppColors.danger,
                  onTap: () => context.read<AppState>().rejectIncomingCall(),
                ),
              ] else ...[
                _CallButton(
                  icon: state.callMuted ? Icons.mic_off : Icons.mic,
                  color: state.callMuted
                      ? const Color(0xfff59e0b)
                      : AppColors.brand,
                  onTap: () => context.read<AppState>().toggleCallMute(),
                ),
                const SizedBox(width: 6),
                _CallButton(
                  icon: Icons.call_end,
                  color: AppColors.danger,
                  onTap: () => context.read<AppState>().endOrCancelCall(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton(
      {required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}

class _SidePanel extends StatefulWidget {
  const _SidePanel({
    required this.mode,
    required this.searchController,
    required this.contactSearchController,
    required this.currentUserid,
    required this.onSearchUser,
    required this.onModeChanged,
  });

  final _PanelMode mode;
  final TextEditingController searchController;
  final TextEditingController contactSearchController;
  final String currentUserid;
  final Future<void> Function([String? keyword]) onSearchUser;
  final ValueChanged<_PanelMode> onModeChanged;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_refresh);
    widget.contactSearchController.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _SidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.removeListener(_refresh);
      widget.searchController.addListener(_refresh);
    }
    if (oldWidget.contactSearchController != widget.contactSearchController) {
      oldWidget.contactSearchController.removeListener(_refresh);
      widget.contactSearchController.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_refresh);
    widget.contactSearchController.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isContacts = widget.mode == _PanelMode.contacts;
    final searchController =
        isContacts ? widget.contactSearchController : widget.searchController;

    return Container(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PanelHeader(
              title: isContacts ? 'Danh ba' : 'Tin nhan',
              subtitle: 'YS Chat',
              primaryIcon: isContacts
                  ? Icons.person_add_alt_outlined
                  : Icons.edit_square,
              onPrimary: () => widget.onSearchUser(searchController.text),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) =>
                    isContacts ? null : widget.onSearchUser(value),
                decoration: InputDecoration(
                  hintText: isContacts
                      ? 'Tim trong danh ba'
                      : 'Tim cuoc tro chuyen hoac nguoi dung',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchController.text.isEmpty
                      ? (isContacts
                          ? null
                          : IconButton(
                              tooltip: 'Mo chat',
                              onPressed: () =>
                                  widget.onSearchUser(searchController.text),
                              icon: const Icon(Icons.chat_bubble_outline),
                            ))
                      : IconButton(
                          tooltip: 'Xoa',
                          onPressed: searchController.clear,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            if (isContacts)
              Expanded(
                child: _ContactList(
                  keyword: widget.contactSearchController.text,
                  onStartChat: (userid) async {
                    await context
                        .read<AppState>()
                        .openDirectConversation(userid);
                    widget.onModeChanged(_PanelMode.chats);
                  },
                ),
              )
            else
              Expanded(
                child: _ConversationList(
                  conversations: _filterConversations(
                      state.conversations, widget.searchController.text),
                  currentUserid: widget.currentUserid,
                  selectedConversationId: state.selectedConversation?.id,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<ChatConversation> _filterConversations(
      List<ChatConversation> conversations, String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return conversations;
    return conversations.where((conversation) {
      final title = conversation.titleFor(widget.currentUserid).toLowerCase();
      final lastMessage = conversation.lastMessage?.content.toLowerCase() ?? '';
      return title.contains(query) || lastMessage.contains(query);
    }).toList();
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.primaryIcon,
    required this.onPrimary,
  });

  final String title;
  final String subtitle;
  final IconData primaryIcon;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.brand,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            _PanelIconButton(
                tooltip: 'Mo chat',
                icon: primaryIcon,
                onTap: onPrimary,
                primary: true),
          ],
        ),
      ),
    );
  }
}

class _PanelIconButton extends StatelessWidget {
  const _PanelIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: primary ? AppColors.brand : const Color(0xfff0f4fa),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: primary ? Colors.white : AppColors.ink, size: 20),
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.conversations,
    required this.currentUserid,
    required this.selectedConversationId,
  });

  final List<ChatConversation> conversations;
  final String currentUserid;
  final int? selectedConversationId;

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          EmptyState(
              icon: Icons.chat_bubble_outline, text: 'Chua co cuoc tro chuyen'),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        return _ConversationItem(
          conversation: conversation,
          currentUserid: currentUserid,
          selected: selectedConversationId == conversation.id,
          onTap: () =>
              context.read<AppState>().selectConversation(conversation),
        );
      },
    );
  }
}

class _ConversationItem extends StatelessWidget {
  const _ConversationItem({
    required this.conversation,
    required this.currentUserid,
    required this.selected,
    required this.onTap,
  });

  final ChatConversation conversation;
  final String currentUserid;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final title = conversation.titleFor(currentUserid);
    final member = _presenceMember(conversation, currentUserid);
    final imageUrl = conversation.avatar.isNotEmpty
        ? state.apiClient.absoluteUrl(conversation.avatar)
        : member?.avatarUrl(state);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? AppColors.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(
              children: [
                if (conversation.type == 'group' && conversation.avatar.isEmpty)
                  _GroupAvatar(count: conversation.memberCount)
                else
                  YSAvatar(
                      label: title,
                      imageUrl: imageUrl,
                      online: member?.isOnline),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            _conversationTime(conversation),
                            style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _lastMessagePreview(conversation),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
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

class _ContactList extends StatelessWidget {
  const _ContactList({
    required this.keyword,
    required this.onStartChat,
  });

  final String keyword;
  final Future<void> Function(String userid) onStartChat;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = keyword.trim().toLowerCase();
    final contacts = state.contacts.where((contact) {
      if (query.isEmpty) return true;
      return contact.fullname.toLowerCase().contains(query) ||
          contact.userid.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.fullname.compareTo(b.fullname));

    if (contacts.isEmpty) {
      return const EmptyState(
          icon: Icons.groups_outlined, text: 'Chua co lien he phu hop');
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final display =
            contact.fullname.trim().isEmpty ? contact.userid : contact.fullname;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onStartChat(contact.userid),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Row(
                  children: [
                    YSAvatar(
                      label: display,
                      imageUrl: contact.avatar.isNotEmpty
                          ? state.apiClient.absoluteUrl(contact.avatar)
                          : null,
                      online: contact.isOnline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            display,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            contact.userid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Thread extends StatefulWidget {
  const _Thread({
    required this.currentUserid,
    required this.messageController,
    required this.recording,
    required this.wide,
    required this.onBack,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onReply,
    required this.onForward,
    required this.onDownload,
    required this.onInfo,
    required this.onCreatePoll,
    required this.onSend,
    required this.onPickFiles,
    required this.onPickImages,
    required this.onRecord,
  });

  final String currentUserid;
  final TextEditingController messageController;
  final bool recording;
  final bool wide;
  final VoidCallback onBack;
  final ChatMessage? replyingTo;
  final VoidCallback onCancelReply;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onForward;
  final ValueChanged<ChatAttachment> onDownload;
  final VoidCallback onInfo;
  final VoidCallback onCreatePoll;
  final VoidCallback onSend;
  final VoidCallback onPickFiles;
  final VoidCallback onPickImages;
  final VoidCallback onRecord;

  @override
  State<_Thread> createState() => _ThreadState();
}

class _ThreadState extends State<_Thread> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 180) {
      context.read<AppState>().loadOlderMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conversation = state.selectedConversation;
    if (conversation == null) {
      return Container(
        color: AppColors.canvas,
        child: const EmptyState(
            icon: Icons.forum_outlined,
            text: 'Chon mot cuoc tro chuyen de bat dau'),
      );
    }

    return Container(
      color: AppColors.canvas,
      child: SafeArea(
        left: false,
        bottom: false,
        child: Column(
          children: [
            _ChatHeader(
              conversation: conversation,
              currentUserid: widget.currentUserid,
              wide: widget.wide,
              onBack: widget.onBack,
              onInfo: widget.onInfo,
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                reverse: true,
                itemCount: state.messages.length +
                    (state.hasMoreMessages || state.loadingOlderMessages
                        ? 1
                        : 0),
                itemBuilder: (context, index) {
                  if (index == state.messages.length) {
                    return _OlderMessagesLoader(
                        loading: state.loadingOlderMessages);
                  }
                  final message = state.messages.reversed.elementAt(index);
                  return MessageBubble(
                    message: message,
                    mine: message.senderUserid == widget.currentUserid,
                    resolveUrl: state.apiClient.absoluteUrl,
                    onReply: widget.onReply,
                    onForward: widget.onForward,
                    onDownload: widget.onDownload,
                    onVotePoll: (message, optionIds, customOption) => context
                        .read<AppState>()
                        .votePoll(message, optionIds,
                            customOption: customOption),
                    onClosePoll: (message) =>
                        context.read<AppState>().closePoll(message),
                  );
                },
              ),
            ),
            _Composer(
              controller: widget.messageController,
              recording: widget.recording,
              replyingTo: widget.replyingTo,
              onCancelReply: widget.onCancelReply,
              onCreatePoll: widget.onCreatePoll,
              onSend: widget.onSend,
              onPickFiles: widget.onPickFiles,
              onPickImages: widget.onPickImages,
              onRecord: widget.onRecord,
            ),
          ],
        ),
      ),
    );
  }
}

class _OlderMessagesLoader extends StatelessWidget {
  const _OlderMessagesLoader({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) {
      return const SizedBox(height: 10);
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.currentUserid,
    required this.wide,
    required this.onBack,
    required this.onInfo,
  });

  final ChatConversation conversation;
  final String currentUserid;
  final bool wide;
  final VoidCallback onBack;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final title = conversation.titleFor(currentUserid);
    final member = _presenceMember(conversation, currentUserid);
    final imageUrl = conversation.avatar.isNotEmpty
        ? state.apiClient.absoluteUrl(conversation.avatar)
        : member?.avatarUrl(state);

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          if (!wide)
            IconButton(
              tooltip: 'Quay lai',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          if (conversation.type == 'group' && conversation.avatar.isEmpty)
            _GroupAvatar(count: conversation.memberCount)
          else
            YSAvatar(
                label: title,
                imageUrl: imageUrl,
                online: member?.isOnline,
                size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  conversation.type == 'group'
                      ? '${conversation.memberCount} thanh vien'
                      : (member?.isOnline == true
                          ? 'Dang hoat dong'
                          : 'Nhan tin truc tiep'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (conversation.type == 'direct')
            IconButton(
              tooltip: 'Goi dien',
              onPressed: () => context.read<AppState>().startAudioCall(),
              icon: const Icon(Icons.phone_outlined),
            ),
          IconButton(
            tooltip: 'Thong tin',
            onPressed: onInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.recording,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onCreatePoll,
    required this.onSend,
    required this.onPickFiles,
    required this.onPickImages,
    required this.onRecord,
  });

  final TextEditingController controller;
  final bool recording;
  final ChatMessage? replyingTo;
  final VoidCallback onCancelReply;
  final VoidCallback onCreatePoll;
  final VoidCallback onSend;
  final VoidCallback onPickFiles;
  final VoidCallback onPickImages;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyingTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandSoftest,
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                      left: BorderSide(color: AppColors.brand, width: 3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Tra loi ${replyingTo!.senderName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.brandDark,
                                fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _messagePreview(replyingTo!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bo tra loi',
                      onPressed: onCancelReply,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (recording)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xfffee2e2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        size: 15, color: AppColors.danger),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Dang ghi am',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    InkWell(
                      onTap: onRecord,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.stop_circle_outlined,
                            color: AppColors.danger),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ComposerButton(
                    tooltip: 'Anh',
                    icon: Icons.image_outlined,
                    onTap: onPickImages),
                _ComposerButton(
                    tooltip: 'File',
                    icon: Icons.attach_file,
                    onTap: onPickFiles),
                _ComposerButton(
                  tooltip: recording ? 'Dung ghi am' : 'Ghi am',
                  icon: recording ? Icons.stop_circle_outlined : Icons.mic_none,
                  active: recording,
                  onTap: onRecord,
                ),
                _ComposerButton(
                  tooltip: 'Binh chon',
                  icon: Icons.how_to_vote_outlined,
                  onTap: onCreatePoll,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Nhap tin nhan',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: onSend,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.18),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 40,
          decoration: BoxDecoration(
            color: active ? const Color(0xfffee2e2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: active ? AppColors.danger : const Color(0xff596779),
              size: 21),
        ),
      ),
    );
  }
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet();

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final TextEditingController _fullnameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final me = context.read<AppState>().me;
    _fullnameController = TextEditingController(text: me?.fullname ?? '');
  }

  @override
  void dispose() {
    _fullnameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().updateFullname(_fullnameController.text);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().uploadAvatar(File(path));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPasswordSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PasswordSheet(),
    );
  }

  Future<void> _logout() async {
    Navigator.of(context).pop();
    await context.read<AppState>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me;
    final avatar = me?.avatar ?? '';
    final label = me?.fullname.trim().isNotEmpty == true
        ? me!.fullname
        : me?.userid ?? 'YS';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  YSAvatar(
                    label: label,
                    imageUrl: avatar.isNotEmpty
                        ? state.apiClient.absoluteUrl(avatar)
                        : null,
                    size: 86,
                  ),
                  _PanelIconButton(
                    tooltip: 'Doi avatar',
                    icon: Icons.photo_camera_outlined,
                    onTap: _saving ? () {} : _pickAvatar,
                    primary: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _fullnameController,
              decoration: const InputDecoration(
                labelText: 'Ho ten',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              me?.userid ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _saveName,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Luu ho so'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _openPasswordSheet,
              icon: const Icon(Icons.lock_reset_outlined),
              label: const Text('Doi mat khau'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _saving ? null : _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Dang xuat'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet();

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String _error = '';

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty || newPassword.isEmpty) {
      setState(() => _error = 'Vui long nhap day du mat khau');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _error = 'Mat khau moi khong khop');
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await context
          .read<AppState>()
          .apiClient
          .changePassword(currentPassword, newPassword);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Da doi mat khau')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Doi mat khau khong thanh cong');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Doi mat khau',
              style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Mat khau hien tai',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscureCurrent ? 'Hien mat khau' : 'An mat khau',
                  onPressed: () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                  icon: Icon(_obscureCurrent
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Mat khau moi',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscureNew ? 'Hien mat khau' : 'An mat khau',
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  icon: Icon(_obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saving ? null : _save(),
              decoration: InputDecoration(
                labelText: 'Xac nhan mat khau moi',
                prefixIcon: const Icon(Icons.verified_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscureConfirm ? 'Hien mat khau' : 'An mat khau',
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  icon: Icon(_obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _error,
                style: const TextStyle(
                    color: AppColors.danger, fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Luu mat khau'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSearchSheet extends StatelessWidget {
  const _UserSearchSheet({required this.users});

  final List<ChatUser> users;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chon nguoi dung',
              style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (users.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: EmptyState(
                    icon: Icons.person_search_outlined,
                    text: 'Khong tim thay nguoi dung'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final display = user.fullname.trim().isEmpty
                        ? user.userid
                        : user.fullname;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: YSAvatar(label: display, size: 42),
                      title: Text(display,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(user.userid),
                      onTap: () => Navigator.of(context).pop(user),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ForwardSheet extends StatelessWidget {
  const _ForwardSheet({
    required this.conversations,
    required this.currentUserid,
    required this.currentConversationId,
  });

  final List<ChatConversation> conversations;
  final String currentUserid;
  final int currentConversationId;

  @override
  Widget build(BuildContext context) {
    final items = conversations
        .where((conversation) => conversation.id != currentConversationId)
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Chuyen tiep den',
              style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: EmptyState(
                    icon: Icons.forward_outlined,
                    text: 'Chua co cuoc tro chuyen khac'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final conversation = items[index];
                    final title = conversation.titleFor(currentUserid);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: conversation.type == 'group'
                          ? _GroupAvatar(count: conversation.memberCount)
                          : YSAvatar(label: title, size: 42),
                      title: Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_lastMessagePreview(conversation),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop(conversation),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PollCreateSheet extends StatefulWidget {
  const _PollCreateSheet();

  @override
  State<_PollCreateSheet> createState() => _PollCreateSheetState();
}

class _PollCreateSheetState extends State<_PollCreateSheet> {
  final _questionController = TextEditingController();
  final _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _allowCustomOptions = false;
  bool _allowMultiple = false;
  bool _showVoters = true;
  bool _submitting = false;
  String _error = '';

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 20) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    final controller = _optionControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  Future<void> _submit() async {
    final question = _questionController.text.trim();
    final options = _optionControllers
        .map((controller) => controller.text.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (question.isEmpty || options.length < 2) {
      setState(() => _error = 'Can cau hoi va it nhat 2 lua chon');
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      await context.read<AppState>().createPoll(
            question: question,
            options: options,
            allowCustomOptions: _allowCustomOptions,
            allowMultiple: _allowMultiple,
            showVoters: _showVoters,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'Tao binh chon khong thanh cong');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            18, 4, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tao binh chon',
                style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _questionController,
                decoration: const InputDecoration(
                  labelText: 'Cau hoi',
                  prefixIcon: Icon(Icons.help_outline),
                ),
              ),
              const SizedBox(height: 12),
              ..._optionControllers.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: entry.value,
                          decoration: InputDecoration(
                            labelText: 'Lua chon ${entry.key + 1}',
                            prefixIcon: const Icon(Icons.circle_outlined),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Xoa',
                        onPressed: _optionControllers.length <= 2
                            ? null
                            : () => _removeOption(entry.key),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed:
                      _optionControllers.length >= 20 ? null : _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Them lua chon'),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowMultiple,
                onChanged: (value) => setState(() => _allowMultiple = value),
                title: const Text('Cho phep chon nhieu'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowCustomOptions,
                onChanged: (value) =>
                    setState(() => _allowCustomOptions = value),
                title: const Text('Cho phep them lua chon'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showVoters,
                onChanged: (value) => setState(() => _showVoters = value),
                title: const Text('Hien nguoi binh chon'),
              ),
              if (_error.isNotEmpty)
                Text(_error,
                    style: const TextStyle(
                        color: AppColors.danger, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.how_to_vote_outlined),
                label: const Text('Tao binh chon'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.onDownload});

  final ValueChanged<ChatAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conversation = state.selectedConversation;
    final currentUserid = state.tokenStore.userid ?? '';
    if (conversation == null) return const SizedBox.shrink();

    final title = conversation.titleFor(currentUserid);
    final media = state.messages
        .expand((message) => message.attachments)
        .where((attachment) =>
            _isImageAttachment(attachment) || _isVideoAttachment(attachment))
        .toList()
        .reversed
        .take(12)
        .toList();
    final documents = state.messages
        .expand((message) => message.attachments)
        .where((attachment) =>
            !_isImageAttachment(attachment) &&
            !_isVideoAttachment(attachment) &&
            !_isAudioAttachment(attachment))
        .toList()
        .reversed
        .take(12)
        .toList();
    final polls = state.messages
        .where((message) => message.type == 'poll' && message.poll != null)
        .toList()
        .reversed
        .take(12)
        .toList();

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        maxChildSize: 0.96,
        minChildSize: 0.45,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            children: [
              Center(
                child: conversation.type == 'group'
                    ? _GroupAvatar(count: conversation.memberCount)
                    : YSAvatar(label: title, size: 74),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                conversation.type == 'group'
                    ? '${conversation.memberCount} thanh vien'
                    : 'Chat truc tiep',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.muted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              const _InfoSectionTitle(title: 'Thanh vien'),
              ...conversation.members.map((member) {
                final display = member.fullname.trim().isEmpty
                    ? member.userid
                    : member.fullname;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: YSAvatar(
                      label: display, size: 38, online: member.isOnline),
                  title: Text(display,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(member.userid),
                );
              }),
              const SizedBox(height: 12),
              const _InfoSectionTitle(title: 'Media'),
              if (media.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Chua co hinh anh',
                      style: TextStyle(color: AppColors.muted)),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 7,
                    mainAxisSpacing: 7,
                  ),
                  itemCount: media.length,
                  itemBuilder: (context, index) {
                    final file = media[index];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            state.apiClient.absoluteUrl(file.fileUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(color: AppColors.brandSoftest),
                          ),
                          if (_isVideoAttachment(file))
                            const Center(
                              child: Icon(Icons.play_circle_fill,
                                  color: Colors.white, size: 34),
                            ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: InkWell(
                              onTap: () => onDownload(file),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.download_outlined,
                                    color: Colors.white, size: 15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 16),
              const _InfoSectionTitle(title: 'Binh chon'),
              if (polls.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Chua co binh chon',
                      style: TextStyle(color: AppColors.muted)),
                )
              else
                ...polls.map((message) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.how_to_vote_outlined,
                          color: AppColors.brand),
                      title: Text(message.poll?.question ?? message.content,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${message.poll?.totalVotes ?? 0} luot binh chon'),
                    )),
              const SizedBox(height: 16),
              const _InfoSectionTitle(title: 'Tep da chia se'),
              if (documents.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Chua co tep',
                      style: TextStyle(color: AppColors.muted)),
                )
              else
                ...documents.map((file) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined,
                          color: AppColors.brand),
                      title: const Text('Tep dinh kem',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_formatBytes(file.fileSize)),
                      trailing: IconButton(
                        tooltip: 'Tai ve',
                        onPressed: () => onDownload(file),
                        icon: const Icon(Icons.download_outlined),
                      ),
                    )),
              if (state.hasMoreMessages)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: OutlinedButton.icon(
                    onPressed: state.loadingOlderMessages
                        ? null
                        : () => context.read<AppState>().loadOlderMessages(),
                    icon: state.loadingOlderMessages
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.history),
                    label: const Text('Tai them tin cu'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoSectionTitle extends StatelessWidget {
  const _InfoSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.line),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.groups_outlined,
              color: AppColors.brandDark, size: 22),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(8)),
              child: Text('$count',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }
}

ChatUser? _presenceMember(ChatConversation conversation, String currentUserid) {
  return conversation.members
      .where((user) => user.userid != currentUserid)
      .firstOrNull;
}

String _lastMessagePreview(ChatConversation conversation) {
  final message = conversation.lastMessage;
  if (message == null) return '';
  if (message.content.trim().isNotEmpty) return message.content.trim();
  final attachment = message.attachments.firstOrNull;
  if (attachment != null) return attachment.fileName;
  if (message.type == 'voice') return 'Tin nhan thoai';
  if (message.type == 'image') return 'Hinh anh';
  return 'Tap tin';
}

String _messagePreview(ChatMessage message) {
  if (message.content.trim().isNotEmpty) return message.content.trim();
  if (message.attachments.any(_isImageAttachment)) return 'Hinh anh';
  if (message.type == 'voice') return 'Tin nhan thoai';
  if (message.attachments.isNotEmpty) return 'Tep dinh kem';
  return 'Tin nhan';
}

bool _isImageAttachment(ChatAttachment attachment) {
  final mime = attachment.mimeType.toLowerCase();
  final name = (attachment.fileName.isNotEmpty
          ? attachment.fileName
          : attachment.relativePath)
      .toLowerCase();
  final ext = name.split('.').last;
  return mime.startsWith('image/') ||
      ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext);
}

bool _isVideoAttachment(ChatAttachment attachment) {
  final mime = attachment.mimeType.toLowerCase();
  final ext = _attachmentExt(attachment);
  return mime.startsWith('video/') ||
      ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
}

bool _isAudioAttachment(ChatAttachment attachment) {
  final mime = attachment.mimeType.toLowerCase();
  final ext = _attachmentExt(attachment);
  return mime.startsWith('audio/') ||
      ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'webm'].contains(ext);
}

String _attachmentExt(ChatAttachment attachment) {
  final name = (attachment.fileName.isNotEmpty
          ? attachment.fileName
          : attachment.relativePath)
      .toLowerCase();
  final pieces = name.split('.');
  return pieces.length > 1 ? pieces.last : '';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remain = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remain.toString().padLeft(2, '0')}';
}

String _safeDownloadName(ChatAttachment attachment) {
  final raw = [
    attachment.relativePath.split('/').last,
    attachment.fileName,
    'ys-chat-file-${DateTime.now().millisecondsSinceEpoch}',
  ].firstWhere((value) => value.trim().isNotEmpty);
  return raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String _conversationTime(ChatConversation conversation) {
  final createdAt = conversation.lastMessage?.createdAt;
  if (createdAt == null) return '';
  final local = createdAt.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return DateFormat('HH:mm').format(local);
  }
  return DateFormat('dd/MM').format(local);
}

extension _AvatarUrl on ChatUser {
  String? avatarUrl(AppState state) {
    if (avatar.isEmpty) return null;
    return state.apiClient.absoluteUrl(avatar);
  }
}
