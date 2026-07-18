import 'dart:convert';

class ChatUser {
  const ChatUser({
    required this.userid,
    required this.fullname,
    this.nickname = '',
    this.avatar = '',
    this.role = '',
    this.isContact = false,
    this.isOnline = false,
  });

  final String userid;
  final String fullname;
  final String nickname;
  final String avatar;
  final String role;
  final bool isContact;
  final bool isOnline;

  String get displayName {
    final alias = nickname.trim();
    if (alias.isNotEmpty) return alias;
    final name = fullname.trim();
    return name.isEmpty ? userid : name;
  }

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      userid: '${json['userid'] ?? ''}',
      fullname: '${json['fullname'] ?? ''}',
      nickname: '${json['nickname'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
      role: '${json['role'] ?? ''}',
      isContact: json['isContact'] == true,
      isOnline: json['isOnline'] == true,
    );
  }

  ChatUser copyWith({String? nickname, bool? isContact, bool? isOnline}) {
    return ChatUser(
      userid: userid,
      fullname: fullname,
      nickname: nickname ?? this.nickname,
      avatar: avatar,
      role: role,
      isContact: isContact ?? this.isContact,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

class ChatCallLog {
  const ChatCallLog({
    required this.status,
    required this.duration,
  });

  final String status;
  final int duration;

  bool get isMissed => status == 'missed';

  static ChatCallLog? tryParse(String content) {
    final value = content.trim();
    if (value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        final status = '${decoded['status'] ?? ''}'.trim();
        if (status != 'completed' && status != 'missed') return null;
        final rawDuration = decoded['duration'];
        final duration = rawDuration is int
            ? rawDuration
            : int.tryParse('$rawDuration') ?? 0;
        return ChatCallLog(
          status: status,
          duration: duration < 0 ? 0 : duration,
        );
      }
    } catch (_) {
      // Support call records created by earlier mobile builds.
    }

    if (value.toLowerCase().contains('cuộc gọi nhỡ')) {
      return const ChatCallLog(status: 'missed', duration: 0);
    }
    final durationMatch = RegExp(r'(\d{2,}):(\d{2})$').firstMatch(value);
    if (durationMatch != null) {
      final minutes = int.tryParse(durationMatch.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(durationMatch.group(2) ?? '') ?? 0;
      return ChatCallLog(
        status: 'completed',
        duration: minutes * 60 + seconds,
      );
    }
    return null;
  }
}

class ChatAttachment {
  const ChatAttachment({
    this.id = 0,
    this.messageId = 0,
    required this.fileName,
    required this.fileUrl,
    this.fileSize = 0,
    this.mimeType = '',
    this.relativePath = '',
  });

  final int id;
  final int messageId;
  final String fileName;
  final String fileUrl;
  final int fileSize;
  final String mimeType;
  final String relativePath;

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: _asInt(json['id']),
      messageId: _asInt(_value(json, 'messageId', 'message_id')),
      fileName: _asString(_value(json, 'fileName', 'file_name')),
      fileUrl: _asString(_value(json, 'fileUrl', 'file_url')),
      fileSize: _asInt(_value(json, 'fileSize', 'file_size')),
      mimeType: _asString(_value(json, 'mimeType', 'mime_type')),
      relativePath: _asString(_value(json, 'relativePath', 'relative_path')),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileName': fileName,
      'fileUrl': fileUrl,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'relativePath': relativePath,
    };
  }
}

enum MessageState {
  sending,
  failed,
  sent,
  delivered,
  read;

  static MessageState parse(Object? raw) {
    return switch ('$raw'.trim().toLowerCase()) {
      'sending' || 'pending' => MessageState.sending,
      'failed' || 'error' => MessageState.failed,
      'delivered' => MessageState.delivered,
      'read' || 'seen' => MessageState.read,
      _ => MessageState.sent,
    };
  }
}

class ChatReaction {
  const ChatReaction({
    required this.emoji,
    this.count = 0,
    this.reactedByMe = false,
    this.userids = const [],
    this.users = const [],
  });

  final String emoji;
  final int count;
  final bool reactedByMe;
  final List<String> userids;
  final List<ChatUser> users;

