import 'package:get/get.dart';
import 'package:ngs_recordbook/core/services/secure_service.dart';
import 'package:ngs_recordbook/core/database/database_service.dart';

class AuthController extends GetxController {
  final SecureService _secureService = SecureService();

  final RxString storeName = 'Noor Grocery Store'.obs;
  final RxString username = 'admin'.obs;
  final RxBool isLoggedIn = false.obs;
  final RxBool isSeparatePinEnabled = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final db = await DatabaseService.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'settings',
      where: 'id = ?',
      whereArgs: [1],
    );

    if (maps.isNotEmpty) {
      storeName.value = maps[0]['store_name'] ?? 'Noor Grocery Store';
      username.value = maps[0]['username'] ?? 'admin';
      isSeparatePinEnabled.value = maps[0]['is_separate_pin_enabled'] == 1;
    }
  }

  Future<bool> login(String pin) async {
    // Check database/secure storage for PIN
    final storedHash = await _secureService.getPinHash('login_pin_hash');

    // For first time setup, if no PIN is set, allow any 4-6 digit PIN and save it
    if (storedHash == null) {
      if (pin.length >= 4 && pin.length <= 6) {
        await _secureService.savePin('login_pin_hash', pin);
        await _secureService.savePin(
          'edit_pin_hash',
          pin,
        ); // Default same for edit
        isLoggedIn.value = true;
        return true;
      }
      return false;
    }

    final isValid = await _secureService.verifyPin('login_pin_hash', pin);
    if (isValid) {
      isLoggedIn.value = true;
    }
    return isValid;
  }

  Future<bool> verifyEditAction(String pin) async {
    final key = isSeparatePinEnabled.value ? 'edit_pin_hash' : 'login_pin_hash';
    return await _secureService.verifyPin(key, pin);
  }

  void logout() {
    isLoggedIn.value = false;
  }

  Future<void> updateSettings({
    String? newStoreName,
    String? newUsername,
    bool? separatePin,
  }) async {
    final db = await DatabaseService.database;
    final Map<String, dynamic> values = {};
    if (newStoreName != null) values['store_name'] = newStoreName;
    if (newUsername != null) values['username'] = newUsername;
    if (separatePin != null)
      values['is_separate_pin_enabled'] = separatePin ? 1 : 0;

    if (values.isNotEmpty) {
      await db.update('settings', values, where: 'id = ?', whereArgs: [1]);
      _loadSettings();
    }
  }

  Future<void> changePin(String type, String newPin) async {
    final key = type == 'login' ? 'login_pin_hash' : 'edit_pin_hash';
    await _secureService.savePin(key, newPin);
  }
}
