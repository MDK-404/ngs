import 'package:get/get.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:ngs_recordbook/core/database/database_service.dart';
import '../models/record_model.dart';
import '../../forms/models/form_model.dart';
import '../utils/formula_engine.dart';

class RecordController extends GetxController {
  final FormModel form;
  final RxList<RecordModel> records = <RecordModel>[].obs;
  final RxBool isLoading = false.obs;

  late PlutoGridStateManager stateManager;

  RecordController(this.form);

  @override
  void onInit() {
    super.onInit();
    loadRecords();
  }

  Future<void> loadRecords() async {
    try {
      isLoading.value = true;
      final db = await DatabaseService.database;
      print('Loading records for form ${form.id}...');

      final List<Map<String, dynamic>> maps = await db.query(
        'form_records',
        where: 'form_id = ?',
        whereArgs: [form.id],
      );

      records.value = maps.map((m) => RecordModel.fromMap(m)).toList();
      print('Loaded ${records.length} records');
    } catch (e) {
      print('Error loading records: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> addColumn(ColumnModel col) async {
    final db = await DatabaseService.database;
    await db.insert('form_columns', {
      'form_id': col.formId,
      'name': col.name,
      'type': col.type.name,
      'formula': col.formula,
    });
    // We would ideally need to migrate existing records json structure if we were enforcing schema there,
    // but since it's loose JSON, existing records just won't have this key until edited.
    // However, for PlutoGrid to show it, the model is updated in memory in the View.
  }

  Future<void> saveRecord(Map<String, dynamic> data) async {
    final db = await DatabaseService.database;
    if (form.id == null) return;
    final record = RecordModel(formId: form.id!, data: data);
    await db.insert('form_records', record.toMap());
    await loadRecords();
  }

  Future<void> updateRecord(int id, Map<String, dynamic> data) async {
    final db = await DatabaseService.database;
    final record = RecordModel(id: id, formId: form.id!, data: data);
    await db.update(
      'form_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
    await loadRecords();
  }

  Future<void> deleteRecord(int id) async {
    final db = await DatabaseService.database;
    await db.delete('form_records', where: 'id = ?', whereArgs: [id]);
    await loadRecords();
  }

  void recalculateFormulas(PlutoRow row) {
    final formulaColumns = form.columns
        .where((c) => c.type == ColumnType.formula)
        .toList();
    if (formulaColumns.isEmpty) return;

    final values = <String, double>{};
    for (var col in form.columns) {
      if (col.type == ColumnType.number) {
        final val = row.cells[col.name]?.value;
        values[col.name.replaceAll(' ', '_')] =
            double.tryParse(val?.toString() ?? '0') ?? 0.0;
      }
    }

    for (var fCol in formulaColumns) {
      if (fCol.formula != null) {
        // Adjust formula for underscored variables
        String adjustedFormula = fCol.formula!;
        values.keys.forEach((key) {
          adjustedFormula = adjustedFormula.replaceAll(
            key.replaceAll('_', ' '),
            key,
          );
        });

        final result = FormulaEngine.evaluate(adjustedFormula, values);
        stateManager.changeCellValue(
          row.cells[fCol.name]!,
          result.toStringAsFixed(2),
          force: true,
        );
      }
    }
  }
}
