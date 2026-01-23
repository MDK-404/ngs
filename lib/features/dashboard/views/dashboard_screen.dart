import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../forms/controllers/form_controller.dart';
import '../../forms/views/form_builder_screen.dart';
import '../../records/views/record_grid_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();
    final formController = Get.find<FormController>();

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 260,
            color: Theme.of(
              context,
            ).colorScheme.surfaceVariant.withOpacity(0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Obx(
                        () => Text(
                          authController.storeName.value,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const Text(
                        'RECORDS SYSTEM',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('Dashboard'),
                  selected: true,
                  onTap: () {},
                ),
                ListTile(
                  leading: const Icon(Icons.add_box_outlined),
                  title: const Text('Create New Form'),
                  onTap: () => Get.to(() => const FormBuilderScreen()),
                ),
                const Spacer(),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () {
                    // TODO: Settings Screen
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: () {
                    authController.logout();
                    Get.offAllNamed('/');
                  },
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Offline Mode Enabled',
                    style: TextStyle(fontSize: 10, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Dynamic Forms',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      ElevatedButton.icon(
                        onPressed: () =>
                            Get.to(() => const FormBuilderScreen()),
                        icon: const Icon(Icons.add),
                        label: const Text('NEW FORM'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: Obx(() {
                      if (formController.isLoading.value) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (formController.forms.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.note_add_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No forms created yet. Start by creating one!',
                              ),
                            ],
                          ),
                        );
                      }
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1.5,
                            ),
                        itemCount: formController.forms.length,
                        itemBuilder: (context, index) {
                          final form = formController.forms[index];
                          return Card(
                            child: InkWell(
                              onTap: () {
                                Get.to(() => RecordGridScreen(form: form));
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      form.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const Spacer(),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          '${form.columns.length} Columns',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.red,
                                          ),
                                          onPressed: () {
                                            Get.defaultDialog(
                                              title: 'Delete Form?',
                                              middleText:
                                                  'This will delete "${form.name}" and all its records permanently.',
                                              textConfirm: 'DELETE',
                                              textCancel: 'CANCEL',
                                              confirmTextColor: Colors.white,
                                              buttonColor: Colors.red,
                                              onConfirm: () async {
                                                Get.back(); // Close confirmation
                                                // Ask for PIN
                                                final pinController =
                                                    TextEditingController();
                                                final result = await Get.dialog<bool>(
                                                  AlertDialog(
                                                    title: const Text(
                                                      'Enter PIN to Delete',
                                                    ),
                                                    content: TextField(
                                                      controller: pinController,
                                                      obscureText: true,
                                                      decoration:
                                                          const InputDecoration(
                                                            labelText: 'PIN',
                                                          ),
                                                      keyboardType:
                                                          TextInputType.number,
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Get.back(
                                                              result: false,
                                                            ),
                                                        child: const Text(
                                                          'CANCEL',
                                                        ),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () async {
                                                          final isValid =
                                                              await authController
                                                                  .verifyEditAction(
                                                                    pinController
                                                                        .text,
                                                                  );
                                                          Get.back(
                                                            result: isValid,
                                                          );
                                                        },
                                                        child: const Text(
                                                          'VERIFY',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );

                                                if (result == true) {
                                                  await formController
                                                      .deleteForm(form.id!);
                                                  Get.snackbar(
                                                    'Success',
                                                    'Form deleted successfully',
                                                  );
                                                } else if (result == false) {
                                                  Get.snackbar(
                                                    'Error',
                                                    'Invalid PIN',
                                                    backgroundColor: Colors.red,
                                                    colorText: Colors.white,
                                                  );
                                                }
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
