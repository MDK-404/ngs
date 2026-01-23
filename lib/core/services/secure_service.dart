import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecureService {
  final _storage = const FlutterSecureStorage();

  String hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> savePin(String key, String pin) async {
    final hashedPin = hashPin(pin);
    await _storage.write(key: key, value: hashedPin);
  }

  Future<String?> getPinHash(String key) async {
    return await _storage.read(key: key);
  }

  Future<bool> verifyPin(String key, String enteredPin) async {
    final storedHash = await getPinHash(key);
    if (storedHash == null) return false;
    return storedHash == hashPin(enteredPin);
  }

  Future<void> clearAuth() async {
    await _storage.delete(key: 'login_pin_hash');
    await _storage.delete(key: 'edit_pin_hash');
  }
}
