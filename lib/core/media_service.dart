import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';
import 'package:device_runtime/device_runtime.dart';
import 'controller.dart';
import 'models.dart';

/// Independently authenticated, bounded chunks. The key, total length, object
/// binding and SHA-256 digest are sent only inside the Signal payload.
class MediaCipher {
  static const chunkSize = 1024 * 1024;
  static final _aes = AesGcm.with256bits();
  static Future<Map<String, dynamic>> encrypt(
    File input,
    File output,
    String object,
  ) async {
    final size = await input.length();
    if (size < 1 || size > 100 * 1024 * 1024) {
      throw StateError('Ukuran file tidak didukung.');
    }
    final key = await _aes.newSecretKey();
    final source = await input.open();
    final sink = await output.open(mode: FileMode.write);
    final digest = Sha256().newHashSink();
    try {
      var index = 0, offset = 0;
      while (offset < size) {
        final bytes = await source.read(min(chunkSize, size - offset));
        if (bytes.isEmpty) throw StateError('File berubah saat dibaca.');
        final box = await _aes.encrypt(
          bytes,
          secretKey: key,
          aad: utf8.encode('$object:$index:$size'),
        );
        final packed = box.concatenation();
        final length = ByteData(4)..setUint32(0, packed.length);
        await sink.writeFrom(length.buffer.asUint8List());
        await sink.writeFrom(packed);
        digest.add(length.buffer.asUint8List());
        digest.add(packed);
        index++;
        offset += bytes.length;
      }
      digest.close();
      return {
        'format': 'aes256gcm-chunks-v1',
        'object': object,
        'key': base64Encode(await key.extractBytes()),
        'size': size,
        'sha256': base64Encode((await digest.hash()).bytes),
      };
    } finally {
      await source.close();
      await sink.close();
    }
  }

  static Future<void> decrypt(
    File input,
    File output,
    Map<String, dynamic> metadata,
  ) async {
    if (metadata['format'] != 'aes256gcm-chunks-v1') {
      throw StateError('Format lampiran tidak didukung.');
    }
    final size = metadata['size'] as int;
    if (size < 1 ||
        size > 100 * 1024 * 1024 ||
        await input.length() > 110000000) {
      throw StateError('Lampiran terlalu besar.');
    }
    final digest = Sha256().newHashSink();
    await for (final bytes in input.openRead()) {
      digest.add(bytes);
    }
    digest.close();
    if (base64Encode((await digest.hash()).bytes) != metadata['sha256']) {
      throw StateError('Lampiran rusak.');
    }
    final source = await input.open();
    final sink = await output.open(mode: FileMode.write);
    var success = false;
    try {
      var index = 0, total = 0;
      while (total < size) {
        final header = await source.read(4);
        if (header.length != 4) throw StateError('Lampiran terpotong.');
        final count = ByteData.sublistView(header).getUint32(0);
        if (count < 29 || count > chunkSize + 28) {
          throw StateError('Ukuran blok tidak valid.');
        }
        final bytes = await source.read(count);
        if (bytes.length != count) throw StateError('Lampiran terpotong.');
        final plain = await _aes.decrypt(
          SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16),
          secretKey: SecretKey(base64Decode(metadata['key'])),
          aad: utf8.encode('${metadata['object']}:$index:$size'),
        );
        if (total + plain.length > size) {
          throw StateError('Ukuran file tidak valid.');
        }
        await sink.writeFrom(plain);
        total += plain.length;
        index++;
      }
      if ((await source.read(1)).isNotEmpty) {
        throw StateError('Data tambahan tidak valid.');
      }
      success = true;
    } finally {
      await source.close();
      await sink.close();
      if (!success && await output.exists()) await output.delete();
    }
  }
}

class MediaDownload {
  HttpClient? client;
  bool cancelled = false;
  void cancel() {
    cancelled = true;
    client?.close(force: true);
  }
}

class MediaService {
  static Future<String> mimeFor(File file, String name) async {
    final input = await file.open();
    try {
      return lookupMimeType(name, headerBytes: await input.read(64)) ??
          'application/octet-stream';
    } finally {
      await input.close();
    }
  }

  static Future<void> pick(
    ChatController c,
    Conversation chat,
    FileType type,
  ) async {
    final result = await FilePicker.pickFile(type: type);
    if (result == null || result.path == null) return;
    final file = result;
    await send(c, chat, File(file.path!), file.name);
  }

