import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Password-protected transport envelope for a complete v3 media snapshot.
/// Decrypted bytes are never exported by the backup screen.
class LocalEncryptedBackup {
  const LocalEncryptedBackup._();

  static const format = 'agrico-encrypted-local';
  static const version = 1;
  static const iterations = 600000;
  static const _aad = 'agrico-encrypted-local-v1';

  static bool isEncrypted(Uint8List bytes) {
    try {
      final header = jsonDecode(utf8.decode(bytes));
      return header is Map<String, dynamic> && header['format'] == format;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List> encrypt(Uint8List plain, String password) async {
    if (password.runes.length < 12) {
      throw const FormatException('Backup password must have 12 characters.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final cipher = AesGcm.with256bits();
    final nonce = cipher.newNonce();
    final key = await _derive(password, salt);
    final box = await cipher.encrypt(plain,
        secretKey: key, nonce: nonce, aad: utf8.encode(_aad));
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'format': format,
      'version': version,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'cipher': 'AES-256-GCM',
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    })));
  }

  static Future<Uint8List> decrypt(Uint8List bytes, String password) async {
    if (password.isEmpty) throw const BackupPasswordException();
    try {
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (root['format'] != format || root['version'] != version ||
          root['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          root['iterations'] != iterations || root['cipher'] != 'AES-256-GCM') {
        throw const FormatException('Unsupported encrypted backup.');
      }
      final salt = base64Decode(root['salt'] as String);
      final nonce = base64Decode(root['nonce'] as String);
      final mac = base64Decode(root['mac'] as String);
      final cipherText = base64Decode(root['cipherText'] as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException('Invalid encrypted backup parameters.');
      }
      final key = await _derive(password, salt);
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(_aad),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const BackupPasswordException();
    }
  }

  static Future<SecretKey> _derive(String password, List<int> salt) =>
      Pbkdf2.hmacSha256(iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);
}

class BackupPasswordException implements Exception {
  const BackupPasswordException();
}
