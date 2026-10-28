import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:adoetz_chat/core/media_service.dart';

void main() {
  test(
    'large attachments round-trip in bounded authenticated chunks; corruption and truncation fail closed',
    () async {
      final dir = await Directory.systemTemp.createTemp('adoetz-media-test-');
      try {
        final input = File('${dir.path}/input'),
            cipher = File('${dir.path}/cipher'),
            output = File('${dir.path}/output');
        final bytes = List<int>.generate(
          MediaCipher.chunkSize + 73,
          (i) => i % 251,
        );
        await input.writeAsBytes(bytes);
        final metadata = await MediaCipher.encrypt(
          input,
          cipher,
          'room/alice/object',
        );
        await MediaCipher.decrypt(cipher, output, metadata);
        expect(await output.readAsBytes(), bytes);
        await output.delete();
        final packed = await cipher.readAsBytes();
        packed[100] ^= 1;
        await cipher.writeAsBytes(packed);
        await expectLater(
          MediaCipher.decrypt(cipher, output, metadata),
          throwsStateError,
        );
        // Even if an attacker forges the outer digest, the AEAD tag is mandatory.
        final changed = {
          ...metadata,
          'sha256': base64Encode((await Sha256().hash(packed)).bytes),
        };
        await expectLater(
          MediaCipher.decrypt(cipher, output, changed),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
        expect(await output.exists(), isFalse);
        await cipher.writeAsBytes(packed.sublist(0, packed.length - 1));
        await expectLater(
          MediaCipher.decrypt(cipher, output, metadata),
          throwsStateError,
        );
      } finally {
        for (final file in dir.listSync()) {
          await file.delete();
        }
        await dir.delete();
      }
    },
  );
}
