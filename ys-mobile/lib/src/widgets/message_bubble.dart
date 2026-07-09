import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
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
    required this.mentionLabels,
    required this.onOpenReference,
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
  final List<String> mentionLabels;
  final ValueChanged<int> onOpenReference;

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
                constraints: const BoxConstraints(maxWidth: 330),
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
                    padding: const EdgeInsets.fromLTRB(9, 7, 9, 6),
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
                            reference: message.replyTo!,
                            mine: mine,
                            onTap: () => onOpenReference(message.replyTo!.id),
                          ),
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
                            content: message.content,
                            color: textColor,
                            mentionLabels: mentionLabels,
                          ),
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

class _MessageText extends StatefulWidget {
  const _MessageText({
    required this.content,
    required this.color,
    required this.mentionLabels,
  });

  final String content;
  final Color color;
  final List<String> mentionLabels;

  @override
  State<_MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<_MessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final parts = _messageParts(widget.content, widget.mentionLabels);
    if (parts.isEmpty) {
      return Text(widget.content,
          style: TextStyle(color: widget.color, fontSize: 14.2, height: 1.32));
    }

    final spans = <TextSpan>[];
    for (final part in parts) {
      if (part.isLink) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _openLink(part.text);
        _recognizers.add(recognizer);
        spans.add(TextSpan(
          text: part.text,
          recognizer: recognizer,
          style: const TextStyle(
            color: Color(0xff2563eb),
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.underline,
          ),
        ));
      } else if (part.isMention) {
        spans.add(TextSpan(
          text: part.text,
          style: const TextStyle(
              color: Color(0xff2563eb), fontWeight: FontWeight.w900),
        ));
      } else {
        spans.add(TextSpan(text: part.text));
      }
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(color: widget.color, fontSize: 14.2, height: 1.32),
        children: spans,
      ),
    );
  }

  Future<void> _openLink(String value) async {
    final hasProtocol =
        RegExp(r'^https?://', caseSensitive: false).hasMatch(value);
    final uri = Uri.tryParse(hasProtocol ? value : 'https://$value');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _ReferenceBox extends StatelessWidget {
  const _ReferenceBox({
    required this.reference,
    required this.mine,
    required this.onTap,
  });

  final ChatMessageReference reference;
  final bool mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              final url = resolveUrl(attachment.fileUrl);
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Material(
                  color: AppColors.brandSoftest,
                  child: InkWell(
                    onTap: () => _openImageViewer(context, url),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          url,
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
                  ),
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
      ..addListener(_refresh)
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
            GestureDetector(
              onTap: _controller.value.isInitialized
                  ? () => _openVideoViewer(context, widget.url)
                  : null,
              child: _controller.value.isInitialized
                  ? VideoPlayer(_controller)
                  : const ColoredBox(color: AppColors.brandSoftest),
            ),
            if (!_controller.value.isPlaying)
              Center(
                child: IconButton.filled(
                  onPressed: _controller.value.isInitialized
                      ? () => _controller.play()
                      : null,
                  icon: const Icon(Icons.play_arrow),
                ),
              ),
            Positioned(
              right: 5,
              top: 5,
              child: _FloatingDownloadButton(onTap: widget.onDownload),
            ),
            if (_controller.value.isInitialized)
              Positioned(
                left: 8,
                right: 8,
                bottom: 5,
                child: _VideoProgress(controller: _controller),
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
      constraints: const BoxConstraints(minWidth: 176, maxWidth: 250),
      padding: const EdgeInsets.fromLTRB(6, 6, 9, 6),
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
            visualDensity: VisualDensity.compact,
            onPressed: () => _playing ? _player.pause() : _player.play(),
            icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle,
                color: foreground),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _AudioProgress(player: _player, color: foreground),
          ),
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
    final muted = mine ? Colors.white.withValues(alpha: 0.74) : AppColors.muted;
    final panelColor =
        mine ? Colors.white.withValues(alpha: 0.12) : const Color(0xfff8fbff);
    final borderColor =
        mine ? Colors.white.withValues(alpha: 0.20) : AppColors.line;
    final name = attachment.relativePath.isNotEmpty
        ? attachment.relativePath.split('/').last
        : attachment.fileName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onDownload,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 190, maxWidth: 286),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(9, 8, 6, 8),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: mine
                        ? Colors.white.withValues(alpha: 0.13)
                        : AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      Icon(_fileIcon(attachment), size: 20, color: foreground),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name.isNotEmpty
                            ? name
                            : context.l10n.t('attachmentFile'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (attachment.fileSize > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatBytes(attachment.fileSize),
                          style: TextStyle(
                            color: muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: context.l10n.t('download'),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDownload,
                  icon: Icon(
                    Icons.file_open_outlined,
                    color: mine ? Colors.white : AppColors.brand,
                    size: 18,
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

class _AudioProgress extends StatelessWidget {
  const _AudioProgress({required this.player, required this.color});

  final AudioPlayer player;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, durationSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final max = duration.inMilliseconds <= 0
                ? 1.0
                : duration.inMilliseconds.toDouble();
            final value = position.inMilliseconds.clamp(0, max.toInt());
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: color,
                    inactiveTrackColor: color.withValues(alpha: 0.24),
                    thumbColor: color,
                  ),
                  child: Slider(
                    min: 0,
                    max: max,
                    value: value.toDouble(),
                    onChanged: duration.inMilliseconds <= 0
                        ? null
                        : (next) =>
                            player.seek(Duration(milliseconds: next.round())),
                  ),
                ),
                Text(
                  '${_formatDuration(position)} / ${duration == Duration.zero ? '--:--' : _formatDuration(duration)}',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _VideoProgress extends StatelessWidget {
  const _VideoProgress({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = controller.value;
        final duration = value.duration;
        final position = value.position;
        final max = duration.inMilliseconds <= 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final current = position.inMilliseconds.clamp(0, max.toInt());
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: value.isInitialized
                    ? () =>
                        value.isPlaying ? controller.pause() : controller.play()
                    : null,
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(
                    value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              Text(
                _formatDuration(position),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 9),
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 0,
                    max: max,
                    value: current.toDouble(),
                    onChanged: duration.inMilliseconds <= 0
                        ? null
                        : (next) => controller
                            .seekTo(Duration(milliseconds: next.round())),
                  ),
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FullscreenVideo extends StatefulWidget {
  const _FullscreenVideo({required this.url});

  final String url;

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(_refresh)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton.filled(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            if (!_controller.value.isPlaying)
              Center(
                child: IconButton.filled(
                  onPressed: _controller.value.isInitialized
                      ? () => _controller.play()
                      : null,
                  icon: const Icon(Icons.play_arrow),
                ),
              ),
            if (_controller.value.isInitialized)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: _VideoProgress(controller: _controller),
              ),
          ],
        ),
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

Future<void> _openImageViewer(BuildContext context, String url) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 42,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _openVideoViewer(BuildContext context, String url) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (context) => _FullscreenVideo(url: url)),
  );
}

List<_TextPart> _messageParts(String content, List<String> mentionLabels) {
  if (content.isEmpty) return const [];
  final labels = mentionLabels
      .map((label) => label.trim())
      .where((label) => label.length > 1)
      .toSet()
      .toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final lowerLabels =
      labels.map((label) => (text: label, lower: label.toLowerCase())).toList();
  final linkMatches = _linkPattern
      .allMatches(content)
      .map((match) => _TextRange(match.start, match.end, isLink: true))
      .toList();
  final ranges = <_TextRange>[...linkMatches];
  final lowerContent = content.toLowerCase();
  var cursor = 0;
  while (cursor < content.length && lowerLabels.isNotEmpty) {
    ({String text, String lower})? nextLabel;
    var nextIndex = -1;
    for (final label in lowerLabels) {
      final index = lowerContent.indexOf(label.lower, cursor);
      if (index < 0 || _overlaps(index, index + label.text.length, ranges)) {
        continue;
      }
      if (nextIndex < 0 ||
          index < nextIndex ||
          (index == nextIndex && label.text.length > nextLabel!.text.length)) {
        nextIndex = index;
        nextLabel = label;
      }
    }
    if (nextLabel == null) break;
    final end = nextIndex + nextLabel.text.length;
    if (_hasMentionBoundary(content, nextIndex, end)) {
      ranges.add(_TextRange(nextIndex, end, isMention: true));
    }
    cursor = end;
  }
  if (ranges.isEmpty) return [_TextPart(content)];
  ranges.sort((a, b) => a.start.compareTo(b.start));

  final parts = <_TextPart>[];
  var index = 0;
  for (final range in ranges) {
    if (range.start < index) continue;
    if (range.start > index) {
      parts.add(_TextPart(content.substring(index, range.start)));
    }
    parts.add(_TextPart(
      content.substring(range.start, range.end),
      isLink: range.isLink,
      isMention: range.isMention,
    ));
    index = range.end;
  }
  if (index < content.length) parts.add(_TextPart(content.substring(index)));
  return parts;
}

bool _hasMentionBoundary(String content, int start, int end) {
  final before = start == 0 ? '' : content[start - 1];
  final after = end >= content.length ? '' : content[end];
  final beforeOk = before.isEmpty || RegExp(r'\s|[([{]').hasMatch(before);
  final afterOk = after.isEmpty || RegExp(r'\s|[.,!?;:)\]}]').hasMatch(after);
  return beforeOk && afterOk;
}

bool _overlaps(int start, int end, List<_TextRange> ranges) {
  return ranges.any((range) => start < range.end && end > range.start);
}

final _linkPattern = RegExp(
  r'((https?:\/\/)?([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(:\d+)?(\/[^\s]*)?)',
  caseSensitive: false,
);

class _TextRange {
  const _TextRange(this.start, this.end,
      {this.isLink = false, this.isMention = false});

  final int start;
  final int end;
  final bool isLink;
  final bool isMention;
}

class _TextPart {
  const _TextPart(this.text, {this.isLink = false, this.isMention = false});

  final String text;
  final bool isLink;
  final bool isMention;
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

String _formatDuration(Duration duration) {
  final total = duration.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _referencePreview(BuildContext context, ChatMessageReference reference) {
  if (reference.content.trim().isNotEmpty) return reference.content.trim();
  if (reference.type == 'voice') return context.l10n.t('voicePreview');
  if (reference.type == 'file') return context.l10n.t('attachmentPreview');
  if (reference.type == 'image') return context.l10n.t('imagePreview');
  if (reference.type == 'poll') return context.l10n.t('poll');
  return context.l10n.t('messagePreview');
}
