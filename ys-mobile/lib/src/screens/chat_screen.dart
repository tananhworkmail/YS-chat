import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app/app_state.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';

enum _PanelMode { chats, contacts }

enum _ContactSection { people, groups }

enum _ChatSearchScope { all, messages, contacts, files }

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
  AppState? _observedAppState;
  int _lastCallNoticeSequence = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (identical(_observedAppState, state)) return;
    _observedAppState?.removeListener(_handleCallNotice);
    _observedAppState = state;
    state.addListener(_handleCallNotice);
    _handleCallNotice();
  }

  void _handleCallNotice() {
    final state = _observedAppState;
    if (state == null ||
        state.callNoticeSequence <= _lastCallNoticeSequence ||
        state.callNotice.trim().isEmpty) {
      return;
    }
    _lastCallNoticeSequence = state.callNoticeSequence;
    final notice = state.callNotice;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.callStatus(notice))),
      );
    });
  }

  @override
  void dispose() {
    _observedAppState?.removeListener(_handleCallNotice);
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
    final users = await _findExactUsers(value);
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

  Future<void> _addContact([String? keyword]) async {
    final state = context.read<AppState>();
    try {
      var value = (keyword ?? _contactSearchController.text).trim();
      if (value.isEmpty) {
        final controller = TextEditingController();
        final requested = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.t('addContact')),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.l10n.t('enterMemberUserid'),
              ),
              onSubmitted: (input) =>
                  Navigator.of(dialogContext).pop(input.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(context.l10n.t('cancel')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: Text(context.l10n.t('addContact')),
              ),
            ],
          ),
        );
        controller.dispose();
        if (requested == null || requested.trim().isEmpty || !mounted) return;
        value = requested.trim();
      }
      if (value.isEmpty) return;
      final users = await _findExactUsers(value);
      if (!mounted) return;
      if (users.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('noUsersFound'))),
        );
        return;
      }
      final selected = await showModalBottomSheet<ChatUser>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _UserSearchSheet(users: users),
      );
      if (selected == null || !mounted) return;
      await state.addContact(selected.userid);
      _contactSearchController.clear();
      if (!mounted) return;
      final display = selected.displayName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.l10n.t('contactAdded')}: $display')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('addContactFailed'))),
      );
    }
  }

  Future<List<ChatUser>> _findExactUsers(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];
    final users = await context.read<AppState>().apiClient.searchUsers(query);
    final exact = users
        .where(
            (user) => user.userid.trim().toLowerCase() == query.toLowerCase())
        .toList();
    return exact;
  }

  Future<void> _addActiveConversationContact() async {
    final state = context.read<AppState>();
    final conversation = state.selectedConversation;
    if (conversation == null || conversation.type != 'direct') return;
    final currentUserid = state.tokenStore.userid ?? '';
    final peer = conversation.members.firstWhere(
      (member) => member.userid != currentUserid,
      orElse: () => const ChatUser(userid: '', fullname: ''),
    );
    if (peer.userid.isEmpty) return;
    try {
      await state.addContact(peer.userid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('contactAdded'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('addContactFailed'))),
      );
    }
  }

  Future<void> _editActiveConversationNickname() async {
    final state = context.read<AppState>();
    final conversation = state.selectedConversation;
    if (conversation == null || conversation.type != 'direct') return;
    final currentUserid = state.tokenStore.userid ?? '';
    final peer = conversation.members
        .where((member) => member.userid != currentUserid)
        .firstOrNull;
    if (peer == null ||
        !state.contacts.any((contact) =>
            contact.userid.toLowerCase() == peer.userid.toLowerCase())) {
      return;
    }
    final nickname = await _requestNickname(
      context,
      contact: peer,
      initialValue: peer.nickname,
    );
    if (nickname == null || !mounted) return;
    try {
      await state.updateContactNickname(peer.userid, nickname);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n
              .t(nickname.isEmpty ? 'nicknameRemoved' : 'nicknameSaved')),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('nicknameFailed'))),
      );
    }
  }

  Future<void> _showCreateGroupSheet() async {
    final state = context.read<AppState>();
    final draft = await showModalBottomSheet<_CreateGroupDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateGroupSheet(
        contacts: state.contacts,
        currentUserid: state.tokenStore.userid ?? '',
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await state.createGroupConversation(draft.name, draft.memberUserids);
      if (mounted) setState(() => _panelMode = _PanelMode.chats);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('groupCreateFailed'))),
      );
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
      final result = await OpenFilex.open(destination);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.downloaded(filename))),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('downloadFailed'))),
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
    final sent = await state.forwardMessage(target, message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.t(sent ? 'forwardedMessage' : 'sendFailed'),
        ),
      ),
    );
  }

  Future<void> _editMessage(ChatMessage message) async {
    final controller = TextEditingController(text: message.content);
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('editMessage')),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: 4000,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(context.l10n.t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty || !mounted) return;
    try {
      await context.read<AppState>().editMessage(message, content);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('messageActionFailed'))),
      );
    }
  }

  Future<void> _showMessageEditHistory(ChatMessage message) async {
    final future =
        context.read<AppState>().apiClient.getMessageEditHistory(message.id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditHistorySheet(history: future),
    );
  }

  Future<void> _recallMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.t('recallMessage')),
            content: Text(context.l10n.t('recallConfirm')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(context.l10n.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(context.l10n.t('recallMessage')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      await context.read<AppState>().recallMessage(message);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('messageActionFailed'))),
      );
    }
  }

  Future<void> _deleteMessageForMe(ChatMessage message) async {
    try {
      await context.read<AppState>().deleteMessageForMe(message);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('messageActionFailed'))),
      );
    }
  }

  Future<void> _showInfoPanel() async {
    final conversation = context.read<AppState>().selectedConversation;
    if (conversation == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InfoPanel(onDownload: _downloadAttachment),
    );
  }

  Future<void> _openPollSheet() async {
    final conversation = context.read<AppState>().selectedConversation;
    if (conversation == null || conversation.type != 'group') return;
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
                onAddContact: _addContact,
                onCreateGroup: _showCreateGroupSheet,
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
                onEdit: _editMessage,
                onShowEditHistory: _showMessageEditHistory,
                onRecall: _recallMessage,
                onDeleteForMe: _deleteMessageForMe,
                onDownload: _downloadAttachment,
                onInfo: _showInfoPanel,
                onAddContact: _addActiveConversationContact,
                onEditNickname: _editActiveConversationNickname,
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
    final unreadCount = context.watch<AppState>().totalUnreadMessages;
    return Container(
      width: 72,
      color: AppColors.brandDark,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SafeArea(
        child: Column(
          children: [
            const BrandLogo(size: 40, padding: 5, shadow: false),
            const SizedBox(height: 16),
            _RailButton(
              tooltip: context.l10n.t('messages'),
              icon: Icons.chat_bubble_outline,
              active: mode == _PanelMode.chats,
              badgeCount: unreadCount,
              onTap: () => onModeChanged(_PanelMode.chats),
            ),
            const SizedBox(height: 6),
            _RailButton(
              tooltip: context.l10n.t('contacts'),
              icon: Icons.groups_outlined,
              active: mode == _PanelMode.contacts,
              onTap: () => onModeChanged(_PanelMode.contacts),
            ),
            const Spacer(),
            _RailButton(
                tooltip: context.l10n.t('profile'),
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
    final unreadCount = context.watch<AppState>().totalUnreadMessages;
    return SafeArea(
      top: false,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
              tooltip: context.l10n.t('messages'),
              icon: Icons.chat_bubble_outline,
              active: mode == _PanelMode.chats,
              badgeCount: unreadCount,
              onTap: () => onModeChanged(_PanelMode.chats),
            ),
            _RailButton(
              tooltip: context.l10n.t('contacts'),
              icon: Icons.groups_outlined,
              active: mode == _PanelMode.contacts,
              onTap: () => onModeChanged(_PanelMode.contacts),
            ),
            _RailButton(
                tooltip: context.l10n.t('profile'),
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
    this.badgeCount = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.78),
                size: 22,
              ),
              if (badgeCount > 0)
                Positioned(
                  right: 2,
                  top: 2,
                  child: _UnreadBadge(count: badgeCount),
                ),
            ],
          ),
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

    final currentUserid = state.tokenStore.userid ?? '';
    final conversation = state.conversations
        .where((item) => item.id == state.callConversationId)
        .firstOrNull;
    final member = conversation == null
        ? null
        : _presenceMember(conversation, currentUserid);
    final imageUrl = conversation?.avatar.isNotEmpty == true
        ? state.apiClient.absoluteUrl(conversation!.avatar)
        : member?.avatarUrl(state);
    final status = state.callState == 'active'
        ? context.l10n.callingDuration(_formatDuration(state.callDuration))
        : context.l10n.callStatus(state.callStatus);

    return Positioned.fill(
      child: Material(
        color: const Color(0xff111827),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      color: Color(0xff9ca3af),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.t('call'),
                      style: const TextStyle(
                        color: Color(0xffd1d5db),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 2),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                      width: 2,
                    ),
                  ),
                  child: YSAvatar(
                    label: state.callPeerName,
                    imageUrl: imageUrl,
                    online: member?.isOnline,
                    size: 96,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  state.callPeerName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffd1d5db),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(flex: 3),
                if (state.callState == 'incoming')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallActionButton(
                        icon: Icons.call_end,
                        label: context.l10n.t('rejectCall'),
                        color: AppColors.danger,
                        onTap: () =>
                            context.read<AppState>().rejectIncomingCall(),
                      ),
                      _CallActionButton(
                        icon: Icons.call,
                        label: context.l10n.t('acceptCall'),
                        color: const Color(0xff16a34a),
                        onTap: () =>
                            context.read<AppState>().acceptIncomingCall(),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _CallActionButton(
                        icon: state.callMuted ? Icons.mic_off : Icons.mic,
                        label: context.l10n
                            .t(state.callMuted ? 'unmuteCall' : 'muteCall'),
                        color: state.callMuted
                            ? const Color(0xfff59e0b)
                            : Colors.white.withValues(alpha: 0.16),
                        onTap: () => context.read<AppState>().toggleCallMute(),
                      ),
                      _CallActionButton(
                        icon: state.callSpeakerOn
                            ? Icons.volume_up
                            : Icons.hearing,
                        label: context.l10n.t('speakerCall'),
                        color: state.callSpeakerOn
                            ? AppColors.brand
                            : Colors.white.withValues(alpha: 0.16),
                        onTap: () =>
                            context.read<AppState>().toggleCallSpeaker(),
                      ),
                      _CallActionButton(
                        icon: Icons.call_end,
                        label: context.l10n.t('endCall'),
                        color: AppColors.danger,
                        onTap: () => context.read<AppState>().endOrCancelCall(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: label,
            child: Material(
              color: color,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox.square(
                  dimension: 58,
                  child: Icon(icon, color: Colors.white, size: 25),
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    required this.onAddContact,
    required this.onCreateGroup,
    required this.onModeChanged,
  });

  final _PanelMode mode;
  final TextEditingController searchController;
  final TextEditingController contactSearchController;
  final String currentUserid;
  final Future<void> Function([String? keyword]) onSearchUser;
  final Future<void> Function([String? keyword]) onAddContact;
  final VoidCallback onCreateGroup;
  final ValueChanged<_PanelMode> onModeChanged;

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  Timer? _exactUserSearchTimer;
  ChatUser? _exactSearchedUser;
  ChatSearchResults _searchResults = const ChatSearchResults();
  _ChatSearchScope _searchScope = _ChatSearchScope.all;
  bool _searching = false;
  int _exactUserSearchRequest = 0;
  _ContactSection _contactSection = _ContactSection.people;

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_refresh);
    widget.contactSearchController.addListener(_refresh);
    _scheduleExactUserSearch();
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
    if (oldWidget.mode != widget.mode ||
        oldWidget.searchController != widget.searchController) {
      _scheduleExactUserSearch();
    }
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_refresh);
    widget.contactSearchController.removeListener(_refresh);
    _exactUserSearchTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    if (widget.mode == _PanelMode.chats) _scheduleExactUserSearch();
  }

  void _scheduleExactUserSearch() {
    _exactUserSearchTimer?.cancel();
    final query = widget.searchController.text.trim();
    final request = ++_exactUserSearchRequest;
    if (widget.mode != _PanelMode.chats || query.isEmpty) {
      if (mounted) {
        setState(() {
          _exactSearchedUser = null;
          _searchResults = const ChatSearchResults();
          _searching = false;
        });
      }
      return;
    }

    _exactUserSearchTimer = Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _searching = true);
      _loadExactUserSearch(query, request);
    });
  }

  Future<void> _loadExactUserSearch(String query, int request) async {
    try {
      final apiClient = context.read<AppState>().apiClient;
      final resultsFuture = apiClient.searchChat(query, _searchScope.name);
      final usersFuture = apiClient.searchUsers(query);
      final results = await resultsFuture;
      final users = await usersFuture;
      if (!mounted ||
          request != _exactUserSearchRequest ||
          widget.mode != _PanelMode.chats ||
          widget.searchController.text.trim() != query) {
        return;
      }
      ChatUser? exact;
      for (final user in users) {
        if (user.userid.trim().toLowerCase() == query.toLowerCase()) {
          exact = user;
          break;
        }
      }
      setState(() {
        _exactSearchedUser = exact;
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted && request == _exactUserSearchRequest) {
        setState(() {
          _exactSearchedUser = null;
          _searchResults = const ChatSearchResults();
          _searching = false;
        });
      }
    }
  }

  void _changeSearchScope(_ChatSearchScope scope) {
    if (_searchScope == scope) return;
    setState(() => _searchScope = scope);
    _scheduleExactUserSearch();
  }

  Future<void> _openExactUser(ChatUser user) async {
    await context.read<AppState>().openDirectConversation(user.userid);
    if (!mounted) return;
    widget.onModeChanged(_PanelMode.chats);
  }

  Future<void> _addExactUser(ChatUser user) async {
    try {
      await context.read<AppState>().addContact(user.userid);
      if (!mounted) return;
      setState(() => _exactSearchedUser = user.copyWith(isContact: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('contactAdded'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('addContactFailed'))),
      );
    }
  }

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
              title: isContacts
                  ? context.l10n.t('contacts')
                  : context.l10n.t('messages'),
              subtitle: 'YS Chat',
              primaryIcon: isContacts
                  ? Icons.person_add_alt_outlined
                  : Icons.group_add_outlined,
              primaryTooltip:
                  context.l10n.t(isContacts ? 'addContact' : 'createGroup'),
              onPrimary: () => isContacts
                  ? widget.onAddContact(searchController.text)
                  : widget.onCreateGroup(),
              secondaryIcon: isContacts ? null : Icons.person_add_alt_outlined,
              secondaryTooltip:
                  isContacts ? null : context.l10n.t('addContact'),
              onSecondary: isContacts ? null : () => widget.onAddContact(''),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (value) =>
                    isContacts ? null : widget.onSearchUser(value),
                decoration: InputDecoration(
                  hintText: isContacts
                      ? context.l10n.t(
                          _contactSection == _ContactSection.people
                              ? 'searchContacts'
                              : 'searchGroups',
                        )
                      : context.l10n.t('searchConversations'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchController.text.isEmpty
                      ? (isContacts
                          ? null
                          : IconButton(
                              tooltip: context.l10n.t('openChat'),
                              onPressed: () =>
                                  widget.onSearchUser(searchController.text),
                              icon: const Icon(Icons.chat_bubble_outline),
                            ))
                      : IconButton(
                          tooltip: context.l10n.t('clear'),
                          onPressed: searchController.clear,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            if (isContacts)
              _ContactSectionTabs(
                selected: _contactSection,
                peopleCount: state.contacts.length,
                groupCount: state.conversations
                    .where((conversation) => conversation.type == 'group')
                    .length,
                onChanged: (section) =>
                    setState(() => _contactSection = section),
              ),
            if (isContacts)
              Expanded(
                child: _contactSection == _ContactSection.people
                    ? _ContactList(
                        keyword: widget.contactSearchController.text,
                        onStartChat: (userid) async {
                          await context
                              .read<AppState>()
                              .openDirectConversation(userid);
                          widget.onModeChanged(_PanelMode.chats);
                        },
                      )
                    : _GroupContactList(
                        keyword: widget.contactSearchController.text,
                        currentUserid: widget.currentUserid,
                        onOpenGroup: (conversation) async {
                          await context
                              .read<AppState>()
                              .selectConversation(conversation);
                          widget.onModeChanged(_PanelMode.chats);
                        },
                      ),
              )
            else
              Expanded(
                child: widget.searchController.text.trim().isEmpty
                    ? _ConversationList(
                        conversations: state.conversations,
                        currentUserid: widget.currentUserid,
                        selectedConversationId: state.selectedConversation?.id,
                      )
                    : Column(
                        children: [
                          _SearchScopeTabs(
                            selected: _searchScope,
                            onChanged: _changeSearchScope,
                          ),
                          Expanded(
                            child: _MobileSearchResults(
                              scope: _searchScope,
                              loading: _searching,
                              exactUser: _exactSearchedUser,
                              results: _searchResults,
                              conversations: _filterConversations(
                                state.conversations,
                                widget.searchController.text,
                              ),
                              allConversations: state.conversations,
                              currentUserid: widget.currentUserid,
                              onOpenExactUser: _openExactUser,
                              onAddExactUser: _addExactUser,
                              onOpenContact: _openExactUser,
                              onOpenConversation: (conversation) async {
                                await state.selectConversation(conversation);
                                if (mounted) {
                                  widget.onModeChanged(_PanelMode.chats);
                                }
                              },
                              onOpenMessage: (message) =>
                                  _openSearchMessage(message),
                            ),
                          ),
                        ],
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
      return title.contains(query);
    }).toList();
  }

  Future<void> _openSearchMessage(ChatMessage message) async {
    final state = context.read<AppState>();
    final conversation = state.conversations
        .where((item) => item.id == message.conversationId)
        .firstOrNull;
    if (conversation == null) return;
    await state.openSearchMessage(conversation, message.id);
    if (mounted) widget.onModeChanged(_PanelMode.chats);
  }
}

class _ExactUserResult extends StatelessWidget {
  const _ExactUserResult({
    required this.user,
    required this.onOpenChat,
    required this.onAddContact,
  });

  final ChatUser user;
  final VoidCallback onOpenChat;
  final VoidCallback onAddContact;

  @override
  Widget build(BuildContext context) {
    final display = user.displayName;
    final isContact = user.isContact ||
        context.watch<AppState>().contacts.any((contact) =>
            contact.userid.toLowerCase() == user.userid.toLowerCase());
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Material(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
              YSAvatar(label: display, size: 38),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.ink, fontWeight: FontWeight.w900)),
                    Text(user.userid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.l10n.t('openChat'),
                onPressed: onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 19),
              ),
              IconButton(
                tooltip:
                    context.l10n.t(isContact ? 'contactAdded' : 'addContact'),
                onPressed: isContact ? null : onAddContact,
                icon: Icon(isContact
                    ? Icons.check_circle_outline
                    : Icons.person_add_alt_1_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchScopeTabs extends StatelessWidget {
  const _SearchScopeTabs({required this.selected, required this.onChanged});

  final _ChatSearchScope selected;
  final ValueChanged<_ChatSearchScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: SegmentedButton<_ChatSearchScope>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -3, vertical: -3),
            textStyle: WidgetStatePropertyAll(
              TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
          segments: [
            ButtonSegment(
              value: _ChatSearchScope.all,
              label: Text(context.l10n.t('searchAll')),
            ),
            ButtonSegment(
              value: _ChatSearchScope.messages,
              label: Text(context.l10n.t('searchMessages')),
            ),
            ButtonSegment(
              value: _ChatSearchScope.contacts,
              label: Text(context.l10n.t('searchContactNames')),
            ),
            ButtonSegment(
              value: _ChatSearchScope.files,
              label: Text(context.l10n.t('searchFiles')),
            ),
          ],
          selected: {selected},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

class _MobileSearchResults extends StatelessWidget {
  const _MobileSearchResults({
    required this.scope,
    required this.loading,
    required this.exactUser,
    required this.results,
    required this.conversations,
    required this.allConversations,
    required this.currentUserid,
    required this.onOpenExactUser,
    required this.onAddExactUser,
    required this.onOpenContact,
    required this.onOpenConversation,
    required this.onOpenMessage,
  });

  final _ChatSearchScope scope;
  final bool loading;
  final ChatUser? exactUser;
  final ChatSearchResults results;
  final List<ChatConversation> conversations;
  final List<ChatConversation> allConversations;
  final String currentUserid;
  final ValueChanged<ChatUser> onOpenExactUser;
  final ValueChanged<ChatUser> onAddExactUser;
  final ValueChanged<ChatUser> onOpenContact;
  final ValueChanged<ChatConversation> onOpenConversation;
  final ValueChanged<ChatMessage> onOpenMessage;

  @override
  Widget build(BuildContext context) {
    final showAll = scope == _ChatSearchScope.all;
    final showContacts = showAll || scope == _ChatSearchScope.contacts;
    final showMessages = showAll || scope == _ChatSearchScope.messages;
    final showFiles = showAll || scope == _ChatSearchScope.files;
    final exactIsInContacts = exactUser != null &&
        results.contacts.any((contact) =>
            contact.userid.toLowerCase() == exactUser!.userid.toLowerCase());
    final hasResults = (showAll && conversations.isNotEmpty) ||
        (showContacts &&
            (results.contacts.isNotEmpty ||
                (exactUser != null && !exactIsInContacts))) ||
        (showMessages && results.messages.isNotEmpty) ||
        (showFiles && results.files.isNotEmpty);

    if (loading && !hasResults) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (!hasResults) {
      return EmptyState(
        icon: Icons.search_off_outlined,
        text: context.l10n.t('noSearchResults'),
      );
    }

    final children = <Widget>[];
    if (loading) {
      children.add(const LinearProgressIndicator(minHeight: 2));
    }
    if (showAll && conversations.isNotEmpty) {
      children.add(_SearchResultHeader(
        label: context.l10n.t('searchConversationsResult'),
        count: conversations.length,
      ));
      children.addAll(conversations.map((conversation) => _ConversationItem(
            conversation: conversation,
            currentUserid: currentUserid,
            selected: false,
            onTap: () => onOpenConversation(conversation),
          )));
    }
    if (showContacts && exactUser != null && !exactIsInContacts) {
      children.add(_SearchResultHeader(
        label: context.l10n.t('searchContactsResult'),
        count: results.contacts.length + 1,
      ));
      children.add(_ExactUserResult(
        user: exactUser!,
        onOpenChat: () => onOpenExactUser(exactUser!),
        onAddContact: () => onAddExactUser(exactUser!),
      ));
    } else if (showContacts && results.contacts.isNotEmpty) {
      children.add(_SearchResultHeader(
        label: context.l10n.t('searchContactsResult'),
        count: results.contacts.length,
      ));
    }
    if (showContacts) {
      children.addAll(results.contacts.map((contact) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            leading: YSAvatar(label: contact.displayName, size: 36),
            title: Text(
              contact.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(contact.userid),
            trailing: const Icon(Icons.chat_bubble_outline, size: 18),
            onTap: () => onOpenContact(contact),
          )));
    }
    if (showMessages && results.messages.isNotEmpty) {
      children.add(_SearchResultHeader(
        label: context.l10n.t('searchMessagesResult'),
        count: results.messages.length,
      ));
      children.addAll(results.messages.map((message) => _SearchMessageTile(
            message: message,
            conversation: _conversationFor(message),
            currentUserid: currentUserid,
            fileResult: false,
            onTap: () => onOpenMessage(message),
          )));
    }
    if (showFiles && results.files.isNotEmpty) {
      children.add(_SearchResultHeader(
        label: context.l10n.t('searchFilesResult'),
        count: results.files.length,
      ));
      children.addAll(results.files.map((message) => _SearchMessageTile(
            message: message,
            conversation: _conversationFor(message),
            currentUserid: currentUserid,
            fileResult: true,
            onTap: () => onOpenMessage(message),
          )));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      children: children,
    );
  }

  ChatConversation? _conversationFor(ChatMessage message) => allConversations
      .where((conversation) => conversation.id == message.conversationId)
      .firstOrNull;
}

class _SearchResultHeader extends StatelessWidget {
  const _SearchResultHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      child: Text(
        '$label ($count)',
        style: const TextStyle(
          color: AppColors.brandDark,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SearchMessageTile extends StatelessWidget {
  const _SearchMessageTile({
    required this.message,
    required this.conversation,
    required this.currentUserid,
    required this.fileResult,
    required this.onTap,
  });

  final ChatMessage message;
  final ChatConversation? conversation;
  final String currentUserid;
  final bool fileResult;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = conversation?.titleFor(currentUserid) ?? message.senderName;
    final attachment = message.attachments.firstOrNull;
    final preview = fileResult && attachment != null
        ? _attachmentDisplayName(attachment)
        : _messagePreview(context, message);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fileResult ? const Color(0xffeef2ff) : AppColors.brandSoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          fileResult ? Icons.insert_drive_file_outlined : Icons.chat_outlined,
          size: 19,
          color: fileResult ? const Color(0xff4f46e5) : AppColors.brandDark,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

class _ContactSectionTabs extends StatelessWidget {
  const _ContactSectionTabs({
    required this.selected,
    required this.peopleCount,
    required this.groupCount,
    required this.onChanged,
  });

  final _ContactSection selected;
  final int peopleCount;
  final int groupCount;
  final ValueChanged<_ContactSection> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xfff0f4f8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ContactSectionButton(
              label: context.l10n.t('personalContacts'),
              icon: Icons.person_outline,
              count: peopleCount,
              selected: selected == _ContactSection.people,
              onTap: () => onChanged(_ContactSection.people),
            ),
          ),
          Expanded(
            child: _ContactSectionButton(
              label: context.l10n.t('groupContacts'),
              icon: Icons.groups_outlined,
              count: groupCount,
              selected: selected == _ContactSection.groups,
              onTap: () => onChanged(_ContactSection.groups),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactSectionButton extends StatelessWidget {
  const _ContactSectionButton({
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? AppColors.brandDark : AppColors.muted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppColors.ink : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: selected ? AppColors.brandDark : AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.primaryIcon,
    required this.primaryTooltip,
    required this.onPrimary,
    this.secondaryIcon,
    this.secondaryTooltip,
    this.onSecondary,
  });

  final String title;
  final String subtitle;
  final IconData primaryIcon;
  final String primaryTooltip;
  final VoidCallback onPrimary;
  final IconData? secondaryIcon;
  final String? secondaryTooltip;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
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
                        fontSize: 20,
                        fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            if (secondaryIcon != null && onSecondary != null) ...[
              _PanelIconButton(
                tooltip: secondaryTooltip ?? '',
                icon: secondaryIcon!,
                onTap: onSecondary!,
              ),
              const SizedBox(width: 6),
            ],
            _PanelIconButton(
                tooltip: primaryTooltip,
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
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: primary ? AppColors.brand : const Color(0xfff0f4fa),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: primary ? Colors.white : AppColors.ink, size: 19),
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
        children: [
          const SizedBox(height: 120),
          EmptyState(
              icon: Icons.chat_bubble_outline, text: context.l10n.t('noChats')),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
    final state = context.watch<AppState>();
    final title = conversation.titleFor(currentUserid);
    final unreadCount = state.unreadCountFor(conversation.id);
    final member = _presenceMember(conversation, currentUserid);
    final imageUrl = conversation.avatar.isNotEmpty
        ? state.apiClient.absoluteUrl(conversation.avatar)
        : member?.avatarUrl(state);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? AppColors.brandSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          onLongPress: () => _showConversationSettings(context, state),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                if (conversation.type == 'group' && conversation.avatar.isEmpty)
                  _GroupAvatar(count: conversation.memberCount, size: 40)
                else
                  YSAvatar(
                      label: title,
                      imageUrl: imageUrl,
                      online: member?.isOnline,
                      size: 40),
                const SizedBox(width: 9),
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
                          if (conversation.settings.isPinned)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.push_pin,
                                  size: 13, color: AppColors.brand),
                            ),
                          if (conversation.settings.isMuted)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.notifications_off_outlined,
                                  size: 13, color: AppColors.muted),
                            ),
                          if (conversation.settings.isArchived)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.archive_outlined,
                                  size: 13, color: AppColors.muted),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _lastMessagePreview(context, conversation),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unreadCount > 0
                                    ? AppColors.ink
                                    : AppColors.muted,
                                fontSize: 13,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            _UnreadBadge(count: unreadCount),
                          ],
                        ],
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

  Future<void> _showConversationSettings(
      BuildContext context, AppState state) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(conversation.settings.isMuted
                  ? Icons.notifications_outlined
                  : Icons.notifications_off_outlined),
              title: Text(context.l10n.t(conversation.settings.isMuted
                  ? 'unmuteConversation'
                  : 'muteConversation')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                state.setConversationMuted(
                    conversation, !conversation.settings.isMuted);
              },
            ),
            ListTile(
              leading: Icon(conversation.settings.isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin),
              title: Text(context.l10n.t(conversation.settings.isPinned
                  ? 'unpinConversation'
                  : 'pinConversation')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                state.setConversationPinned(
                    conversation, !conversation.settings.isPinned);
              },
            ),
            ListTile(
              leading: Icon(conversation.settings.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined),
              title: Text(context.l10n.t(conversation.settings.isArchived
                  ? 'unarchiveConversation'
                  : 'archiveConversation')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                state.setConversationArchived(
                    conversation, !conversation.settings.isArchived);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
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
      return contact.displayName.toLowerCase().contains(query) ||
          contact.fullname.toLowerCase().contains(query) ||
          contact.userid.toLowerCase().contains(query);
    }).toList()
      ..sort(_compareDirectoryContacts);

    if (contacts.isEmpty) {
      return EmptyState(
          icon: Icons.groups_outlined,
          text: context.l10n.t('noMatchingContacts'));
    }

    final children = <Widget>[];
    String? currentLetter;
    for (final contact in contacts) {
      final display = contact.displayName;
      final letter = _contactDirectoryLetter(display);
      if (letter != currentLetter) {
        currentLetter = letter;
        children.add(_ContactLetterHeader(letter: letter));
      }
      children.add(
        _ContactListItem(
          contact: contact,
          display: display,
          imageUrl: contact.avatar.isNotEmpty
              ? state.apiClient.absoluteUrl(contact.avatar)
              : null,
          onTap: () => onStartChat(contact.userid),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: children,
    );
  }
}

class _ContactLetterHeader extends StatelessWidget {
  const _ContactLetterHeader({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 3),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          color: AppColors.brandDark,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ContactListItem extends StatelessWidget {
  const _ContactListItem({
    required this.contact,
    required this.display,
    required this.imageUrl,
    required this.onTap,
  });

  final ChatUser contact;
  final String display;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              YSAvatar(
                label: display,
                imageUrl: imageUrl,
                online: contact.isOnline,
                size: 40,
              ),
              const SizedBox(width: 9),
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
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      contact.userid,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupContactList extends StatelessWidget {
  const _GroupContactList({
    required this.keyword,
    required this.currentUserid,
    required this.onOpenGroup,
  });

  final String keyword;
  final String currentUserid;
  final Future<void> Function(ChatConversation conversation) onOpenGroup;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final query = keyword.trim().toLowerCase();
    final groups = state.conversations.where((conversation) {
      if (conversation.type != 'group') return false;
      if (query.isEmpty) return true;
      final memberText = conversation.members
          .map((member) => '${member.fullname} ${member.userid}')
          .join(' ')
          .toLowerCase();
      return conversation
              .titleFor(currentUserid)
              .toLowerCase()
              .contains(query) ||
          memberText.contains(query);
    }).toList()
      ..sort((first, second) {
        final firstTime = first.lastMessage?.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final secondTime = second.lastMessage?.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final byLatestMessage = secondTime.compareTo(firstTime);
        if (byLatestMessage != 0) return byLatestMessage;
        return second.id.compareTo(first.id);
      });

    if (groups.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        text: context.l10n.t('noMatchingGroups'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final conversation = groups[index];
        return _ConversationItem(
          conversation: conversation,
          currentUserid: currentUserid,
          selected: state.selectedConversation?.id == conversation.id,
          onTap: () => onOpenGroup(conversation),
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
    required this.onEdit,
    required this.onShowEditHistory,
    required this.onRecall,
    required this.onDeleteForMe,
    required this.onDownload,
    required this.onInfo,
    required this.onAddContact,
    required this.onEditNickname,
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
  final ValueChanged<ChatMessage> onEdit;
  final ValueChanged<ChatMessage> onShowEditHistory;
  final ValueChanged<ChatMessage> onRecall;
  final ValueChanged<ChatMessage> onDeleteForMe;
  final ValueChanged<ChatAttachment> onDownload;
  final VoidCallback onInfo;
  final Future<void> Function() onAddContact;
  final Future<void> Function() onEditNickname;
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
  final Map<int, GlobalKey> _messageKeys = {};
  bool _showLatestButton = false;
  int _lastMessageFocusSequence = 0;

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
    final shouldShowLatest = position.pixels > 220;
    if (shouldShowLatest != _showLatestButton && mounted) {
      setState(() => _showLatestButton = shouldShowLatest);
    }
    if (position.pixels >= position.maxScrollExtent - 180) {
      context.read<AppState>().loadOlderMessages();
    }
  }

  Future<void> _scrollToLatest() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollToMessage(int messageId) async {
    final state = context.read<AppState>();
    final found = await state.loadMessageUntilVisible(messageId);
    if (!found || !mounted) return;

    final orderedMessages = state.messages;
    final ascendingIndex =
        orderedMessages.indexWhere((message) => message.id == messageId);
    if (ascendingIndex < 0) return;
    final listIndex = orderedMessages.length - 1 - ascendingIndex;
    if (_scrollController.hasClients) {
      final targetOffset = (listIndex * 86.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final keyContext = _messageKeys[messageId]?.currentContext;
    if (keyContext == null) return;
    if (!keyContext.mounted) return;
    await Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: 0.35,
    );
  }

  Future<void> _togglePinnedMessage(ChatMessage message) async {
    final state = context.read<AppState>();
    final conversation = state.selectedConversation;
    if (conversation == null || message.id <= 0) return;
    final pinned = state.pinnedMessageFor(conversation.id);
    try {
      if (pinned?.id == message.id) {
        await _unpinMessage(conversation.id);
        return;
      }
      await state.pinMessage(message);
    } catch (_) {
      _showPinError();
    }
  }

  Future<void> _unpinMessage(int conversationId) async {
    try {
      await context.read<AppState>().unpinMessage(conversationId);
    } catch (_) {
      _showPinError();
    }
  }

  void _showPinError() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.t('pinMessageFailed'))));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final conversation = state.selectedConversation;
    if (conversation == null) {
      return Container(
        color: AppColors.canvas,
        child: EmptyState(
            icon: Icons.forum_outlined,
            text: context.l10n.t('selectChatPrompt')),
      );
    }
    final typingUsers = state
        .typingUsersFor(conversation.id)
        .map((userid) =>
            conversation.members
                .where((member) => member.userid == userid)
                .firstOrNull
                ?.displayName ??
            userid)
        .toList(growable: false);

    if (state.messageFocusConversationId == conversation.id &&
        state.messageFocusSequence > _lastMessageFocusSequence &&
        state.messageFocusId > 0) {
      final focusSequence = state.messageFocusSequence;
      _lastMessageFocusSequence = focusSequence;
      final messageId = state.messageFocusId;
      final appState = state;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await _scrollToMessage(messageId);
        if (mounted) {
          appState.clearMessageFocus(focusSequence);
        }
      });
    }

    final pinnedMessage = state.pinnedMessageFor(conversation.id);

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
              onAddContact: widget.onAddContact,
              onEditNickname: widget.onEditNickname,
            ),
            if (pinnedMessage != null)
              _PinnedMessageBar(
                reference: pinnedMessage,
                onOpen: () => _scrollToMessage(pinnedMessage.id),
                onUnpin: () => _unpinMessage(conversation.id),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _ChatBackground(
                      imageUrl: conversation.background.trim().isEmpty
                          ? null
                          : state.apiClient
                              .absoluteUrl(conversation.background.trim()),
                    ),
                  ),
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
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
                      final sender = conversation.members
                          .where(
                              (member) => member.userid == message.senderUserid)
                          .firstOrNull;
                      final key = _messageKeys.putIfAbsent(message.id,
                          () => GlobalKey(debugLabel: 'm-${message.id}'));
                      return KeyedSubtree(
                        key: key,
                        child: MessageBubble(
                          message: message,
                          mine: message.senderUserid == widget.currentUserid,
                          isGroup: conversation.type == 'group',
                          resolveUrl: state.apiClient.absoluteUrl,
                          pinned: pinnedMessage?.id == message.id,
                          onTogglePin: _togglePinnedMessage,
                          onReply: widget.onReply,
                          onForward: widget.onForward,
                          onEdit: widget.onEdit,
                          onShowEditHistory: widget.onShowEditHistory,
                          onRecall: widget.onRecall,
                          onDeleteForMe: widget.onDeleteForMe,
                          onToggleReaction: (message, emoji) => context
                              .read<AppState>()
                              .toggleReaction(message, emoji),
                          onRetry: (message) =>
                              context.read<AppState>().retryMessage(message),
                          onDownload: widget.onDownload,
                          mentionUsers: conversation.type == 'group'
                              ? conversation.members
                              : const [],
                          onOpenMentionProfile: conversation.type == 'group'
                              ? (member) => _showChatUserProfile(
                                  context, member, conversation)
                              : null,
                          onOpenSenderProfile:
                              conversation.type == 'group' && sender != null
                                  ? () => _showChatUserProfile(
                                      context, sender, conversation)
                                  : null,
                          onOpenReference: _scrollToMessage,
                          onVotePoll: (message, optionIds, customOption) =>
                              context.read<AppState>().votePoll(
                                  message, optionIds,
                                  customOption: customOption),
                          onClosePoll: (message) =>
                              context.read<AppState>().closePoll(message),
                        ),
                      );
                    },
                  ),
                  if (_showLatestButton)
                    Positioned(
                      right: 14,
                      bottom: 14,
                      child: Material(
                        color: AppColors.brand,
                        elevation: 4,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: _scrollToLatest,
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.keyboard_double_arrow_down,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (typingUsers.isNotEmpty) _TypingIndicator(users: typingUsers),
            _Composer(
              controller: widget.messageController,
              recording: widget.recording,
              replyingTo: widget.replyingTo,
              conversation: conversation,
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

class _PinnedMessageBar extends StatelessWidget {
  const _PinnedMessageBar({
    required this.reference,
    required this.onOpen,
    required this.onUnpin,
  });

  final ChatMessageReference reference;
  final VoidCallback onOpen;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandSoftest,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
          child: Row(
            children: [
              const Icon(Icons.push_pin, size: 16, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.t('pinnedMessage'),
                      style: const TextStyle(
                        color: AppColors.brandDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      messageReferencePreview(context, reference),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onUnpin,
                tooltip: context.l10n.t('unpinMessage'),
                icon: const Icon(Icons.close, size: 17),
                color: AppColors.muted,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return const ColoredBox(color: AppColors.canvas);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const ColoredBox(color: AppColors.canvas),
        ),
        ColoredBox(color: AppColors.canvas.withValues(alpha: 0.82)),
      ],
    );
  }
}

class _OlderMessagesLoader extends StatelessWidget {
  const _OlderMessagesLoader({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (!loading) {
      return const SizedBox(height: 6);
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
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
    required this.onAddContact,
    required this.onEditNickname,
  });

  final ChatConversation conversation;
  final String currentUserid;
  final bool wide;
  final VoidCallback onBack;
  final VoidCallback onInfo;
  final Future<void> Function() onAddContact;
  final Future<void> Function() onEditNickname;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final title = conversation.titleFor(currentUserid);
    final member = _presenceMember(conversation, currentUserid);
    final canAddContact = conversation.type == 'direct' &&
        member != null &&
        !state.contacts.any((contact) =>
            contact.userid.toLowerCase() == member.userid.toLowerCase());
    final canEditNickname = conversation.type == 'direct' &&
        member != null &&
        state.contacts.any((contact) =>
            contact.userid.toLowerCase() == member.userid.toLowerCase());
    final imageUrl = conversation.avatar.isNotEmpty
        ? state.apiClient.absoluteUrl(conversation.avatar)
        : member?.avatarUrl(state);

    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          if (!wide)
            IconButton(
              tooltip: context.l10n.t('back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          if (conversation.type == 'group' && conversation.avatar.isEmpty)
            _GroupAvatar(count: conversation.memberCount, size: 34)
          else
            YSAvatar(
                label: title,
                imageUrl: imageUrl,
                online: member?.isOnline,
                size: 34),
          const SizedBox(width: 8),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  conversation.type == 'group'
                      ? context.l10n.memberCount(conversation.memberCount)
                      : (member?.isOnline == true
                          ? context.l10n.t('online')
                          : context.l10n.t('directMessage')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (conversation.type == 'direct')
            IconButton(
              tooltip: context.l10n.t('call'),
              onPressed: () => context.read<AppState>().startAudioCall(),
              icon: const Icon(Icons.phone_outlined),
            ),
          if (canAddContact)
            IconButton(
              tooltip: context.l10n.t('addContact'),
              onPressed: () => onAddContact(),
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          if (canEditNickname)
            IconButton(
              tooltip: context.l10n.t('setNickname'),
              onPressed: () => onEditNickname(),
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(
            tooltip: context.l10n.t('info'),
            onPressed: onInfo,
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.users});

  final List<String> users;

  @override
  Widget build(BuildContext context) {
    final names = users.take(2).join(', ');
    final suffix = users.length > 2 ? ' +${users.length - 2}' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 5),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            child: Text('•••',
                style: TextStyle(
                    color: AppColors.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$names$suffix ${context.l10n.t('typing')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditHistorySheet extends StatelessWidget {
  const _EditHistorySheet({required this.history});

  final Future<List<ChatMessageEditHistoryEntry>> history;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, color: AppColors.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.t('editHistory'),
                      style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<ChatMessageEditHistoryEntry>>(
                future: history,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: Text(context.l10n.t('messageActionFailed')));
                  }
                  final entries = snapshot.data ?? const [];
                  if (entries.isEmpty) {
                    return Center(child: Text(context.l10n.t('noEditHistory')));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final editor = entry.editorName.trim().isNotEmpty
                          ? entry.editorName
                          : entry.editorUserid;
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(editor,
                                      style: const TextStyle(
                                          color: AppColors.ink,
                                          fontWeight: FontWeight.w900)),
                                ),
                                if (entry.editedAt != null)
                                  Text(
                                    DateFormat('dd/MM/yyyy HH:mm')
                                        .format(entry.editedAt!.toLocal()),
                                    style: const TextStyle(
                                        color: AppColors.muted, fontSize: 11),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _HistoryContent(
                              label: context.l10n.t('beforeEdit'),
                              content: entry.previousContent,
                              color: AppColors.canvas,
                            ),
                            const SizedBox(height: 6),
                            _HistoryContent(
                              label: context.l10n.t('afterEdit'),
                              content: entry.content,
                              color: const Color(0xfff0fdf4),
                            ),
                          ],
                        ),
                      );
                    },
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

class _HistoryContent extends StatelessWidget {
  const _HistoryContent({
    required this.label,
    required this.content,
    required this.color,
  });

  final String label;
  final String content;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(content, style: const TextStyle(color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.recording,
    required this.replyingTo,
    required this.conversation,
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
  final ChatConversation conversation;
  final VoidCallback onCancelReply;
  final VoidCallback onCreatePoll;
  final VoidCallback onSend;
  final VoidCallback onPickFiles;
  final VoidCallback onPickImages;
  final VoidCallback onRecord;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  List<_MentionOption> _mentionSuggestions = const [];
  int _mentionStart = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateMentionSuggestions);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_updateMentionSuggestions);
      widget.controller.addListener(_updateMentionSuggestions);
    }
    _updateMentionSuggestions();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateMentionSuggestions);
    super.dispose();
  }

  void _updateMentionSuggestions() {
    if (mounted) {
      context.read<AppState>().updateTyping(widget.controller.text);
    }
    final selection = widget.controller.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _setMentionSuggestions(const [], -1);
      return;
    }
    final cursor = selection.baseOffset;
    final textBeforeCursor = widget.controller.text.substring(0, cursor);
    final atIndex = textBeforeCursor.lastIndexOf('@');
    if (widget.conversation.type != 'group' ||
        atIndex < 0 ||
        (atIndex > 0 &&
            !RegExp(r'\s').hasMatch(textBeforeCursor[atIndex - 1]))) {
      _setMentionSuggestions(const [], -1);
      return;
    }

    final query = textBeforeCursor.substring(atIndex + 1);
    if (query.contains('@') || query.contains('\n') || query.contains(' ')) {
      _setMentionSuggestions(const [], -1);
      return;
    }

    final normalizedQuery = query.toLowerCase();
    final options = _mentionOptions(widget.conversation)
        .where((option) =>
            normalizedQuery.isEmpty ||
            option.searchText.contains(normalizedQuery))
        .toList();
    _setMentionSuggestions(options, options.isEmpty ? -1 : atIndex);
  }

  void _setMentionSuggestions(List<_MentionOption> options, int start) {
    if (_mentionStart == start &&
        _mentionSuggestions.length == options.length &&
        _mentionSuggestions
            .asMap()
            .entries
            .every((entry) => entry.value.label == options[entry.key].label)) {
      return;
    }
    setState(() {
      _mentionSuggestions = options;
      _mentionStart = start;
    });
  }

  void _insertMention(_MentionOption option) {
    final selection = widget.controller.selection;
    if (_mentionStart < 0 || !selection.isValid) return;
    final cursor = selection.baseOffset;
    final text = widget.controller.text;
    final mentionText = '@${option.label} ';
    final nextText =
        '${text.substring(0, _mentionStart)}$mentionText${text.substring(cursor)}';
    final nextCursor = _mentionStart + mentionText.length;
    widget.controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
    _setMentionSuggestions(const [], -1);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyingTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                            '${context.l10n.t('replyingTo')} ${widget.replyingTo!.senderName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.brandDark,
                                fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _messagePreview(context, widget.replyingTo!),
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
                      tooltip: context.l10n.t('cancelReply'),
                      onPressed: widget.onCancelReply,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (widget.recording)
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
                    Expanded(
                      child: Text(
                        context.l10n.t('recording'),
                        style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    InkWell(
                      onTap: widget.onRecord,
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
            if (_mentionSuggestions.isNotEmpty)
              _MentionSuggestions(
                options: _mentionSuggestions,
                onSelected: _insertMention,
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ComposerButton(
                    tooltip: context.l10n.t('image'),
                    icon: Icons.image_outlined,
                    onTap: widget.onPickImages),
                _ComposerButton(
                    tooltip: context.l10n.t('file'),
                    icon: Icons.attach_file,
                    onTap: widget.onPickFiles),
                _ComposerButton(
                  tooltip: widget.recording
                      ? context.l10n.t('stopRecording')
                      : context.l10n.t('recordVoice'),
                  icon: widget.recording
                      ? Icons.stop_circle_outlined
                      : Icons.mic_none,
                  active: widget.recording,
                  onTap: widget.onRecord,
                ),
                if (widget.conversation.type == 'group')
                  _ComposerButton(
                    tooltip: context.l10n.t('poll'),
                    icon: Icons.how_to_vote_outlined,
                    onTap: widget.onCreatePoll,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => widget.onSend(),
                    decoration: InputDecoration(
                      hintText: context.l10n.t('typeMessage'),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: widget.onSend,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 36,
                    height: 36,
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
                        const Icon(Icons.send, color: Colors.white, size: 18),
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
          width: 32,
          height: 36,
          decoration: BoxDecoration(
            color: active ? const Color(0xfffee2e2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              color: active ? AppColors.danger : const Color(0xff596779),
              size: 19),
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
                    tooltip: context.l10n.t('changeAvatar'),
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
              decoration: InputDecoration(
                labelText: context.l10n.t('fullName'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: state.languageCode,
              decoration: InputDecoration(
                labelText: context.l10n.t('language'),
                prefixIcon: const Icon(Icons.language),
              ),
              items: const ['vi', 'en', 'zh']
                  .map(
                    (code) => DropdownMenuItem(
                      value: code,
                      child: Text(AppLocalizations.languageName(code)),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (code) {
                      if (code != null) {
                        context.read<AppState>().setLanguage(code);
                      }
                    },
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
              label: Text(context.l10n.t('saveProfile')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _openPasswordSheet,
              icon: const Icon(Icons.lock_reset_outlined),
              label: Text(context.l10n.t('changePassword')),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _saving ? null : _logout,
              icon: const Icon(Icons.logout),
              label: Text(context.l10n.t('logout')),
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
      setState(() => _error = context.l10n.t('passwordRequired'));
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _error = context.l10n.t('newPasswordMismatch'));
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
        SnackBar(content: Text(context.l10n.t('passwordChanged'))),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.t('changePasswordFailed'));
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
            Text(
              context.l10n.t('changePassword'),
              style: const TextStyle(
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
                labelText: context.l10n.t('currentPassword'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscureCurrent
                      ? context.l10n.t('showPassword')
                      : context.l10n.t('hidePassword'),
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
                labelText: context.l10n.t('newPassword'),
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscureNew
                      ? context.l10n.t('showPassword')
                      : context.l10n.t('hidePassword'),
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
                labelText: context.l10n.t('confirmNewPassword'),
                prefixIcon: const Icon(Icons.verified_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscureConfirm
                      ? context.l10n.t('showPassword')
                      : context.l10n.t('hidePassword'),
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
              label: Text(context.l10n.t('savePassword')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateGroupDraft {
  const _CreateGroupDraft({required this.name, required this.memberUserids});

  final String name;
  final List<String> memberUserids;
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.contacts,
    required this.currentUserid,
  });

  final List<ChatUser> contacts;
  final String currentUserid;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameController = TextEditingController();
  final _memberCodeController = TextEditingController();
  final _contactFilterController = TextEditingController();
  final Map<String, ChatUser> _selected = {};
  bool _lookingUp = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_refresh);
    _contactFilterController.addListener(_refresh);
  }

  @override
  void dispose() {
    _nameController.removeListener(_refresh);
    _contactFilterController.removeListener(_refresh);
    _nameController.dispose();
    _memberCodeController.dispose();
    _contactFilterController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _toggle(ChatUser user) {
    setState(() {
      final key = user.userid.toLowerCase();
      if (_selected.containsKey(key)) {
        _selected.remove(key);
      } else {
        _selected[key] = user;
      }
    });
  }

  Future<void> _addByCode() async {
    final query = _memberCodeController.text.trim();
    if (query.isEmpty || _lookingUp) return;
    setState(() => _lookingUp = true);
    try {
      final users = await context.read<AppState>().apiClient.searchUsers(query);
      final user = users
          .where((item) =>
              item.userid.toLowerCase() == query.toLowerCase() &&
              item.userid.toLowerCase() != widget.currentUserid.toLowerCase())
          .firstOrNull;
      if (!mounted) return;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('noUsersFound'))),
        );
        return;
      }
      setState(() {
        _selected[user.userid.toLowerCase()] = user;
        _memberCodeController.clear();
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('noUsersFound'))),
      );
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _selected.isEmpty) return;
    Navigator.of(context).pop(_CreateGroupDraft(
      name: name,
      memberUserids: _selected.values.map((user) => user.userid).toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final filter = _contactFilterController.text.trim().toLowerCase();
    final contacts = widget.contacts.where((contact) {
      if (filter.isEmpty) return true;
      return contact.displayName.toLowerCase().contains(filter) ||
          contact.fullname.toLowerCase().contains(filter) ||
          contact.userid.toLowerCase().contains(filter);
    }).toList()
      ..sort((first, second) => first.displayName
          .toLowerCase()
          .compareTo(second.displayName.toLowerCase()));
    final canCreate =
        _nameController.text.trim().isNotEmpty && _selected.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.82,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.t('createGroup'),
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: context.l10n.t('groupName'),
                  hintText: context.l10n.t('groupNamePlaceholder'),
                  prefixIcon: const Icon(Icons.groups_outlined),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memberCodeController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addByCode(),
                      decoration: InputDecoration(
                        hintText: context.l10n.t('memberCodePlaceholder'),
                        prefixIcon: const Icon(Icons.badge_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: context.l10n.t('addMemberByCode'),
                    onPressed: _lookingUp ? null : _addByCode,
                    icon: _lookingUp
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.person_add_alt_1_outlined),
                  ),
                ],
              ),
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _selected.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final user = _selected.values.elementAt(index);
                      return InputChip(
                        label: Text(user.displayName),
                        onDeleted: () => _toggle(user),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _contactFilterController,
                decoration: InputDecoration(
                  hintText: context.l10n.t('searchContacts'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: filter.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _contactFilterController.clear,
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: contacts.isEmpty
                    ? EmptyState(
                        icon: Icons.people_outline,
                        text: context.l10n.t('noMatchingContacts'),
                      )
                    : ListView.builder(
                        itemCount: contacts.length,
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          final selected = _selected
                              .containsKey(contact.userid.toLowerCase());
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selected,
                            onChanged: (_) => _toggle(contact),
                            secondary: YSAvatar(
                              label: contact.displayName,
                              size: 34,
                            ),
                            title: Text(
                              contact.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(contact.userid),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: canCreate ? _submit : null,
                icon: const Icon(Icons.group_add_outlined),
                label: Text(_selected.isEmpty
                    ? context.l10n.t('groupNeedsMember')
                    : context.l10n.t('createGroup')),
              ),
            ],
          ),
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
            Text(
              context.l10n.t('chooseUser'),
              style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (users.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: EmptyState(
                  icon: Icons.person_search_outlined,
                  text: context.l10n.t('noUsersFound'),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final display = user.displayName;
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

class _MentionSuggestions extends StatelessWidget {
  const _MentionSuggestions({
    required this.options,
    required this.onSelected,
  });

  final List<_MentionOption> options;
  final ValueChanged<_MentionOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 236),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0f172a).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: options.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final option = options[index];
          return InkWell(
            onTap: () => onSelected(option),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  option.isAll
                      ? Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.brandSoft,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.groups_outlined,
                              color: AppColors.brand, size: 19),
                        )
                      : YSAvatar(
                          label: option.label,
                          online: option.online,
                          size: 34,
                        ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          option.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    '@',
                    style: TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
            Text(
              context.l10n.t('forwardTo'),
              style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: EmptyState(
                    icon: Icons.forward_outlined,
                    text: context.l10n.t('noOtherChats')),
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
                      subtitle: Text(_lastMessagePreview(context, conversation),
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
      setState(() => _error = context.l10n.t('pollValidation'));
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
      if (mounted) setState(() => _error = context.l10n.t('pollCreateFailed'));
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
              Text(
                context.l10n.t('createPoll'),
                style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _questionController,
                decoration: InputDecoration(
                  labelText: context.l10n.t('question'),
                  prefixIcon: const Icon(Icons.help_outline),
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
                            labelText: context.l10n.optionNumber(entry.key + 1),
                            prefixIcon: const Icon(Icons.circle_outlined),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: context.l10n.t('delete'),
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
                  label: Text(context.l10n.t('addOption')),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowMultiple,
                onChanged: (value) => setState(() => _allowMultiple = value),
                title: Text(context.l10n.t('allowMultiple')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowCustomOptions,
                onChanged: (value) =>
                    setState(() => _allowCustomOptions = value),
                title: Text(context.l10n.t('allowCustomOption')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showVoters,
                onChanged: (value) => setState(() => _showVoters = value),
                title: Text(context.l10n.t('showVoters')),
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
                label: Text(context.l10n.t('createPoll')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _InfoPanelMode { overview, members, media, polls, files }

class _InfoPanel extends StatefulWidget {
  const _InfoPanel({required this.onDownload});

  final ValueChanged<ChatAttachment> onDownload;

  @override
  State<_InfoPanel> createState() => _InfoPanelState();
}

class _InfoPanelState extends State<_InfoPanel> {
  _InfoPanelMode _mode = _InfoPanelMode.overview;
  bool _loadingHistory = true;
  bool _historyRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_historyRequested) return;
    _historyRequested = true;
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      await context.read<AppState>().loadAllMessages();
    } catch (_) {
      // Keep the currently loaded previews when older history is unavailable.
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _openMode(_InfoPanelMode mode) => setState(() => _mode = mode);

  void _backToOverview() => setState(() => _mode = _InfoPanelMode.overview);

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
        .toList();
    final documents = state.messages
        .expand((message) => message.attachments)
        .where((attachment) =>
            !_isImageAttachment(attachment) &&
            !_isVideoAttachment(attachment) &&
            !_isAudioAttachment(attachment))
        .toList()
        .reversed
        .toList();
    final polls = state.messages
        .where((message) => message.type == 'poll' && message.poll != null)
        .toList()
        .reversed
        .toList();
    final isGroup = conversation.type == 'group';

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
              _InfoPanelHeader(
                title: title,
                subtitle: isGroup
                    ? context.l10n.memberCount(conversation.memberCount)
                    : context.l10n.t('directChat'),
                isGroup: isGroup,
                memberCount: conversation.memberCount,
                showBack: _mode != _InfoPanelMode.overview,
                onBack: _backToOverview,
              ),
              if (_loadingHistory) ...[
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 18),
              if (_mode == _InfoPanelMode.overview) ...[
                _InfoSummaryTile(
                  icon: conversation.settings.isMuted
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  title: context.l10n.t(conversation.settings.isMuted
                      ? 'unmuteConversation'
                      : 'muteConversation'),
                  subtitle: conversation.settings.isMuted
                      ? context.l10n.t('muted')
                      : context.l10n.t('notificationsEnabled'),
                  onTap: () => state.setConversationMuted(
                    conversation,
                    !conversation.settings.isMuted,
                  ),
                ),
                _InfoSummaryTile(
                  icon: conversation.settings.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.push_pin,
                  title: context.l10n.t(conversation.settings.isPinned
                      ? 'unpinConversation'
                      : 'pinConversation'),
                  subtitle: context.l10n.t('personalSetting'),
                  onTap: () => state.setConversationPinned(
                    conversation,
                    !conversation.settings.isPinned,
                  ),
                ),
                _InfoSummaryTile(
                  icon: conversation.settings.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  title: context.l10n.t(conversation.settings.isArchived
                      ? 'unarchiveConversation'
                      : 'archiveConversation'),
                  subtitle: context.l10n.t('personalSetting'),
                  onTap: () => state.setConversationArchived(
                    conversation,
                    !conversation.settings.isArchived,
                  ),
                ),
                if (isGroup)
                  _InfoSummaryTile(
                    icon: Icons.groups_outlined,
                    title: context.l10n.t('members'),
                    subtitle:
                        context.l10n.memberCount(conversation.memberCount),
                    onTap: () => _openMode(_InfoPanelMode.members),
                  ),
                _InfoPreviewSection(
                  title: context.l10n.t('media'),
                  count: media.length,
                  emptyText: context.l10n.t('noMedia'),
                  onViewAll: media.length > 3
                      ? () => _openMode(_InfoPanelMode.media)
                      : null,
                  child: _MediaPreviewGrid(
                    media: media.take(3).toList(),
                    absoluteUrl: state.apiClient.absoluteUrl,
                    onDownload: widget.onDownload,
                  ),
                ),
                if (isGroup)
                  _InfoPreviewSection(
                    title: context.l10n.t('poll'),
                    count: polls.length,
                    emptyText: context.l10n.t('noPolls'),
                    onViewAll: polls.length > 3
                        ? () => _openMode(_InfoPanelMode.polls)
                        : null,
                    child: _PollPreviewList(polls: polls.take(3).toList()),
                  ),
                _InfoPreviewSection(
                  title: context.l10n.t('sharedFiles'),
                  count: documents.length,
                  emptyText: context.l10n.t('noFiles'),
                  onViewAll: documents.length > 3
                      ? () => _openMode(_InfoPanelMode.files)
                      : null,
                  child: _DocumentPreviewList(
                    documents: documents.take(3).toList(),
                    onDownload: widget.onDownload,
                  ),
                ),
              ] else if (_mode == _InfoPanelMode.members) ...[
                ...conversation.members.map((member) {
                  final display = member.displayName;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: YSAvatar(
                      label: display,
                      imageUrl: member.avatar.isNotEmpty
                          ? state.apiClient.absoluteUrl(member.avatar)
                          : null,
                      size: 38,
                      online: member.isOnline,
                    ),
                    title: Text(display,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(member.nickname.trim().isEmpty
                        ? member.userid
                        : '${member.fullname} · ${member.userid}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _showChatUserProfile(context, member, conversation),
                  );
                }),
              ] else if (_mode == _InfoPanelMode.media) ...[
                _MediaPreviewGrid(
                  media: media,
                  absoluteUrl: state.apiClient.absoluteUrl,
                  onDownload: widget.onDownload,
                ),
              ] else if (_mode == _InfoPanelMode.polls) ...[
                _PollPreviewList(polls: polls),
              ] else if (_mode == _InfoPanelMode.files) ...[
                _DocumentPreviewList(
                  documents: documents,
                  onDownload: widget.onDownload,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

Future<void> _showChatUserProfile(
  BuildContext context,
  ChatUser member,
  ChatConversation conversation,
) async {
  final state = context.read<AppState>();
  final currentUserid = state.tokenStore.userid ?? '';
  final contact =
      state.contacts.where((item) => item.userid == member.userid).firstOrNull;
  final isGroup = conversation.type == 'group';
  final profileMember = isGroup ? member : (contact ?? member);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MemberProfileSheet(
      member: profileMember,
      isCurrentUser: member.userid == currentUserid,
      isContact: contact != null,
      canSetNickname: isGroup || contact != null,
      imageUrl: member.avatar.isNotEmpty
          ? state.apiClient.absoluteUrl(member.avatar)
          : null,
      onAddContact: () => state.addContact(member.userid),
      onOpenChat: () => state.openDirectConversation(member.userid),
      onSetNickname: (nickname) => isGroup
          ? state.updateConversationMemberNickname(
              conversation.id,
              member.userid,
              nickname,
            )
          : state.updateContactNickname(member.userid, nickname),
    ),
  );
}

Future<String?> _requestNickname(
  BuildContext context, {
  required ChatUser contact,
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.t('setNickname')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            contact.fullname.trim().isEmpty ? contact.userid : contact.fullname,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: context.l10n.t('nickname'),
              hintText: context.l10n.t('nicknamePlaceholder'),
              prefixIcon: const Icon(Icons.edit_outlined),
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text(context.l10n.t('save')),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class _MemberProfileSheet extends StatefulWidget {
  const _MemberProfileSheet({
    required this.member,
    required this.isCurrentUser,
    required this.isContact,
    required this.canSetNickname,
    required this.imageUrl,
    required this.onAddContact,
    required this.onOpenChat,
    required this.onSetNickname,
  });

  final ChatUser member;
  final bool isCurrentUser;
  final bool isContact;
  final bool canSetNickname;
  final String? imageUrl;
  final Future<void> Function() onAddContact;
  final Future<void> Function() onOpenChat;
  final Future<void> Function(String nickname) onSetNickname;

  @override
  State<_MemberProfileSheet> createState() => _MemberProfileSheetState();
}

class _MemberProfileSheetState extends State<_MemberProfileSheet> {
  late bool _isContact = widget.isContact;
  late bool _canSetNickname = widget.canSetNickname;
  late String _nickname = widget.member.nickname;
  bool _adding = false;
  bool _savingNickname = false;

  Future<void> _addContact() async {
    if (_adding || _isContact) return;
    setState(() => _adding = true);
    try {
      await widget.onAddContact();
      if (!mounted) return;
      setState(() {
        _isContact = true;
        _canSetNickname = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('contactAdded'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('addContactFailed'))),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _openPrivateChat() async {
    Navigator.of(context).pop();
    await widget.onOpenChat();
  }

  Future<void> _editNickname() async {
    if (_savingNickname || !_canSetNickname) return;
    final nickname = await _requestNickname(
      context,
      contact: widget.member,
      initialValue: _nickname,
    );
    if (nickname == null || !mounted) return;
    setState(() => _savingNickname = true);
    try {
      await widget.onSetNickname(nickname);
      if (!mounted) return;
      setState(() => _nickname = nickname);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n
              .t(nickname.isEmpty ? 'nicknameRemoved' : 'nicknameSaved')),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('nicknameFailed'))),
      );
    } finally {
      if (mounted) setState(() => _savingNickname = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullname = widget.member.fullname.trim().isEmpty
        ? widget.member.userid
        : widget.member.fullname.trim();
    final display = _nickname.trim().isEmpty ? fullname : _nickname.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 20),
            YSAvatar(
              label: display,
              imageUrl: widget.imageUrl,
              size: 84,
              online: widget.member.isOnline,
            ),
            const SizedBox(height: 12),
            Text(
              display,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            if (_nickname.trim().isNotEmpty)
              Text(
                fullname,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Text(
              widget.member.userid,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            if (!widget.isCurrentUser) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openPrivateChat,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(context.l10n.t('sendMessage')),
                ),
              ),
              if (!_isContact) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _adding ? null : _addContact,
                    icon: _adding
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.brand,
                            ),
                          )
                        : const Icon(Icons.person_add_alt_1_outlined),
                    label: Text(context.l10n.t('addContact')),
                  ),
                ),
              ],
            ],
            if (_canSetNickname) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _savingNickname ? null : _editNickname,
                  icon: _savingNickname
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined),
                  label: Text(context.l10n.t('setNickname')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoPanelHeader extends StatelessWidget {
  const _InfoPanelHeader({
    required this.title,
    required this.subtitle,
    required this.isGroup,
    required this.memberCount,
    required this.showBack,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final bool isGroup;
  final int memberCount;
  final bool showBack;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showBack)
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: context.l10n.t('back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
        Center(
          child: isGroup
              ? _GroupAvatar(count: memberCount)
              : YSAvatar(label: title, size: 74),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.muted, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _InfoSummaryTile extends StatelessWidget {
  const _InfoSummaryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.brand),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _InfoPreviewSection extends StatelessWidget {
  const _InfoPreviewSection({
    required this.title,
    required this.count,
    required this.emptyText,
    required this.child,
    this.onViewAll,
  });

  final String title;
  final int count;
  final String emptyText;
  final Widget child;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _InfoSectionTitle(title: '$title ($count)')),
              if (onViewAll != null)
                TextButton(
                  onPressed: onViewAll,
                  child: Text(context.l10n.t('viewAll')),
                ),
            ],
          ),
          if (count == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(emptyText,
                  style: const TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w700)),
            )
          else
            child,
        ],
      ),
    );
  }
}

class _MediaPreviewGrid extends StatelessWidget {
  const _MediaPreviewGrid({
    required this.media,
    required this.absoluteUrl,
    required this.onDownload,
  });

  final List<ChatAttachment> media;
  final String Function(String url) absoluteUrl;
  final ValueChanged<ChatAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
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
                absoluteUrl(file.fileUrl),
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
    );
  }
}

class _PollPreviewList extends StatelessWidget {
  const _PollPreviewList({required this.polls});

  final List<ChatMessage> polls;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: polls
          .map((message) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.how_to_vote_outlined,
                    color: AppColors.brand),
                title: Text(message.poll?.question ?? message.content,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle:
                    Text(context.l10n.voteCount(message.poll?.totalVotes ?? 0)),
              ))
          .toList(),
    );
  }
}

class _DocumentPreviewList extends StatelessWidget {
  const _DocumentPreviewList({
    required this.documents,
    required this.onDownload,
  });

  final List<ChatAttachment> documents;
  final ValueChanged<ChatAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: documents
          .map((file) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    Icon(_documentIcon(file), color: _documentAccent(file)),
                title: Text(
                  _attachmentDisplayName(file),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_formatBytes(file.fileSize)),
                trailing: IconButton(
                  tooltip: context.l10n.t('download'),
                  onPressed: () => onDownload(file),
                  icon: const Icon(Icons.download_outlined),
                ),
                onTap: () => onDownload(file),
              ))
          .toList(),
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
  const _GroupAvatar({required this.count, this.size = 44});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.line),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.groups_outlined,
              color: AppColors.brandDark, size: size * 0.5),
          Positioned(
            right: size * 0.08,
            bottom: size * 0.08,
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

const _contactLetterGroups = <String, String>{
  'A': 'AÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ',
  'B': 'B',
  'C': 'C',
  'D': 'DĐ',
  'E': 'EÈÉẺẼẸÊỀẾỂỄỆ',
  'F': 'F',
  'G': 'G',
  'H': 'H',
  'I': 'IÌÍỈĨỊ',
  'J': 'J',
  'K': 'K',
  'L': 'L',
  'M': 'M',
  'N': 'N',
  'O': 'OÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ',
  'P': 'P',
  'Q': 'Q',
  'R': 'R',
  'S': 'S',
  'T': 'T',
  'U': 'UÙÚỦŨỤƯỪỨỬỮỰ',
  'V': 'V',
  'W': 'W',
  'X': 'X',
  'Y': 'YỲÝỶỸỴ',
  'Z': 'Z',
};

int _compareDirectoryContacts(ChatUser first, ChatUser second) {
  final firstName = first.displayName;
  final secondName = second.displayName;
  final byName =
      _contactSortKey(firstName).compareTo(_contactSortKey(secondName));
  if (byName != 0) return byName;
  return first.userid.toLowerCase().compareTo(second.userid.toLowerCase());
}

String _contactSortKey(String value) {
  var normalized = value.trim().toUpperCase();
  for (final entry in _contactLetterGroups.entries) {
    for (final character in entry.value.characters) {
      normalized = normalized.replaceAll(character, entry.key);
    }
  }
  return normalized;
}

String _contactDirectoryLetter(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '#';
  final first = trimmed.characters.first.toUpperCase();
  for (final entry in _contactLetterGroups.entries) {
    if (entry.value.contains(first)) return entry.key;
  }
  return '#';
}

String _lastMessagePreview(
    BuildContext context, ChatConversation conversation) {
  final message = conversation.lastMessage;
  if (message == null) return '';
  if (message.type == 'call') {
    final callLog = ChatCallLog.tryParse(message.content);
    return context.l10n.t(
      callLog?.isMissed == true ? 'missedCall' : 'voiceCall',
    );
  }
  if (message.content.trim().isNotEmpty) return message.content.trim();
  final attachment = message.attachments.firstOrNull;
  if (attachment != null) return attachment.fileName;
  if (message.type == 'voice') return context.l10n.t('voicePreview');
  if (message.type == 'image') return context.l10n.t('imagePreview');
  return context.l10n.t('file');
}

String _messagePreview(BuildContext context, ChatMessage message) {
  if (message.type == 'call') {
    final callLog = ChatCallLog.tryParse(message.content);
    return context.l10n.t(
      callLog?.isMissed == true ? 'missedCall' : 'voiceCall',
    );
  }
  if (message.content.trim().isNotEmpty) return message.content.trim();
  if (message.attachments.any(_isImageAttachment)) {
    return context.l10n.t('imagePreview');
  }
  if (message.type == 'voice') return context.l10n.t('voicePreview');
  if (message.attachments.isNotEmpty) {
    return context.l10n.t('attachmentPreview');
  }
  return context.l10n.t('messagePreview');
}

String _attachmentDisplayName(ChatAttachment attachment) {
  if (attachment.relativePath.trim().isNotEmpty) {
    return attachment.relativePath.split('/').last;
  }
  if (attachment.fileName.trim().isNotEmpty) return attachment.fileName.trim();
  return 'Attachment';
}

IconData _documentIcon(ChatAttachment attachment) {
  final name = (attachment.fileName.isNotEmpty
          ? attachment.fileName
          : attachment.relativePath)
      .toLowerCase();
  final ext = name.contains('.') ? name.split('.').last : '';
  if (['doc', 'docx'].contains(ext)) return Icons.description_outlined;
  if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_outlined;
  if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_outlined;
  if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

Color _documentAccent(ChatAttachment attachment) {
  final name = (attachment.fileName.isNotEmpty
          ? attachment.fileName
          : attachment.relativePath)
      .toLowerCase();
  final ext = name.contains('.') ? name.split('.').last : '';
  if (['doc', 'docx'].contains(ext)) return const Color(0xff2563eb);
  if (['xls', 'xlsx', 'csv'].contains(ext)) return const Color(0xff16a34a);
  if (['ppt', 'pptx'].contains(ext)) return const Color(0xffea580c);
  if (ext == 'pdf') return const Color(0xffdc2626);
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return const Color(0xff7c3aed);
  }
  return AppColors.brand;
}

List<_MentionOption> _mentionOptions(ChatConversation conversation) {
  final options = <_MentionOption>[];
  final seen = <String>{};

  void addOption(_MentionOption option) {
    final key = option.label.toLowerCase();
    if (seen.contains(key)) return;
    seen.add(key);
    options.add(option);
  }

  if (conversation.type == 'group') {
    addOption(const _MentionOption(
      label: 'All',
      detail: '@All',
      searchText: 'all @all',
      isAll: true,
    ));
  }

  for (final member in conversation.members) {
    final label = member.displayName;
    if (label.isEmpty) continue;
    addOption(_MentionOption(
      label: label,
      detail: member.userid,
      online: member.isOnline,
      searchText:
          '$label ${member.fullname} ${member.nickname} ${member.userid}'
              .toLowerCase(),
    ));
  }

  return options;
}

class _MentionOption {
  const _MentionOption({
    required this.label,
    required this.detail,
    this.searchText = '',
    this.online = false,
    this.isAll = false,
  });

  final String label;
  final String detail;
  final String searchText;
  final bool online;
  final bool isAll;
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
