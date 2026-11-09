import 'dart:convert';
import 'dart:typed_data';

import 'package:agrico_deepseek/core/backup/local_encrypted_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encrypted backup round trips and does not disclose plaintext', () async {
    final plain = Uint8List.fromList(utf8.encode(
        '{"parcel":"ບ້ານຕາໂກ","owner":"Nguyễn Văn A"}'));
    final first = await LocalEncryptedBackup.encrypt(
        plain, 'Một mật khẩu dài an toàn 2026');
    final second = await LocalEncryptedBackup.encrypt(
        plain, 'Một mật khẩu dài an toàn 2026');
    expect(LocalEncryptedBackup.isEncrypted(first), isTrue);
    expect(first, isNot(second));
    expect(utf8.decode(first), isNot(contains('Nguyễn Văn A')));
    expect(await LocalEncryptedBackup.decrypt(
        first, 'Một mật khẩu dài an toàn 2026'), plain);
  });

  test('incorrect password and modified encrypted bytes are rejected', () async {
    final plain = Uint8List.fromList(utf8.encode('private parcel'));
    final encrypted = await LocalEncryptedBackup.encrypt(
        plain, 'safe backup password 2026');
    await expectLater(
        LocalEncryptedBackup.decrypt(encrypted, 'wrong backup password'),
        throwsA(isA<BackupPasswordException>()));
    final envelope = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
    final cipher = base64Decode(envelope['cipherText'] as String);
    cipher[0] ^= 1;
    envelope['cipherText'] = base64Encode(cipher);
    await expectLater(
        LocalEncryptedBackup.decrypt(
          Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          'safe backup password 2026',
        ),
        throwsA(isA<BackupPasswordException>()));
  });

  test('short passwords are rejected before saving', () async {
    await expectLater(
        LocalEncryptedBackup.encrypt(Uint8List(1), 'short'),
        throwsFormatException);
  });
}
