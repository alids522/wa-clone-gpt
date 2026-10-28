import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The pinned SDK's File upload buffers the entire file. Stream ciphertext here
/// so a 100 MB video does not require a 100 MB Dart allocation on a tablet.
class StreamingStorage {
  HttpClient? _active;
  void cancel() {
    _active?.close(force: true);
    _active = null;
  }

  Future<void> upload(
    SupabaseClient client,
    String object,
    File file, {
    void Function(double)? onProgress,
  }) async {
    final sessionToken = client.accessToken != null
        ? await client.accessToken!()
        : client.auth.currentSession?.accessToken;
    if (sessionToken == null) {
      throw StateError('Masuk kembali untuk mengunggah.');
    }
    final base = Uri.parse(client.storage.url);
    final uri = base.replace(
      pathSegments: [
        ...base.pathSegments.where((s) => s.isNotEmpty),
        'object',
        'chat-media',
        ...object.split('/'),
      ],
    );
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    _active = http;
    try {
      final request = await http
          .postUrl(uri)
          .timeout(const Duration(seconds: 15));
      client.storage.headers.forEach(
        (key, value) => request.headers.set(key, value),
      );
      final apiKey = client.realtime.headers['apikey'];
      if (apiKey == null) {
        throw StateError('Konfigurasi upload tidak tersedia.');
      }
      request.headers.set('apikey', apiKey);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $sessionToken',
      );
      request.headers.contentType = ContentType('application', 'octet-stream');
      request.headers.set('x-upsert', 'false');
      request.contentLength = await file.length();
      var sent = 0, percent = -1;
      await request
          .addStream(
            file.openRead().map((bytes) {
              sent += bytes.length;
              final next = (100 * sent / request.contentLength).floor();
              if (next != percent) {
                percent = next;
                onProgress?.call(sent / request.contentLength);
              }
              return bytes;
            }),
          )
          .timeout(const Duration(minutes: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      var body = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        if (body.length < 8192) body += chunk;
      }
      if (response.statusCode == 200 || response.statusCode == 201) return;
      final duplicate =
          response.statusCode == 409 ||
          (response.statusCode == 400 && body.contains('Duplicate'));
      if (duplicate) {
        return; // Retry after a lost upload response, same opaque object.
      }
      throw StorageException(
        'Upload belum dapat diselesaikan.',
        statusCode: response.statusCode.toString(),
      );
    } finally {
      http.close(force: true);
      if (identical(_active, http)) _active = null;
    }
  }
}