  factory ChatReaction.fromJson(Map<String, dynamic> json) {
    final rawUsers = json['users'];
    final users = rawUsers is List
        ? rawUsers
            .whereType<Map>()
            .map((item) => ChatUser.fromJson(Map<String, dynamic>.from(item)))
            .where((user) => user.userid.isNotEmpty)
            .toList()
        : <ChatUser>[];
    final rawUserids = _value(json, 'userids', 'userIds');
    final userids = rawUserids is List
        ? rawUserids
            .map((item) => item is Map
                ? _asString(_value(Map<String, dynamic>.from(item), 'userid',
                    'userId', 'user_id'))
                : '$item')
            .where((userid) => userid.isNotEmpty)
            .toList()
        : <String>[];
    if (rawUsers is List) {
      for (final item in rawUsers.where((item) => item is! Map)) {
        final userid = '$item'.trim();
        if (userid.isNotEmpty && !userids.contains(userid)) {
          userids.add(userid);
        }
      }
    }
    for (final user in users) {
      if (!userids.contains(user.userid)) userids.add(user.userid);
    }
    final singleUserid =
        _asString(_value(json, 'userid', 'userId', 'user_id', 'createdBy'));
    if (singleUserid.isNotEmpty && !userids.contains(singleUserid)) {
      userids.add(singleUserid);
    }
    return ChatReaction(
      emoji: _asString(json['emoji']),
      count: _asInt(json['count']) > 0
          ? _asInt(json['count'])
          : userids.isEmpty
              ? 1
              : userids.length,
      reactedByMe: _asBool(
          _value(json, 'reactedByMe', 'reacted_by_me', 'mine', 'hasReacted')),
      userids: userids,
      users: users,
    );
  }

  ChatReaction copyWith({
    int? count,
    bool? reactedByMe,
    List<String>? userids,
    List<ChatUser>? users,
  }) {
    return ChatReaction(
      emoji: emoji,
      count: count ?? this.count,
      reactedByMe: reactedByMe ?? this.reactedByMe,
      userids: userids ?? this.userids,
      users: users ?? this.users,
    );
  }
}

class ChatMessageEditHistoryEntry {
  const ChatMessageEditHistoryEntry({
    required this.auditId,
    required this.messageId,
    required this.previousVersion,
    required this.version,
    required this.previousContent,
    required this.content,
    required this.editorUserid,
    required this.editorName,
    required this.editorAvatar,
    this.editedAt,
  });

  final int auditId;
  final int messageId;
  final int previousVersion;
  final int version;
  final String previousContent;
  final String content;
  final String editorUserid;
  final String editorName;
  final String editorAvatar;
  final DateTime? editedAt;

  factory ChatMessageEditHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ChatMessageEditHistoryEntry(
      auditId: _asInt(_value(json, 'auditId', 'audit_id')),
      messageId: _asInt(_value(json, 'messageId', 'message_id')),
      previousVersion:
          _asInt(_value(json, 'previousVersion', 'previous_version')),
      version: _asInt(json['version']),
      previousContent:
          _asString(_value(json, 'previousContent', 'previous_content')),
      content: _asString(json['content']),
      editorUserid: _asString(_value(json, 'editorUserid', 'editor_userid')),
      editorName: _asString(_value(json, 'editorName', 'editor_name')),
      editorAvatar: _asString(_value(json, 'editorAvatar', 'editor_avatar')),
      editedAt: _asDate(_value(json, 'editedAt', 'edited_at')),
    );
  }
}

class ChatReadReceipt {
  const ChatReadReceipt({
    required this.userid,
    required this.messageId,
    this.deliveredAt,
    this.readAt,
  });

  final String userid;
  final int messageId;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  factory ChatReadReceipt.fromJson(Map<String, dynamic> json) {
    return ChatReadReceipt(
      userid: _asString(_value(json, 'userid', 'userId', 'user_id')),
      messageId:
          _asInt(_value(json, 'messageId', 'lastReadMessageId', 'message_id')),
      deliveredAt: _asDate(_value(json, 'deliveredAt', 'delivered_at')),
      readAt: _asDate(_value(json, 'readAt', 'lastReadAt', 'read_at')),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderUserid,
    required this.senderName,
    this.senderAvatar = '',
    this.type = 'text',
    this.content = '',
    this.replyTo,
    this.forwardedFrom,
    this.attachments = const [],
    this.poll,
    this.createdAt,
    this.clientMessageId = '',
    this.serverSequence = 0,
    this.version = 1,
    this.state = MessageState.sent,
    this.totalRecipients = 0,
    this.deliveredCount = 0,
    this.readCount = 0,
    this.readReceipts = const [],
    this.reactions = const [],
    this.editedAt,
    this.deletedAt,
    this.deletedBy = '',
    this.isRecalled = false,
    this.recallUntil,
    this.canRecall = false,
    this.idempotentReplay = false,
  });

