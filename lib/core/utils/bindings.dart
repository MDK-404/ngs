import 'package:get/get.dart';
import 'package:ngs_recordbook/features/auth/controllers/auth_controller.dart';
import 'package:ngs_recordbook/features/forms/controllers/form_controller.dart';

class GlobalBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(AuthController(), permanent: true);
    Get.lazyPut(() => FormController(), fenix: true);
  }
}
