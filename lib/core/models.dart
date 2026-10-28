enum Delivery { queued, sent, delivered, read, failed }

class Person {
  const Person({
    required this.id,
    required this.username,
    required this.name,
    this.bio = '',
    this.role = 'user',
    this.status = 'active',
  });
  final String id, username, name, bio, role, status;
  factory Person.fromJson(Map<String, dynamic> j) => Person(
    id: j['id'] as String,
    username: j['username'] as String,
    name: (j['display_name'] ?? j['username']) as String,
    bio: (j['bio'] ?? '') as String,
    role: (j['role'] ?? 'user') as String,
    status: (j['status'] ?? 'active') as String,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': name,
    'bio': bio,
    'role': role,
    'status': status,
  };
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.at,
    this.delivery = Delivery.queued,
    this.envelope,
    this.serverId,
  });
  final String id, chatId, senderId, text;
  final DateTime at;
  Delivery delivery;
  String? serverId;
  Map<String, dynamic>? envelope;
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'],
    chatId: j['chat_id'],
    senderId: j['sender_id'],
    text: j['text'],
    at: DateTime.parse(j['at']),
    delivery: Delivery.values.byName(j['delivery']),
    envelope: j['envelope'] == null
        ? null
        : Map<String, dynamic>.from(j['envelope']),
    serverId: j['server_id'],
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'chat_id': chatId,
    'sender_id': senderId,
    'text': text,
    'at': at.toIso8601String(),
    'delivery': delivery.name,
    'envelope': envelope,
    'server_id': serverId,
  };
}

class Conversation {
  Conversation({
    required this.id,
    required this.peer,
    this.pinned = false,
    this.muted = false,
    this.unread = 0,
  });
  final String id;
  final Person peer;
  bool pinned, muted;
  int unread;
  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
    id: j['id'],
    peer: Person.fromJson(Map<String, dynamic>.from(j['peer'])),
    pinned: j['pinned'] ?? false,
    muted: j['muted'] ?? false,
    unread: j['unread'] ?? 0,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'peer': peer.toJson(),
    'pinned': pinned,
    'muted': muted,
    'unread': unread,
  };
}

String? validateUsername(String? value) {
  final s = value?.trim() ?? '';
  if (!RegExp(r'^[a-z0-9_]{3,24}$').hasMatch(s)) {
    return 'Gunakan 3–24 huruf kecil, angka, atau underscore.';
  }
  if (['admin', 'support', 'system', 'root', 'adoetz'].contains(s)) {
    return 'Username ini tidak tersedia.';
  }
  return null;
}

String? validatePassword(String? value) =>
    (value?.length ?? 0) < 12 ? 'Gunakan minimal 12 karakter.' : null;
