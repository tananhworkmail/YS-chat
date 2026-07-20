import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ys_mobile/src/models/models.dart';
import 'package:ys_mobile/src/services/token_store.dart';

void main() {
  group('production chat models', () {
    test('parses unified realtime envelope and payload message', () {
      final event = RealtimeEvent.fromJson({
        'eventId': 'evt-1',
        'type': 'message.created',
        'version': 1,
        'serverTimestamp': '2026-07-15T01:02:03Z',
        'conversationId': 7,
        'messageId': 42,
        'payload': {
          'message': {
            'id': 42,
            'conversationId': 7,
            'clientMessageId': 'f4140c51-c48f-4ec5-84cb-218f50f071f9',
            'serverSequence': 99,
            'senderUserid': 'u1',
            'senderName': 'User One',
            'type': 'text',
            'content': 'hello',
            'createdAt': '2026-07-15T01:02:03Z',
          },
        },
      });

      expect(event.eventId, 'evt-1');
      expect(event.conversationId, 7);
      expect(event.messageId, 42);
      expect(event.message?.clientMessageId,
          'f4140c51-c48f-4ec5-84cb-218f50f071f9');
      expect(event.message?.serverSequence, 99);
    });

    test('keeps parsing legacy top-level message events', () {
      final event = RealtimeEvent.fromJson({
        'type': 'chat.message.created',
        'conversationId': 3,
        'message': {
          'id': 8,
          'conversationId': 3,
          'senderUserid': 'legacy',
          'senderName': 'Legacy User',
          'type': 'text',
          'content': 'compatible',
        },
      });

      expect(event.messageId, 8);
      expect(event.message?.content, 'compatible');
      expect(event.version, 1);
    });

    test('parses video call signaling and call history kind', () {
      final event = RealtimeEvent.fromJson({
        'type': 'call.invite',
        'payload': {'callId': 'video-1', 'mediaType': 'video'},
      });
      final log = ChatCallLog.tryParse(
          '{"kind":"video","status":"completed","duration":12}');

      expect(event.mediaType, 'video');
      expect(log?.kind, 'video');
      expect(log?.duration, 12);
    });

    test('derives group delivery state from receipt summary', () {
      final message = ChatMessage.fromJson({
        'id': 20,
        'conversationId': 4,
        'senderUserid': 'me',
        'senderName': 'Me',
        'type': 'text',
        'content': 'group',
        'receiptSummary': {
          'totalRecipients': 3,
          'deliveredRecipients': 3,
          'readRecipients': 2,
        },
        'receipts': [
          {
            'userid': 'u2',
            'deliveredAt': '2026-07-15T01:03:00Z',
            'readAt': '2026-07-15T01:04:00Z',
          },
          {
            'userid': 'u3',
            'deliveredAt': '2026-07-15T01:03:00Z',
            'readAt': '2026-07-15T01:04:00Z',
          },
          {
            'userid': 'u4',
            'deliveredAt': '2026-07-15T01:03:00Z',
          },
        ],
      });

      expect(message.totalRecipients, 3);
      expect(message.deliveredCount, 3);
      expect(message.readCount, 2);
      expect(message.state, MessageState.delivered);
      expect(
          message.readReceipts
              .singleWhere((item) => item.userid == 'u2')
              .readAt,
          isNotNull);
    });

    test('keeps reaction identities for group reaction details', () {
      final reaction = ChatReaction.fromJson({
        'emoji': '👍',
        'count': 2,
        'users': [
          {'userid': 'u2', 'fullname': 'User Two', 'avatar': '/u2.png'},
          {'userid': 'u3', 'fullname': 'User Three'},
        ],
      });

      expect(reaction.userids, const ['u2', 'u3']);
      expect(reaction.users.map((user) => user.displayName),
          const ['User Two', 'User Three']);

      final legacy = ChatReaction.fromJson({
        'emoji': '❤️',
        'users': ['legacy-user'],
      });
      expect(legacy.userids, const ['legacy-user']);
    });

    test('parses message edit history returned to conversation members', () {
      final entry = ChatMessageEditHistoryEntry.fromJson({
        'auditId': 9,
        'messageId': 20,
        'previousVersion': 1,
        'version': 2,
        'previousContent': 'before',
        'content': 'after',
        'editorUserid': 'u1',
        'editorName': 'User One',
        'editedAt': '2026-07-15T01:05:00Z',
      });

      expect(entry.previousContent, 'before');
      expect(entry.content, 'after');
      expect(entry.editorName, 'User One');
      expect(entry.editedAt, DateTime.utc(2026, 7, 15, 1, 5));
    });

    test('parses server unread and flattened per-user settings', () {
      final conversation = ChatConversation.fromJson({
        'id': 11,
        'type': 'direct',
        'unreadCount': 6,
        'lastReadMessageId': 100,
        'muteUntil': '2099-01-01T00:00:00Z',
        'pinnedAt': '2026-07-15T00:00:00Z',
        'archivedAt': null,
      });

      expect(conversation.unreadCount, 6);
      expect(conversation.lastReadMessageId, 100);
      expect(conversation.settings.isMuted, isTrue);
      expect(conversation.settings.isPinned, isTrue);
      expect(conversation.settings.isArchived, isFalse);
    });

    test('parses shared pinned message state and conversation notice', () {
      final state = PinnedMessageState.fromJson({
        'conversationId': 11,
        'pinnedMessage': {
          'id': 101,
          'senderUserid': 'u1',
          'senderName': 'User One',
          'type': 'text',
          'content': 'important',
        },
        'pinnedMessages': [
          {
            'id': 101,
            'senderUserid': 'u1',
            'senderName': 'User One',
            'type': 'text',
            'content': 'important',
          },
          {
            'id': 99,
            'senderUserid': 'u2',
            'senderName': 'User Two',
            'type': 'text',
            'content': 'older pin',
          },
        ],
        'pinnedCount': 2,
        'systemMessage': {
          'id': 102,
          'conversationId': 11,
          'senderUserid': 'u2',
          'senderName': 'User Two',
          'type': 'system',
          'content': 'User Two đã ghim một tin nhắn',
        },
        'actorUserid': 'u2',
        'actorName': 'User Two',
      });
      final conversation = ChatConversation.fromJson({
        'id': 11,
        'pinnedMessage': state.pinnedMessage?.toJson(),
        'pinnedMessages':
            state.pinnedMessages.map((message) => message.toJson()).toList(),
        'pinnedCount': state.pinnedCount,
      });

      expect(state.pinnedMessage?.id, 101);
      expect(state.pinnedMessages.map((message) => message.id), [101, 99]);
      expect(state.pinnedCount, 2);
      expect(state.systemMessage?.type, 'system');
      expect(state.systemMessage?.content, contains('đã ghim'));
      expect(conversation.pinnedMessage?.id, 101);
      expect(conversation.pinnedMessages, hasLength(2));
      expect(conversation.pinnedCount, 2);
    });

    test('parses scheduled and fired reminders', () {
      final scheduled = ChatReminder.fromJson({
        'id': 7,
        'conversationId': 11,
        'creatorUserid': 'u1',
        'creatorName': 'User One',
        'title': 'Project review',
        'remindAt': '2026-07-20T09:30:00Z',
        'repeatType': 'weekly',
        'status': 'scheduled',
        'createdAt': '2026-07-20T08:00:00Z',
      });
      final fired = ChatReminder.fromJson({
        'id': 7,
        'conversation_id': 11,
        'title': 'Project review',
        'remind_at': '2026-07-20T09:30:00Z',
        'repeat_type': 'daily',
        'status': 'fired',
        'fired_at': '2026-07-20T09:30:01Z',
      });

      expect(scheduled.conversationId, 11);
      expect(scheduled.creatorUserid, 'u1');
      expect(scheduled.repeatType, 'weekly');
      expect(scheduled.remindAt.toUtc(), DateTime.utc(2026, 7, 20, 9, 30));
      expect(fired.repeatType, 'daily');
      expect(fired.status, 'fired');
      expect(fired.firedAt?.toUtc(), DateTime.utc(2026, 7, 20, 9, 30, 1));
    });

    test('recalled messages never expose attachments to the UI', () {
      final message = ChatMessage.fromJson({
        'id': 50,
        'conversationId': 5,
        'senderUserid': 'u1',
        'senderName': 'User One',
        'type': 'file',
        'deletedAt': '2026-07-15T01:05:00Z',
        'deletedBy': 'u1',
        'attachments': [
          {
            'id': 1,
            'messageId': 50,
            'fileName': 'secret.pdf',
            'fileUrl': '/uploads/secret.pdf',
          },
        ],
      });

      expect(message.isDeleted, isTrue);
      expect(message.attachments, hasLength(1));
      expect(message.visibleAttachments, isEmpty);
    });

    test('outbox snapshot survives a process restart with the same UUID', () {
      final snapshot = ChatRuntimeSnapshot(
        pendingMessages: [
          ChatMessage(
            id: -4,
            conversationId: 12,
            clientMessageId: '4ebd5065-99fb-43aa-aea5-b9ee3e7cf25c',
            senderUserid: 'me',
            senderName: 'Current User',
            type: 'file',
            content: 'quarterly report',
            forwardedFrom: const ChatMessageReference(
              id: 88,
              senderUserid: 'source',
              senderName: 'Source User',
              type: 'file',
              content: 'quarterly report',
            ),
            attachments: const [
              ChatAttachment(
                id: 91,
                messageId: 0,
                fileName: 'report.pdf',
                fileUrl: '/uploads/report.pdf',
                mimeType: 'application/pdf',
                fileSize: 1024,
              ),
            ],
            createdAt: DateTime.utc(2026, 7, 15, 2, 3, 4),
            state: MessageState.sending,
          ),
        ],
        lastSeenMessageIds: const {12: 120, 13: 205, 14: 0},
        lastSeenSequences: const {12: 9001, 13: 9010, 14: 0},
      );

      final restored = ChatRuntimeSnapshot.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map,
        ),
      );

      expect(restored.pendingMessages, hasLength(1));
      final pending = restored.pendingMessages.single;
      expect(pending.id, -4);
      expect(pending.clientMessageId, '4ebd5065-99fb-43aa-aea5-b9ee3e7cf25c');
      expect(pending.conversationId, 12);
      expect(pending.forwardedFrom?.id, 88);
      expect(pending.attachments.single.fileUrl, '/uploads/report.pdf');
      expect(pending.attachments.single.mimeType, 'application/pdf');
      expect(restored.lastSeenMessageIds, const {12: 120, 13: 205, 14: 0});
      expect(restored.lastSeenSequences, const {12: 9001, 13: 9010, 14: 0});
    });

    test('outbox snapshot never persists acknowledged server messages', () {
      final snapshot = ChatRuntimeSnapshot(
        pendingMessages: const [
          ChatMessage(
            id: 45,
            conversationId: 12,
            clientMessageId: '5b0b304e-47bf-491a-b2bf-b90f62db4412',
            senderUserid: 'me',
            senderName: 'Current User',
            type: 'text',
            content: 'already sent',
          ),
        ],
      );

      final restored = ChatRuntimeSnapshot.fromJson(snapshot.toJson());

      expect(restored.pendingMessages, isEmpty);
    });

    test('client UUID identity is scoped by sender', () {
      const first = ChatMessage(
        id: -1,
        conversationId: 1,
        clientMessageId: '00522615-880e-4db4-8e90-cf493980675b',
        senderUserid: 'u1',
        senderName: 'User One',
      );
      const sameSender = ChatMessage(
        id: 10,
        conversationId: 1,
        clientMessageId: '00522615-880e-4db4-8e90-cf493980675b',
        senderUserid: 'u1',
        senderName: 'User One',
      );
      const otherSender = ChatMessage(
        id: 11,
        conversationId: 1,
        clientMessageId: '00522615-880e-4db4-8e90-cf493980675b',
        senderUserid: 'u2',
        senderName: 'User Two',
      );

      expect(first.hasSameClientIdentity(sameSender), isTrue);
      expect(first.hasSameClientIdentity(otherSender), isFalse);
    });
  });

  test('auth clearing retains runtime until explicit logout', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = TokenStore();
    await store.saveSession(
      token: 'expired-token',
      userid: 'alice',
      fullname: 'Alice',
      accountId: 7,
    );
    await store.writeChatRuntime('alice', '{"pendingMessages":[]}');

    await store.clearSession();

    expect(store.token, isNull);
    expect(await store.readChatRuntime('alice'), '{"pendingMessages":[]}');

    await store.saveSession(
      token: 'new-token',
      userid: 'alice',
      fullname: 'Alice',
      accountId: 7,
    );
    await store.clearSession(clearChatRuntime: true);

    expect(await store.readChatRuntime('alice'), isNull);
  });
}
