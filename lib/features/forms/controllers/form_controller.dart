import 'package:get/get.dart';
import 'package:ngs_recordbook/core/database/database_service.dart';
import '../models/form_model.dart';

class FormController extends GetxController {
  final RxList<FormModel> forms = <FormModel>[].obs;
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadForms();
  }

  Future<void> loadForms() async {
    try {
      isLoading.value = true;
      final db = await DatabaseService.database;
      print('Loading forms...');

      final List<Map<String, dynamic>> formMaps = await db.query('forms');
      final List<FormModel> loadedForms = [];

      for (var formMap in formMaps) {
        final List<Map<String, dynamic>> columnMaps = await db.query(
          'form_columns',
          where: 'form_id = ?',
          whereArgs: [formMap['id']],
        );

        final columns = columnMaps.map((c) => ColumnModel.fromMap(c)).toList();
        loadedForms.add(FormModel.fromMap(formMap, columns: columns));
      }

      forms.value = loadedForms;
      print('Forms loaded: ${forms.length}');
    } catch (e) {
      print('Error loading forms: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<int> createForm(String name, List<ColumnModel> columns) async {
    final db = await DatabaseService.database;

    int formId = -1;

    await db.transaction((txn) async {
      formId = await txn.insert('forms', {'name': name});

      for (var col in columns) {
        final isHidden =
            col.isHidden || col.name.toLowerCase().contains('purchase');
        await txn.insert('form_columns', {
          'form_id': formId,
          'name': col.name,
          'type': col.type.name,
          'formula': col.formula,
          'is_hidden': isHidden ? 1 : 0,
        });
      }
    });

    await loadForms();
    print('Form created with ID: $formId');
    return formId;
  }

  Future<void> deleteForm(int formId) async {
    final db = await DatabaseService.database;
    await db.delete('forms', where: 'id = ?', whereArgs: [formId]);
    await loadForms();
  }
}