  final int id;
  final int conversationId;
  final String senderUserid;
  final String senderName;
  final String senderAvatar;
  final String type;
  final String content;
  final ChatMessageReference? replyTo;
  final ChatMessageReference? forwardedFrom;
  final List<ChatAttachment> attachments;
  final ChatPoll? poll;
  final DateTime? createdAt;
  final String clientMessageId;
  final int serverSequence;
  final int version;
  final MessageState state;
  final int totalRecipients;
  final int deliveredCount;
  final int readCount;
  final List<ChatReadReceipt> readReceipts;
  final List<ChatReaction> reactions;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String deletedBy;
  final bool isRecalled;
  final DateTime? recallUntil;
  final bool canRecall;
  final bool idempotentReplay;

  bool get isDeleted => isRecalled || deletedAt != null;
  bool get canRetry =>
      state == MessageState.failed && clientMessageId.isNotEmpty;
  bool get canRecallNow =>
      canRecall &&
      !isDeleted &&
      (recallUntil == null || recallUntil!.isAfter(DateTime.now()));
  List<ChatAttachment> get visibleAttachments =>
      isDeleted ? const [] : attachments;

  bool hasSameClientIdentity(ChatMessage other) {
    return clientMessageId.isNotEmpty &&
        clientMessageId == other.clientMessageId &&
        senderUserid.isNotEmpty &&
        senderUserid == other.senderUserid;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final replyToJson = _value(json, 'replyTo', 'reply_to');
    final forwardedFromJson = _value(json, 'forwardedFrom', 'forwarded_from');
    final pollJson = json['poll'];
    final deletedAt = _asDate(_value(json, 'deletedAt', 'deleted_at'));
    final rawReceiptSummary = _value(json, 'receiptSummary', 'receipt_summary');
    final receiptSummary = rawReceiptSummary is Map
        ? Map<String, dynamic>.from(rawReceiptSummary)
        : const <String, dynamic>{};
    final deliveredCount = _asInt(
        _value(json, 'deliveredCount', 'delivered_count') ??
            _value(receiptSummary, 'deliveredRecipients',
                'delivered_recipients', 'deliveredCount'));
    final readCount = _asInt(_value(json, 'readCount', 'read_count') ??
        _value(
            receiptSummary, 'readRecipients', 'read_recipients', 'readCount'));
    final totalRecipients = _asInt(
        _value(json, 'totalRecipients', 'total_recipients') ??
            _value(receiptSummary, 'totalRecipients', 'total_recipients'));
    final explicitState =
        _value(json, 'state', 'messageState', 'deliveryState', 'status');
    final recallUntil = _asDate(_value(json, 'recallUntil', 'recall_until'));
    final rawCanRecall = _value(json, 'canRecall', 'can_recall');
    return ChatMessage(
      id: _asInt(json['id']),
      conversationId: _asInt(_value(json, 'conversationId', 'conversation_id')),
      senderUserid: _asString(
          _value(json, 'senderUserid', 'senderUserId', 'sender_userid')),
      senderName: _asString(_value(json, 'senderName', 'sender_name')),
      senderAvatar: _asString(_value(json, 'senderAvatar', 'sender_avatar')),
      type: '${json['type'] ?? 'text'}',
      content: '${json['content'] ?? ''}',
      replyTo: replyToJson is Map
          ? ChatMessageReference.fromJson(
              Map<String, dynamic>.from(replyToJson))
          : null,
      forwardedFrom: forwardedFromJson is Map
          ? ChatMessageReference.fromJson(
              Map<String, dynamic>.from(forwardedFromJson))
          : null,
      attachments: _listOfMaps(json['attachments'])
          .map(ChatAttachment.fromJson)
          .toList(),
      poll: pollJson is Map
          ? ChatPoll.fromJson(Map<String, dynamic>.from(pollJson))
          : null,
      createdAt: _asDate(_value(json, 'createdAt', 'created_at')),
      clientMessageId:
          _asString(_value(json, 'clientMessageId', 'client_message_id')),
      serverSequence:
          _asInt(_value(json, 'serverSequence', 'server_sequence', 'sequence')),
      version: _asInt(json['version']) <= 0 ? 1 : _asInt(json['version']),
      state: explicitState != null
          ? MessageState.parse(explicitState)
          : totalRecipients > 0 && readCount >= totalRecipients
              ? MessageState.read
              : totalRecipients > 0 && deliveredCount >= totalRecipients
                  ? MessageState.delivered
                  : totalRecipients == 0 && readCount > 0
                      ? MessageState.read
                      : totalRecipients == 0 && deliveredCount > 0
                          ? MessageState.delivered
                          : MessageState.sent,
      totalRecipients: totalRecipients,
      deliveredCount: deliveredCount,
      readCount: readCount,
      readReceipts:
          _listOfMaps(_value(json, 'readReceipts', 'read_receipts', 'receipts'))
              .map(ChatReadReceipt.fromJson)
              .toList(),
      reactions: _parseReactions(json['reactions']),
      editedAt: _asDate(_value(json, 'editedAt', 'edited_at')),
      deletedAt: deletedAt,
      deletedBy: _asString(_value(json, 'deletedBy', 'deleted_by')),
      isRecalled: _asBool(_value(json, 'isRecalled', 'is_recalled')) ||
          deletedAt != null,
      recallUntil: recallUntil,
      canRecall: rawCanRecall == null
          ? recallUntil?.isAfter(DateTime.now()) == true
          : _asBool(rawCanRecall),
      idempotentReplay:
          _asBool(_value(json, 'idempotentReplay', 'idempotent_replay')),
    );
  }

