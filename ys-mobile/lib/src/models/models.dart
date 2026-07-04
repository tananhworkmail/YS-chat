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
    this.attachments = const [],
    this.createdAt,
  });

  final int id;
  final int conversationId;
  final String senderUserid;
  final String senderName;
  final String senderAvatar;
  final String type;
  final String content;
  final List<ChatAttachment> attachments;
  final DateTime? createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversationId']),
      senderUserid: '${json['senderUserid'] ?? ''}',
      senderName: '${json['senderName'] ?? ''}',
      senderAvatar: '${json['senderAvatar'] ?? ''}',
      type: '${json['type'] ?? 'text'}',
      content: '${json['content'] ?? ''}',
      attachments: _listOfMaps(json['attachments'])
          .map(ChatAttachment.fromJson)
          .toList(),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
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
    this.isOnline = false,
    this.message,
  });

  final String type;
  final int conversationId;
  final String userid;
  final bool isOnline;
  final ChatMessage? message;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final messageJson = json['message'];
    return RealtimeEvent(
      type: '${json['type'] ?? ''}',
      conversationId: _asInt(json['conversationId']),
      userid: '${json['userid'] ?? ''}',
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
