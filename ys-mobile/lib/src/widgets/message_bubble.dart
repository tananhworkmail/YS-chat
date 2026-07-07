import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.resolveUrl,
    required this.onReply,
    required this.onForward,
    required this.onDownload,
    required this.onVotePoll,
    required this.onClosePoll,
  });

  final ChatMessage message;
  final bool mine;
  final String Function(String url) resolveUrl;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onForward;
  final ValueChanged<ChatAttachment> onDownload;
  final void Function(
      ChatMessage message, List<int> optionIds, String customOption) onVotePoll;
  final ValueChanged<ChatMessage> onClosePoll;

  @override
  Widget build(BuildContext context) {
    if (message.type == 'system') {
      return _SystemNotice(message: message);
    }
    if (message.type == 'poll' && message.poll != null) {
      return _PollBubble(
        message: message,
        mine: mine,
        onVotePoll: onVotePoll,
        onClosePoll: onClosePoll,
      );
    }

    final images = message.attachments.where(_isImage).toList();
    final videos = message.attachments.where(_isVideo).toList();
    final voices = message.attachments.where(_isVoice).toList();
    final files = message.attachments
        .where((item) => !_isImage(item) && !_isVideo(item) && !_isVoice(item))
        .toList();
    final textColor = mine ? Colors.white : AppColors.ink;
    final metaColor =
        mine ? Colors.white.withValues(alpha: 0.72) : AppColors.muted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -240) onReply(message);
        },
        onLongPress: () => _showOptions(context),
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              YSAvatar(
                  label: message.senderName, imageUrl: _avatarUrl, size: 30),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: mine ? AppColors.brand : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(8),
                      topRight: const Radius.circular(8),
                      bottomLeft: Radius.circular(mine ? 8 : 3),
                      bottomRight: Radius.circular(mine ? 3 : 8),
                    ),
                    border: mine ? null : Border.all(color: AppColors.line),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xff0f172a)
                            .withValues(alpha: mine ? 0.10 : 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!mine)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              message.senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.brandDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        if (message.replyTo != null)
                          _ReferenceBox(
                              reference: message.replyTo!, mine: mine),
                        if (message.forwardedFrom != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Text(
                              context.l10n.forwardedFrom(
                                  message.forwardedFrom!.senderName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: metaColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (message.content.trim().isNotEmpty)
                          _MessageText(
                              content: message.content, color: textColor),
                        if (images.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(
                                top: message.content.trim().isNotEmpty ? 7 : 0),
                            child: _ImageGrid(
                              attachments: images,
                              resolveUrl: resolveUrl,
                              onDownload: onDownload,
                            ),
                          ),
                        if (videos.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: _VideoList(
                              attachments: videos,
                              resolveUrl: resolveUrl,
                              onDownload: onDownload,
                            ),
                          ),
                        if (voices.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: _VoiceList(
                              attachments: voices,
                              mine: mine,
                              resolveUrl: resolveUrl,
                            ),
                          ),
                        if (files.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: _FileList(
                              attachments: files,
                              mine: mine,
                              onDownload: onDownload,
                            ),
                          ),
                        if (message.createdAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              DateFormat('HH:mm')
                                  .format(message.createdAt!.toLocal()),
                              style: TextStyle(
                                  color: metaColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    final downloadable =
        message.attachments.where((item) => !_isVoice(item)).firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text(context.l10n.t('reply')),
                onTap: () {
                  Navigator.of(context).pop();
                  onReply(message);
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: Text(context.l10n.t('forward')),
                onTap: () {
                  Navigator.of(context).pop();
                  onForward(message);
                },
              ),
              if (message.content.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: Text(context.l10n.t('copy')),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    Navigator.of(context).pop();
                  },
                ),
              if (downloadable != null)
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: Text(context.l10n.t('download')),
                  onTap: () {
                    Navigator.of(context).pop();
                    onDownload(downloadable);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? get _avatarUrl {
    if (message.senderAvatar.isEmpty) return null;
    return resolveUrl(message.senderAvatar);
  }
}

class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xffedf2f7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PollBubble extends StatefulWidget {
  const _PollBubble({
    required this.message,
    required this.mine,
    required this.onVotePoll,
    required this.onClosePoll,
  });

  final ChatMessage message;
  final bool mine;
  final void Function(
      ChatMessage message, List<int> optionIds, String customOption) onVotePoll;
  final ValueChanged<ChatMessage> onClosePoll;

  @override
  State<_PollBubble> createState() => _PollBubbleState();
}

class _PollBubbleState extends State<_PollBubble> {
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final poll = message.poll!;
    final totalVotes =
        poll.options.fold<int>(0, (sum, option) => sum + option.voteCount);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.how_to_vote_outlined,
                        color: AppColors.brand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        poll.question.isNotEmpty
                            ? poll.question
                            : message.content,
                        style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (poll.isClosed)
                      Text(context.l10n.t('closed'),
                          style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 10),
                ...poll.options.map((option) {
                  final selected = poll.myOptionIds.contains(option.id);
                  final percent =
                      totalVotes == 0 ? 0.0 : option.voteCount / totalVotes;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: poll.isClosed
                          ? null
                          : () {
                              final selectedIds =
                                  Set<int>.from(poll.myOptionIds);
                              if (poll.allowMultiple) {
                                selected
                                    ? selectedIds.remove(option.id)
                                    : selectedIds.add(option.id);
                              } else {
                                selectedIds
                                  ..clear()
                                  ..add(option.id);
                              }
                              widget.onVotePoll(
                                  message, selectedIds.toList(), '');
                            },
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color:
                              selected ? AppColors.brandSoft : AppColors.canvas,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color:
                                  selected ? AppColors.brand : AppColors.line),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  poll.allowMultiple
                                      ? (selected
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank)
                                      : (selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_unchecked),
                                  color: selected
                                      ? AppColors.brand
                                      : AppColors.muted,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    option.text,
                                    style: const TextStyle(
                                        color: AppColors.ink,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text('${option.voteCount}',
                                    style: const TextStyle(
                                        color: AppColors.muted,
                                        fontWeight: FontWeight.w800)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: percent,
                              minHeight: 4,
                              backgroundColor: Colors.white,
                              color: AppColors.brand,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${context.l10n.voteCount(poll.totalVotes)} · ${poll.allowMultiple ? context.l10n.t('chooseMultiple') : context.l10n.t('chooseOne')}',
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (widget.mine && !poll.isClosed)
                      TextButton(
                        onPressed: () => widget.onClosePoll(message),
                        child: Text(context.l10n.t('close')),
                      ),
                  ],
                ),
                if (poll.allowCustomOptions && !poll.isClosed) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customController,
                          decoration: InputDecoration(
                            hintText: context.l10n.t('addCustomOption'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: context.l10n.t('sendOption'),
                        onPressed: () {
                          final custom = _customController.text.trim();
                          if (custom.isEmpty) return;
                          final optionIds = poll.allowMultiple
                              ? List<int>.from(poll.myOptionIds)
                              : <int>[];
                          widget.onVotePoll(message, optionIds, custom);
                          _customController.clear();
                        },
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  const _MessageText({required this.content, required this.color});

  final String content;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final parts = RegExp(r'(@[^\s@]+)').allMatches(content).toList();
    if (parts.isEmpty) {
      return Text(content,
          style: TextStyle(color: color, fontSize: 14.5, height: 1.35));
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in parts) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, match.start)));
      }
      spans.add(TextSpan(
        text: content.substring(match.start, match.end),
        style: const TextStyle(
            color: Color(0xff2563eb), fontWeight: FontWeight.w900),
      ));
      cursor = match.end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: color, fontSize: 14.5, height: 1.35),
        children: spans,
      ),
    );
  }
}