  Map<String, dynamic> toOutboxJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'clientMessageId': clientMessageId,
      'senderUserid': senderUserid,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'type': type,
      'content': content,
      if (replyTo != null) 'replyTo': replyTo!.toJson(),
      if (forwardedFrom != null) 'forwardedFrom': forwardedFrom!.toJson(),
      'attachments':
          attachments.map((attachment) => attachment.toJson()).toList(),
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'state': state.name,
      'version': version,
    };
  }

  ChatMessage copyWith({
    int? id,
    String? content,
    List<ChatAttachment>? attachments,
    ChatPoll? poll,
    DateTime? createdAt,
    String? clientMessageId,
    int? serverSequence,
    int? version,
    MessageState? state,
    int? totalRecipients,
    int? deliveredCount,
    int? readCount,
    List<ChatReadReceipt>? readReceipts,
    List<ChatReaction>? reactions,
    DateTime? editedAt,
    DateTime? deletedAt,
    String? deletedBy,
    bool? isRecalled,
    DateTime? recallUntil,
    bool? canRecall,
    bool? idempotentReplay,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      senderUserid: senderUserid,
      senderName: senderName,
      senderAvatar: senderAvatar,
      type: type,
      content: content ?? this.content,
      replyTo: replyTo,
      forwardedFrom: forwardedFrom,
      attachments: attachments ?? this.attachments,
      poll: poll ?? this.poll,
      createdAt: createdAt ?? this.createdAt,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      serverSequence: serverSequence ?? this.serverSequence,
      version: version ?? this.version,
      state: state ?? this.state,
      totalRecipients: totalRecipients ?? this.totalRecipients,
      deliveredCount: deliveredCount ?? this.deliveredCount,
      readCount: readCount ?? this.readCount,
      readReceipts: readReceipts ?? this.readReceipts,
      reactions: reactions ?? this.reactions,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      isRecalled: isRecalled ?? this.isRecalled,
      recallUntil: recallUntil ?? this.recallUntil,
      canRecall: canRecall ?? this.canRecall,
      idempotentReplay: idempotentReplay ?? this.idempotentReplay,
    );
  }
}

