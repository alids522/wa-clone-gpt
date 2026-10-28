import 'package:flutter_test/flutter_test.dart';
import 'package:adoetz_chat/core/call_record.dart';

void main() {
  test(
    'call log distinguishes missed, canceled, incoming/outgoing and duration',
    () {
      final data = <String, dynamic>{
        'caller_id': 'alice',
        'status': 'ended',
        'created_at': '2026-01-01T10:00:00Z',
        'expires_at': '2026-01-01T10:00:45Z',
      };
      final record = CallRecord(data);
      expect(record.label('alice'), 'Dibatalkan');
      expect(record.label('bob'), 'Tak terjawab');
      expect(record.duration, isNull);
      data['connected_at'] = '2026-01-01T10:00:05Z';
      data['ended_at'] = '2026-01-01T10:01:07Z';
      expect(record.label('alice'), 'Keluar');
      expect(record.label('bob'), 'Masuk');
      expect(record.duration, '1 mnt 2 dtk');
      data['status'] = 'ringing';
      data['connected_at'] = null;
      expect(record.status, 'missed');
      expect(record.label('alice'), 'Tidak dijawab');
      expect(record.label('bob'), 'Tak terjawab');
    },
  );
}
