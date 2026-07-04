import 'dart:io';

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
    await context.read<AppState>().sendText(text);
  }

  Future<void> _pickFiles(FileType type) async {
    final result = await FilePicker.pickFiles(type: type, allowMultiple: true);
    final files = result?.paths.whereType<String>().map(File.new).toList() ??
        const <File>[];
    if (files.isEmpty || !mounted) return;
    await context
        .read<AppState>()
        .sendFiles(files, type: type == FileType.image ? 'image' : 'file');
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final currentUserid = state.tokenStore.userid ?? '';

    return Scaffold(
      body: LayoutBuilder(
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
            onBack: () => context.read<AppState>().clearSelectedConversation(),
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
                  onModeChanged: (mode) => setState(() => _panelMode = mode),
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
            const SizedBox(height: 10),
            _RailButton(
              tooltip: 'Dang xuat',
              icon: Icons.logout,
              onTap: () => context.read<AppState>().logout(),
            ),
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
              tooltip: 'Lam moi',
              icon: Icons.refresh,
              onTap: () => context.read<AppState>().refreshChat(),
            ),
            _RailButton(
                tooltip: 'Ho so',
                icon: Icons.account_circle_outlined,
                onTap: onProfile),
            _RailButton(
              tooltip: 'Dang xuat',
              icon: Icons.logout,
              onTap: () => context.read<AppState>().logout(),
            ),
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
              onRefresh: () => context.read<AppState>().refreshChat(),
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
                child: RefreshIndicator(
                  onRefresh: () => context.read<AppState>().refreshChat(),
                  child: _ConversationList(
                    conversations: _filterConversations(
                        state.conversations, widget.searchController.text),
                    currentUserid: widget.currentUserid,
                    selectedConversationId: state.selectedConversation?.id,
                  ),
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
    required this.onRefresh,
  });

  final String title;
  final String subtitle;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final VoidCallback onRefresh;

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
                tooltip: 'Lam moi', icon: Icons.refresh, onTap: onRefresh),
            const SizedBox(width: 8),
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

class _Thread extends StatelessWidget {
  const _Thread({
    required this.currentUserid,
    required this.messageController,
    required this.recording,
    required this.wide,
    required this.onBack,
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
  final VoidCallback onSend;
  final VoidCallback onPickFiles;
  final VoidCallback onPickImages;
  final VoidCallback onRecord;

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
              currentUserid: currentUserid,
              wide: wide,
              onBack: onBack,
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                reverse: true,
                itemCount: state.messages.length,
                itemBuilder: (context, index) {
                  final message = state.messages.reversed.elementAt(index);
                  return MessageBubble(
                    message: message,
                    mine: message.senderUserid == currentUserid,
                    resolveUrl: state.apiClient.absoluteUrl,
                  );
                },
              ),
            ),
            _Composer(
              controller: messageController,
              recording: recording,
              onSend: onSend,
              onPickFiles: onPickFiles,
              onPickImages: onPickImages,
              onRecord: onRecord,
            ),
          ],
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
  });

  final ChatConversation conversation;
  final String currentUserid;
  final bool wide;
  final VoidCallback onBack;

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
          IconButton(
            tooltip: 'Lam moi',
            onPressed: () =>
                context.read<AppState>().selectConversation(conversation),
            icon: const Icon(Icons.refresh),
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
    required this.onSend,
    required this.onPickFiles,
    required this.onPickImages,
    required this.onRecord,
  });

  final TextEditingController controller;
  final bool recording;
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