class ChatPoll {
  const ChatPoll({
    required this.id,
    required this.messageId,
    required this.question,
    this.allowCustomOptions = false,
    this.allowMultiple = false,
    this.showVoters = false,
    this.isClosed = false,
    this.createdBy = '',
    this.options = const [],
    this.myOptionIds = const [],
    this.totalVotes = 0,
  });

  final int id;
  final int messageId;
  final String question;
  final bool allowCustomOptions;
  final bool allowMultiple;
  final bool showVoters;
  final bool isClosed;
  final String createdBy;
  final List<ChatPollOption> options;
  final List<int> myOptionIds;
  final int totalVotes;

  factory ChatPoll.fromJson(Map<String, dynamic> json) {
    final rawOptionIds = json['myOptionIds'] ?? json['myOptionIDs'];
    return ChatPoll(
      id: _asInt(json['id']),
      messageId: _asInt(json['messageId']),
      question: '${json['question'] ?? ''}',
      allowCustomOptions: json['allowCustomOptions'] == true,
      allowMultiple: json['allowMultiple'] == true,
      showVoters: json['showVoters'] == true,
      isClosed: json['isClosed'] == true,
      createdBy: '${json['createdBy'] ?? ''}',
      options:
          _listOfMaps(json['options']).map(ChatPollOption.fromJson).toList(),
      myOptionIds: rawOptionIds is List
          ? rawOptionIds.map(_asInt).where((id) => id > 0).toList()
          : const [],
      totalVotes: _asInt(json['totalVotes']),
    );
  }
}

class ChatPollOption {
  const ChatPollOption({
    required this.id,
    required this.text,
    this.voteCount = 0,
    this.voters = const [],
  });

  final int id;
  final String text;
  final int voteCount;
  final List<ChatPollVoter> voters;

  factory ChatPollOption.fromJson(Map<String, dynamic> json) {
    return ChatPollOption(
      id: _asInt(json['id']),
      text: '${json['text'] ?? ''}',
      voteCount: _asInt(json['voteCount']),
      voters: _listOfMaps(json['voters']).map(ChatPollVoter.fromJson).toList(),
    );
  }
}

class ChatPollVoter {
  const ChatPollVoter({
    required this.userid,
    required this.fullname,
    this.avatar = '',
  });

  final String userid;
  final String fullname;
  final String avatar;

  factory ChatPollVoter.fromJson(Map<String, dynamic> json) {
    return ChatPollVoter(
      userid: '${json['userid'] ?? ''}',
      fullname: '${json['fullname'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
    );
  }
}

class ChatMessageReference {
  const ChatMessageReference({
    required this.id,
    required this.senderUserid,
    required this.senderName,
    this.type = 'text',
    this.content = '',
  });

  final int id;
  final String senderUserid;
  final String senderName;
  final String type;
  final String content;

  factory ChatMessageReference.fromJson(Map<String, dynamic> json) {
    return ChatMessageReference(
      id: _asInt(json['id']),
      senderUserid: '${json['senderUserid'] ?? ''}',
      senderName: '${json['senderName'] ?? ''}',
      type: '${json['type'] ?? 'text'}',
      content: '${json['content'] ?? ''}',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderUserid': senderUserid,
      'senderName': senderName,
      'type': type,
      'content': content,
    };
  }
}

class PinnedMessageState {
  const PinnedMessageState({
    required this.conversationId,
    this.pinnedMessage,
    this.systemMessage,
    this.pinnedBy = '',
    this.pinnedByName = '',
    this.pinnedAt,
    this.actorUserid = '',
    this.actorName = '',
  });

  final int conversationId;
  final ChatMessageReference? pinnedMessage;
  final ChatMessage? systemMessage;
  final String pinnedBy;
  final String pinnedByName;
  final DateTime? pinnedAt;
  final String actorUserid;
  final String actorName;

