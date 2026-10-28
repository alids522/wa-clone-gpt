import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:adoetz_chat/core/streaming_storage.dart';

void main() {
  test(
    'ciphertext upload streams a large file with authenticated Storage headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final dir = await Directory.systemTemp.createTemp('adoetz-upload-test-');
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-public-key',
        accessToken: () async => 'test-session-token',
      );
      try {
        final file = File('${dir.path}/cipher');
        final bytes = List<int>.generate(3 * 1024 * 1024 + 17, (i) => i % 251);
        await file.writeAsBytes(bytes);
        final expected = base64Encode((await Sha256().hash(bytes)).bytes);
        final requests = server.listen((request) async {
          expect(
            request.uri.path,
            '/storage/v1/object/chat-media/room/owner/object',
          );
          expect(
            request.headers.value('authorization'),
            'Bearer test-session-token',
          );
          expect(request.headers.value('apikey'), 'test-public-key');
          expect(
            request.headers.contentType?.mimeType,
            'application/octet-stream',
          );
          expect(request.contentLength, bytes.length);
          final digest = Sha256().newHashSink();
          await for (final chunk in request) {
            digest.add(chunk);
          }
          digest.close();
          expect(base64Encode((await digest.hash()).bytes), expected);
          request.response
            ..statusCode = 200
            ..write('{"Key":"room/owner/object"}');
          await request.response.close();
        });
        await StreamingStorage().upload(client, 'room/owner/object', file);
        await requests.cancel();
      } finally {
        await client.dispose();
        await server.close(force: true);
        for (final file in dir.listSync()) {
          await file.delete();
        }
        await dir.delete();
      }
    },
  );
}