class _ReferenceBox extends StatelessWidget {
  const _ReferenceBox({required this.reference, required this.mine});

  final ChatMessageReference reference;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.brandSoftest,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(
                color: mine ? Colors.white : AppColors.brand, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(reference.senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: mine ? Colors.white : AppColors.brandDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(_referencePreview(context, reference),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.78)
                      : AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid(
      {required this.attachments,
      required this.resolveUrl,
      required this.onDownload});

  final List<ChatAttachment> attachments;
  final String Function(String url) resolveUrl;
  final ValueChanged<ChatAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    final columns = attachments.length == 1 ? 1 : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final gridWidth = attachments.length == 1
            ? maxWidth
            : maxWidth.clamp(0.0, 228.0).toDouble();
        return SizedBox(
          width: gridWidth,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: attachments.length == 1 ? 1.35 : 1,
            ),
            itemCount: attachments.length,
            itemBuilder: (context, index) {
              final attachment = attachments[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      resolveUrl(attachment.fileUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const ColoredBox(
                        color: AppColors.brandSoftest,
                        child: Icon(Icons.broken_image_outlined,
                            color: AppColors.muted),
                      ),
                    ),
                    Positioned(
                      right: 5,
                      top: 5,
                      child: _FloatingDownloadButton(
                          onTap: () => onDownload(attachment)),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _VideoList extends StatelessWidget {
  const _VideoList(
      {required this.attachments,
      required this.resolveUrl,
      required this.onDownload});

  final List<ChatAttachment> attachments;
  final String Function(String url) resolveUrl;
  final ValueChanged<ChatAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: attachments
          .map((attachment) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _VideoPreview(
                  url: resolveUrl(attachment.fileUrl),
                  onDownload: () => onDownload(attachment),
                ),
              ))
          .toList(),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.url, required this.onDownload});

  final String url;
  final VoidCallback onDownload;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: _controller.value.isInitialized
            ? _controller.value.aspectRatio
            : 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller.value.isInitialized)
              VideoPlayer(_controller)
            else
              const ColoredBox(color: AppColors.brandSoftest),
            Center(
              child: IconButton.filled(
                onPressed: _controller.value.isInitialized
                    ? () {
                        setState(() {
                          _controller.value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        });
                      }
                    : null,
                icon: Icon(_controller.value.isPlaying
                    ? Icons.pause
                    : Icons.play_arrow),
              ),
            ),
            Positioned(
              right: 5,
              top: 5,
              child: _FloatingDownloadButton(onTap: widget.onDownload),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceList extends StatelessWidget {
  const _VoiceList(
      {required this.attachments,
      required this.mine,
      required this.resolveUrl});

  final List<ChatAttachment> attachments;
  final bool mine;
  final String Function(String url) resolveUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: attachments
          .map((attachment) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _VoicePlayer(
                    url: resolveUrl(attachment.fileUrl), mine: mine),
              ))
          .toList(),
    );
  }
}

class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({required this.url, required this.mine});