  factory PinnedMessageState.fromJson(Map<String, dynamic> json) {
    final rawMessage = _value(json, 'pinnedMessage', 'pinned_message');
    final rawSystemMessage = _value(json, 'systemMessage', 'system_message');
    return PinnedMessageState(
      conversationId: _asInt(_value(json, 'conversationId', 'conversation_id')),
      pinnedMessage: rawMessage is Map
          ? ChatMessageReference.fromJson(Map<String, dynamic>.from(rawMessage))
          : null,
      systemMessage: rawSystemMessage is Map
          ? ChatMessage.fromJson(Map<String, dynamic>.from(rawSystemMessage))
          : null,
      pinnedBy: _asString(_value(json, 'pinnedBy', 'pinned_by')),
      pinnedByName: _asString(_value(json, 'pinnedByName', 'pinned_by_name')),
      pinnedAt: _asDate(_value(json, 'pinnedAt', 'pinned_at')),
      actorUserid:
          _asString(_value(json, 'actorUserid', 'actor_userid', 'userid')),
      actorName: _asString(_value(json, 'actorName', 'actor_name')),
    );
  }
}

class ChatRuntimeSnapshot {
  const ChatRuntimeSnapshot({
    this.pendingMessages = const [],
    this.lastSeenMessageIds = const {},
    this.lastSeenSequences = const {},
  });

  final List<ChatMessage> pendingMessages;
  final Map<int, int> lastSeenMessageIds;
  final Map<int, int> lastSeenSequences;

  factory ChatRuntimeSnapshot.fromJson(Map<String, dynamic> json) {
    return ChatRuntimeSnapshot(
      pendingMessages: _listOfMaps(json['pendingMessages'])
          .map(ChatMessage.fromJson)
          .where((message) =>
              message.id <= 0 && message.clientMessageId.trim().isNotEmpty)
          .toList(),
      lastSeenMessageIds: _intMap(json['lastSeenMessageIds']),
      lastSeenSequences: _intMap(json['lastSeenSequences']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'pendingMessages': pendingMessages
          .where((message) =>
              message.id <= 0 && message.clientMessageId.trim().isNotEmpty)
          .map((message) => message.toOutboxJson())
          .toList(),
      'lastSeenMessageIds': {
        for (final entry in lastSeenMessageIds.entries)
          '${entry.key}': entry.value,
      },
      'lastSeenSequences': {
        for (final entry in lastSeenSequences.entries)
          '${entry.key}': entry.value,
      },
    };
  }
}

class ConversationReadState {
  const ConversationReadState({
    required this.conversationId,
    this.userid = '',
    this.lastReadMessageId = 0,
    this.lastReadAt,
    this.unreadCount = 0,
  });

  final int conversationId;
  final String userid;
  final int lastReadMessageId;
  final DateTime? lastReadAt;
  final int unreadCount;

  factory ConversationReadState.fromJson(Map<String, dynamic> json) {
    return ConversationReadState(
      conversationId: _asInt(_value(json, 'conversationId', 'conversation_id')),
      userid: _asString(_value(json, 'userid', 'userId', 'user_id')),
      lastReadMessageId:
          _asInt(_value(json, 'lastReadMessageId', 'last_read_message_id')),
      lastReadAt: _asDate(_value(json, 'lastReadAt', 'last_read_at')),
      unreadCount: _asInt(_value(json, 'unreadCount', 'unread_count')),
    );
  }
}

class ConversationSettings {
  const ConversationSettings({
    this.muteUntil,
    this.pinnedAt,
    this.archivedAt,
  });

  final DateTime? muteUntil;
  final DateTime? pinnedAt;
  final DateTime? archivedAt;

  bool get isMuted => muteUntil?.isAfter(DateTime.now()) == true;
  bool get isPinned => pinnedAt != null;
  bool get isArchived => archivedAt != null;

  factory ConversationSettings.fromJson(Map<String, dynamic> json) {
    return ConversationSettings(
      muteUntil: _asDate(_value(json, 'muteUntil', 'mute_until')),
      pinnedAt: _asDate(_value(json, 'pinnedAt', 'pinned_at')),
      archivedAt: _asDate(_value(json, 'archivedAt', 'archived_at')),
    );
  }

