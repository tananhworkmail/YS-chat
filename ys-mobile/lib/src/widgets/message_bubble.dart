import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.resolveUrl,
  });

  final ChatMessage message;
  final bool mine;
  final String Function(String url) resolveUrl;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachments.firstOrNull;
    final createdAt = message.createdAt;
    final bubbleColor = mine ? AppColors.brand : Colors.white;
    final textColor = mine ? Colors.white : AppColors.ink;
    final metaColor =
        mine ? Colors.white.withValues(alpha: 0.72) : AppColors.muted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            YSAvatar(label: message.senderName, imageUrl: _avatarUrl, size: 30),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bubbleColor,
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
                      if (message.content.trim().isNotEmpty)
                        Text(
                          message.content,
                          style: TextStyle(
                              color: textColor, fontSize: 14.5, height: 1.35),
                        ),
                      if (attachment != null)
                        Padding(
                          padding: EdgeInsets.only(
                              top: message.content.trim().isNotEmpty ? 7 : 0),
                          child: _AttachmentPreview(
                            attachment: attachment,
                            resolveUrl: resolveUrl,
                            mine: mine,
                          ),
                        ),
                      if (createdAt != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            DateFormat('HH:mm').format(createdAt.toLocal()),
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
    );
  }

  String? get _avatarUrl {
    if (message.senderAvatar.isEmpty) return null;
    return resolveUrl(message.senderAvatar);
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({
    required this.attachment,
    required this.resolveUrl,
    required this.mine,
  });

  final ChatAttachment attachment;
  final String Function(String url) resolveUrl;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    if (attachment.mimeType.startsWith('image/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 260),
          child: Image.network(
            resolveUrl(attachment.fileUrl),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _FileRow(attachment: attachment, mine: mine),
          ),
        ),
      );
    }
    return _FileRow(attachment: attachment, mine: mine);
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.attachment, required this.mine});

  final ChatAttachment attachment;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final foreground = mine ? Colors.white : AppColors.ink;
    final sub = mine ? Colors.white.withValues(alpha: 0.72) : AppColors.muted;

    return Container(
      constraints: const BoxConstraints(minWidth: 190),
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
          Icon(_fileIcon, size: 22, color: foreground),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: foreground, fontWeight: FontWeight.w800),
                ),
                if (attachment.fileSize > 0)
                  Text(
                    _formatBytes(attachment.fileSize),
                    style: TextStyle(
                        color: sub, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _fileIcon {
    if (attachment.mimeType.startsWith('audio/')) return Icons.graphic_eq;
    if (attachment.mimeType.startsWith('video/')) return Icons.movie_outlined;
    if (attachment.mimeType.contains('pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
