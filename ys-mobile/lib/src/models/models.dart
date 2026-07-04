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

  ChatUser copyWith({bool? isOnline}) {
    return ChatUser(
      userid: userid,
      fullname: fullname,
      nickname: nickname,
      avatar: avatar,
      role: role,
      isContact: isContact,
      isOnline: isOnline ?? this.isOnline,
    );
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
      messageId: _asInt(json['messageId']),
      fileName: '${json['fileName'] ?? ''}',
      fileUrl: '${json['fileUrl'] ?? ''}',
      fileSize: _asInt(json['fileSize']),
      mimeType: '${json['mimeType'] ?? ''}',
      relativePath: '${json['relativePath'] ?? ''}',
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

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final replyToJson = json['replyTo'];
    final forwardedFromJson = json['forwardedFrom'];
    final pollJson = json['poll'];
    return ChatMessage(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversationId']),
      senderUserid: '${json['senderUserid'] ?? ''}',
      senderName: '${json['senderName'] ?? ''}',
      senderAvatar: '${json['senderAvatar'] ?? ''}',
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
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
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
  });

  final int id;
  final String type;
  final String name;
  final String avatar;
  final String background;
  final int memberCount;
  final List<ChatUser> members;
  final ChatMessage? lastMessage;

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final lastMessageJson = json['lastMessage'];
    return ChatConversation(
      id: _asInt(json['id']),
      type: '${json['type'] ?? 'direct'}',
      name: '${json['name'] ?? ''}',
      avatar: '${json['avatar'] ?? ''}',
      background: '${json['background'] ?? ''}',
      memberCount: _asInt(json['memberCount']),
      members: _listOfMaps(json['members']).map(ChatUser.fromJson).toList(),
      lastMessage: lastMessageJson is Map<String, dynamic>
          ? ChatMessage.fromJson(lastMessageJson)
          : null,
    );
  }

  ChatConversation copyWith({
    List<ChatUser>? members,
    ChatMessage? lastMessage,
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
    );
  }

  String titleFor(String currentUserid) {
    if (name.trim().isNotEmpty) return name.trim();
    final other =
        members.where((user) => user.userid != currentUserid).firstOrNull;
    return other?.fullname.trim().isNotEmpty == true
        ? other!.fullname
        : 'Cuoc tro chuyen #$id';
  }
}

class RealtimeEvent {
  const RealtimeEvent({
    required this.type,
    this.conversationId = 0,
    this.userid = '',
    this.fromUserid = '',
    this.callId = '',
    this.signal,
    this.isOnline = false,
    this.message,
  });

  final String type;
  final int conversationId;
  final String userid;
  final String fromUserid;
  final String callId;
  final Map<String, dynamic>? signal;
  final bool isOnline;
  final ChatMessage? message;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final messageJson = json['message'];
    final signalJson = json['signal'];
    return RealtimeEvent(
      type: '${json['type'] ?? ''}',
      conversationId: _asInt(json['conversationId']),
      userid: '${json['userid'] ?? ''}',
      fromUserid: '${json['fromUserid'] ?? ''}',
      callId: '${json['callId'] ?? ''}',
      signal: signalJson is Map ? Map<String, dynamic>.from(signalJson) : null,
      isOnline: json['isOnline'] == true,
      message: messageJson is Map<String, dynamic>
          ? ChatMessage.fromJson(messageJson)
          : null,
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

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