  ConversationSettings copyWith({
    Object? muteUntil = _unset,
    Object? pinnedAt = _unset,
    Object? archivedAt = _unset,
  }) {
    return ConversationSettings(
      muteUntil: identical(muteUntil, _unset)
          ? this.muteUntil
          : muteUntil as DateTime?,
      pinnedAt:
          identical(pinnedAt, _unset) ? this.pinnedAt : pinnedAt as DateTime?,
      archivedAt: identical(archivedAt, _unset)
          ? this.archivedAt
          : archivedAt as DateTime?,
    );
  }
}

class ChatConversation {
  const ChatConversation({
    required this.id,
    this.type = 'direct',
    this.name = '',
    this.avatar = '',
    this.background = '',
    this.memberCount = 0,
    this.members = const [],
    this.lastMessage,
    this.pinnedMessage,
    this.lastReadMessageId = 0,
    this.lastReadAt,
    this.unreadCount = 0,
    this.settings = const ConversationSettings(),
  });

  final int id;
  final String type;
  final String name;
  final String avatar;
  final String background;
  final int memberCount;
  final List<ChatUser> members;
  final ChatMessage? lastMessage;
  final ChatMessageReference? pinnedMessage;
  final int lastReadMessageId;
  final DateTime? lastReadAt;
  final int unreadCount;
  final ConversationSettings settings;

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final lastMessageJson = _value(json, 'lastMessage', 'last_message');
    final pinnedMessageJson = _value(json, 'pinnedMessage', 'pinned_message');
    final settingsJson =
        _value(json, 'userSettings', 'settings', 'conversationSettings');
    return ChatConversation(
      id: _asInt(json['id']),
      type: '${json['type'] ?? 'direct'}',
      name: '${json['name'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
      background: '${json['background'] ?? ''}',
      memberCount: _asInt(_value(json, 'memberCount', 'member_count')),
      members: _listOfMaps(json['members']).map(ChatUser.fromJson).toList(),
      lastMessage: lastMessageJson is Map
          ? ChatMessage.fromJson(Map<String, dynamic>.from(lastMessageJson))
          : null,
      pinnedMessage: pinnedMessageJson is Map
          ? ChatMessageReference.fromJson(
              Map<String, dynamic>.from(pinnedMessageJson))
          : null,
      lastReadMessageId:
          _asInt(_value(json, 'lastReadMessageId', 'last_read_message_id')),
      lastReadAt: _asDate(_value(json, 'lastReadAt', 'last_read_at')),
      unreadCount: _asInt(_value(json, 'unreadCount', 'unread_count')),
      settings: settingsJson is Map
          ? ConversationSettings.fromJson(
              Map<String, dynamic>.from(settingsJson))
          : ConversationSettings.fromJson(json),
    );
  }

  ChatConversation copyWith({
    List<ChatUser>? members,
    ChatMessage? lastMessage,
    Object? pinnedMessage = _unset,
    int? lastReadMessageId,
    DateTime? lastReadAt,
    int? unreadCount,
    ConversationSettings? settings,
  }) {
    return ChatConversation(
      id: id,
      type: type,
      name: name,
      avatar: avatar,
      background: background,
      memberCount: memberCount,
      members: members ?? this.members,
      lastMessage: lastMessage ?? this.lastMessage,
      pinnedMessage: identical(pinnedMessage, _unset)
          ? this.pinnedMessage
          : pinnedMessage as ChatMessageReference?,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      unreadCount: unreadCount ?? this.unreadCount,
      settings: settings ?? this.settings,
    );
  }

  String titleFor(String currentUserid) {
    if (name.trim().isNotEmpty) return name.trim();
    final other =
        members.where((user) => user.userid != currentUserid).firstOrNull;
    return other == null ? 'Cuoc tro chuyen #$id' : other.displayName;
  }
}

class ChatSearchResults {
  const ChatSearchResults({
    this.contacts = const [],
    this.messages = const [],
    this.files = const [],
  });

  final List<ChatUser> contacts;
  final List<ChatMessage> messages;
  final List<ChatMessage> files;

  factory ChatSearchResults.fromJson(Map<String, dynamic> json) {
    return ChatSearchResults(
      contacts: _listOfMaps(json['contacts']).map(ChatUser.fromJson).toList(),
      messages:
          _listOfMaps(json['messages']).map(ChatMessage.fromJson).toList(),
      files: _listOfMaps(json['files']).map(ChatMessage.fromJson).toList(),
    );
  }
}

class RealtimeEvent {
  const RealtimeEvent({
    required this.type,
    this.eventId = '',
    this.serverTimestamp,
    this.conversationId = 0,
    this.messageId = 0,
    this.version = 1,
    this.userid = '',
    this.fromUserid = '',
    this.callId = '',
    this.sourceDeviceId = '',
    this.signal,
    this.isOnline = false,
    this.message,
    this.payload = const {},
  });

