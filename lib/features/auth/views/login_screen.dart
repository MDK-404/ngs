import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../../dashboard/views/dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthController _authController = Get.find<AuthController>();
  final TextEditingController _pinController = TextEditingController();
  final RxString _error = ''.obs;

  void _handleLogin() async {
    if (_pinController.text.isEmpty) {
      _error.value = 'Please enter your PIN';
      return;
    }

    final success = await _authController.login(_pinController.text);
    if (success) {
      Get.offAll(() => const DashboardScreen());
    } else {
      _error.value = 'Invalid PIN. Try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.primaryContainer,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Obx(
                      () => Text(
                        _authController.storeName.value,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Offline Desktop Application',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),
                    Obx(
                      () => Text(
                        'Welcome back, ${_authController.username.value}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _pinController,
                      decoration: const InputDecoration(
                        labelText: 'Enter 4-6 Digit PIN',
                        prefixIcon: Icon(Icons.lock_outline),
                        counterText: '',
                      ),
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      onSubmitted: (_) => _handleLogin(),
                    ),
                    Obx(
                      () => _error.value.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _error.value,
                                style: const TextStyle(color: Colors.red),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleLogin,
                        child: const Text('LOGIN'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