  static Future<void> send(
    ChatController c,
    Conversation chat,
    File file,
    String name, {
    bool voice = false,
    int? duration,
    String caption = '',
    bool asDocument = false,
  }) async {
    if (c.preview) throw StateError('Lampiran tersedia setelah masuk.');
    final mime = voice ? 'audio/mp4' : await mimeFor(file, name);
    final limit = mime.startsWith('video/')
        ? 100
        : mime.startsWith('image/')
        ? 15
        : 25;
    if (await file.length() > limit * 1024 * 1024) {
      throw StateError('Batas lampiran $limit MB.');
    }
    final object = '${chat.id}/${c.me!.id}/${const Uuid().v4()}';
    final cache = await getApplicationSupportDirectory();
    final encrypted = File('${cache.path}/${const Uuid().v4()}.adoetz');
    var queued = false;
    try {
      final data = await MediaCipher.encrypt(file, encrypted, object);
      data.addAll({
        'name': name.split(RegExp(r'[/\\]')).last,
        'mime': mime,
        'duration': ?duration,
        'caption': caption.trim(),
        'presentation': asDocument
            ? 'document'
            : mime.startsWith('image/')
            ? 'image'
            : mime.startsWith('video/')
            ? 'video'
            : 'document',
      });
      if (!voice &&
          !asDocument &&
          (mime.startsWith('image/') || mime.startsWith('video/'))) {
        try {
          data.addAll(await DeviceRuntime.mediaPreview(file.path, mime));
        } catch (_) {
          /* Unsupported thumbnail formats still allow file transport. */
        }
      }
      data['_upload_path'] = encrypted.path;
      // The durable message/outbox holds the authenticated metadata. Retrying
      // sending never needs access to the original picker URI or microphone file.
      await c.send(
        chat,
        voice ? 'Pesan suara' : name,
        kind: voice ? 'voice' : 'attachment',
        data: data,
        onCommitted: () => queued = true,
      );
    } finally {
      if (await encrypted.exists() && !queued) {
        await encrypted.delete();
      }
    }
  }

  static Future<File> download(
    ChatController c,
    ChatMessage message, {
    void Function(double)? onProgress,
    MediaDownload? transfer,
  }) async {
    final data = message.data;
    final object = data['object'] as String;
    if (!object.startsWith('${message.chatId}/${message.senderId}/')) {
      throw StateError('Lampiran tidak sesuai pengirim.');
    }
    final dir = await getTemporaryDirectory();
    final safeName = (data['name'] as String).replaceAll(
      RegExp(r'[^a-zA-Z0-9._ -]'),
      '_',
    );
    final requestId = const Uuid().v4();
    final out = File('${dir.path}/$requestId-$safeName');
    final cipher = File('${dir.path}/$requestId.download');
    var success = false;
    try {
      // An authenticated signed URL streams large files without buffering 100 MB.
      final url = await c.client!.storage
          .from('chat-media')
          .createSignedUrl(object, 60);
      final http = HttpClient();
      transfer?.client = http;
      try {
        if (transfer?.cancelled ?? false) {
          throw StateError('Unduhan dibatalkan.');
        }
        final response = await (await http.getUrl(Uri.parse(url))).close();
        if (response.statusCode != 200 || response.contentLength > 110000000) {
          throw StateError('Unduhan gagal.');
        }
        final writer = cipher.openWrite();
        var received = 0;
        var percent = -1;
        try {
          await for (final bytes in response) {
            received += bytes.length;
            if (received > 110000000) {
              throw StateError('Lampiran terlalu besar.');
            }
            writer.add(bytes);
            if (response.contentLength > 0) {
              final next = (received * 100 / response.contentLength).floor();
              if (next != percent) {
                percent = next;
                onProgress?.call(received / response.contentLength);
              }
            }
          }
        } finally {
          await writer.close();
        }
      } finally {
        http.close(force: true);
        if (transfer != null) transfer.client = null;
      }
      if (transfer?.cancelled ?? false) throw StateError('Unduhan dibatalkan.');
      await MediaCipher.decrypt(cipher, out, data);
      if (transfer?.cancelled ?? false) throw StateError('Unduhan dibatalkan.');
      success = true;
      return out;
    } finally {
      if (await cipher.exists()) await cipher.delete();
      if (!success && await out.exists()) await out.delete();
    }
  }

  static Future<void> avatar(ChatController c) async {
    final result = await FilePicker.pickFile(type: FileType.image);
    if (result == null || result.path == null || c.preview) return;
    final file = File(result.path!);
    final mime = _mime(result.name.toLowerCase());
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(mime) ||
        await file.length() > 5000000) {
      throw StateError('Pilih JPG, PNG, atau WebP maksimal 5 MB.');
    }
    final path = '${c.me!.id}/${const Uuid().v4()}';
    final old = c.me!.avatarPath;
    await c.client!.storage
        .from('avatars')
        .upload(path, file, fileOptions: FileOptions(contentType: mime));
    await c.setAvatar(path);
    if (old != null) {
      try {
        await c.client!.storage.from('avatars').remove([old]);
      } catch (_) {}
    }
  }

  static String _mime(String name) {
    return lookupMimeType(name) ?? 'application/octet-stream';
  }
}