  final String type;
  final String eventId;
  final DateTime? serverTimestamp;
  final int conversationId;
  final int messageId;
  final int version;
  final String userid;
  final String fromUserid;
  final String callId;
  final String sourceDeviceId;
  final Map<String, dynamic>? signal;
  final bool isOnline;
  final ChatMessage? message;
  final Map<String, dynamic> payload;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : <String, dynamic>{};
    final messageJson = json['message'] ?? payload['message'];
    final signalJson = json['signal'] ?? payload['signal'];
    final message = messageJson is Map
        ? ChatMessage.fromJson(Map<String, dynamic>.from(messageJson))
        : null;
    return RealtimeEvent(
      type: _asString(_value(json, 'type', 'eventType', 'event_type')),
      eventId: _asString(_value(json, 'eventId', 'event_id')),
      serverTimestamp:
          _asDate(_value(json, 'serverTimestamp', 'server_timestamp')),
      conversationId: _asInt(
          _value(json, 'conversationId', 'conversation_id') ??
              _value(payload, 'conversationId', 'conversation_id') ??
              message?.conversationId),
      messageId: _asInt(_value(json, 'messageId', 'message_id') ??
          _value(payload, 'messageId', 'message_id') ??
          message?.id),
      version: _asInt(json['version']) <= 0 ? 1 : _asInt(json['version']),
      userid: _asString(_value(json, 'userid', 'userId', 'user_id') ??
          _value(payload, 'userid', 'userId', 'user_id')),
      fromUserid: _asString(_value(json, 'fromUserid', 'fromUserId') ??
          _value(payload, 'fromUserid', 'fromUserId')),
      callId: _asString(json['callId'] ?? payload['callId']),
      sourceDeviceId: _asString(
          _value(json, 'sourceDeviceId', 'source_device_id') ??
              _value(payload, 'sourceDeviceId', 'source_device_id')),
      signal: signalJson is Map ? Map<String, dynamic>.from(signalJson) : null,
      isOnline: _asBool(json['isOnline'] ?? payload['isOnline']),
      message: message,
      payload: payload,
    );
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

const _unset = Object();

Object? _value(Map<String, dynamic> json, String first,
    [String? second, String? third, String? fourth]) {
  if (json.containsKey(first)) return json[first];
  if (second != null && json.containsKey(second)) return json[second];
  if (third != null && json.containsKey(third)) return json[third];
  if (fourth != null && json.containsKey(fourth)) return json[fourth];
  return null;
}

String _asString(Object? value) => value == null ? '' : '$value';

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return const {'true', '1', 'yes'}.contains('$value'.toLowerCase());
}

DateTime? _asDate(Object? value) {
  if (value == null || '$value'.trim().isEmpty) return null;
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(
        value < 100000000000 ? value * 1000 : value,
        isUtc: true);
  }
  return DateTime.tryParse('$value');
}

List<ChatReaction> _parseReactions(Object? value) {
  final parsed = _listOfMaps(value).map(ChatReaction.fromJson).toList();
  if (parsed.isEmpty) return const [];
  final aggregated = <String, ChatReaction>{};
  for (final reaction in parsed) {
    if (reaction.emoji.isEmpty) continue;
    final previous = aggregated[reaction.emoji];
    if (previous == null) {
      aggregated[reaction.emoji] = reaction;
      continue;
    }
    final userids = {...previous.userids, ...reaction.userids}.toList();
    aggregated[reaction.emoji] = ChatReaction(
      emoji: reaction.emoji,
      count:
          userids.isNotEmpty ? userids.length : previous.count + reaction.count,
      reactedByMe: previous.reactedByMe || reaction.reactedByMe,
      userids: userids,
    );
  }
  return aggregated.values.toList();
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

Map<int, int> _intMap(Object? value) {
  if (value is! Map) return const {};
  final result = <int, int>{};
  for (final entry in value.entries) {
    final key = _asInt(entry.key);
    final item = _asInt(entry.value);
    if (key > 0 && item >= 0) result[key] = item;
  }
  return result;
}
