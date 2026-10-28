class CallRecord {
  CallRecord(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'];
  String get chatId => data['conversation_id'];
  bool get video => data['video'] == true;
  DateTime get at => DateTime.parse(data['created_at']).toLocal();
  bool outgoing(String owner) => data['caller_id'] == owner;
  String get status {
    final value = data['status'] as String;
    if (['ringing', 'connecting', 'connected'].contains(value) &&
        DateTime.parse(data['expires_at']).isBefore(DateTime.now())) {
      return value == 'ringing' ? 'missed' : 'failed';
    }
    return value;
  }

  bool get unanswered => data['connected_at'] == null;
  String label(String owner) => switch (status) {
    'missed' => outgoing(owner) ? 'Tidak dijawab' : 'Tak terjawab',
    'declined' => 'Ditolak',
    'failed' => 'Gagal tersambung',
    'ringing' => outgoing(owner) ? 'Memanggil' : 'Panggilan masuk',
    'connecting' => 'Menghubungkan',
    'connected' => 'Berlangsung',
    _ =>
      unanswered
          ? (outgoing(owner) ? 'Dibatalkan' : 'Tak terjawab')
          : (outgoing(owner) ? 'Keluar' : 'Masuk'),
  };
  String? get duration {
    if (data['connected_at'] == null || data['ended_at'] == null) return null;
    final seconds = DateTime.parse(data['ended_at'])
        .difference(DateTime.parse(data['connected_at']))
        .inSeconds
        .clamp(0, 864000);
    if (seconds < 60) return '$seconds dtk';
    return '${seconds ~/ 60} mnt${seconds % 60 == 0 ? '' : ' ${seconds % 60} dtk'}';
  }
}