  final String url;
  final bool mine;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  late final AudioPlayer _player;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.setUrl(widget.url);
    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.mine ? Colors.white : AppColors.ink;
    return Container(
      constraints: const BoxConstraints(minWidth: 190),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: widget.mine
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.brandSoftest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: widget.mine
                ? Colors.white.withValues(alpha: 0.18)
                : AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => _playing ? _player.pause() : _player.play(),
            icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle,
                color: foreground),
          ),
          const SizedBox(width: 4),
          Text(context.l10n.t('voiceMessage'),
              style: TextStyle(color: foreground, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList(
      {required this.attachments,
      required this.mine,
      required this.onDownload});

  final List<ChatAttachment> attachments;
  final bool mine;
  final ValueChanged<ChatAttachment> onDownload;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: attachments
          .map((attachment) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _FileRow(
                  attachment: attachment,
                  mine: mine,
                  onDownload: () => onDownload(attachment),
                ),
              ))
          .toList(),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow(
      {required this.attachment, required this.mine, required this.onDownload});

  final ChatAttachment attachment;
  final bool mine;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final foreground = mine ? Colors.white : AppColors.ink;
    final sub = mine ? Colors.white.withValues(alpha: 0.72) : AppColors.muted;
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.brandSoftest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color:
                mine ? Colors.white.withValues(alpha: 0.18) : AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_fileIcon(attachment), size: 24, color: foreground),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.relativePath.isNotEmpty
                      ? attachment.relativePath
                      : attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: foreground, fontWeight: FontWeight.w800),
                ),
                if (attachment.fileSize > 0)
                  Text(_formatBytes(attachment.fileSize),
                      style: TextStyle(
                          color: sub,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.t('download'),
            onPressed: onDownload,
            icon: Icon(Icons.download_outlined,
                color: mine ? Colors.white : AppColors.brand, size: 18),
          ),
        ],
      ),
    );
  }
}

class _FloatingDownloadButton extends StatelessWidget {
  const _FloatingDownloadButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const SizedBox(
          width: 30,
          height: 30,
          child: Icon(Icons.download_outlined, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

bool _isImage(ChatAttachment attachment) {
  final mime = attachment.mimeType.toLowerCase();
  final ext = _fileExt(attachment);
  return mime.startsWith('image/') ||
      ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext);
}

bool _isVideo(ChatAttachment attachment) {
  final mime = attachment.mimeType.toLowerCase();
  final ext = _fileExt(attachment);
  return mime.startsWith('video/') ||
      ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
}

bool _isVoice(ChatAttachment attachment) {
  final mime = attachment.mimeType.toLowerCase();
  final ext = _fileExt(attachment);
  return mime.startsWith('audio/') ||
      ['mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'webm'].contains(ext);
}

String _fileExt(ChatAttachment attachment) {
  final name = (attachment.fileName.isNotEmpty
          ? attachment.fileName
          : attachment.relativePath)
      .toLowerCase();
  final pieces = name.split('.');
  return pieces.length > 1 ? pieces.last : '';
}

IconData _fileIcon(ChatAttachment attachment) {
  final ext = _fileExt(attachment);
  if (['doc', 'docx'].contains(ext)) return Icons.description_outlined;
  if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_outlined;
  if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_outlined;
  if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
  if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _referencePreview(BuildContext context, ChatMessageReference reference) {
  if (reference.content.trim().isNotEmpty) return reference.content.trim();
  if (reference.type == 'voice') return context.l10n.t('voicePreview');
  if (reference.type == 'file') return context.l10n.t('attachmentPreview');
  if (reference.type == 'image') return context.l10n.t('imagePreview');
  if (reference.type == 'poll') return context.l10n.t('poll');
  return context.l10n.t('messagePreview');
}
