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
  }

  Future<void> deleteColumn(String colName) async {
    final db = await DatabaseService.database;
    await db.delete(
      'form_columns',
      where: 'form_id = ? AND name = ?',
      whereArgs: [form.id, colName],
    );
    // Optional: Iterate records and remove key, but not strictly necessary for display
  }

  Future<void> updateColumn(String oldName, ColumnModel newCol) async {
    final db = await DatabaseService.database;

    // Update definition
    await db.update(
      'form_columns',
      {
        'name': newCol.name,
        'type': newCol.type.name,
        'formula': newCol.formula,
      },
      where: 'form_id = ? AND name = ?',
      whereArgs: [form.id, oldName],
    );

    // If name changed, we MUST update all records data keys
    if (oldName != newCol.name) {
      for (var record in records) {
        if (record.data.containsKey(oldName)) {
          final val = record.data[oldName];
          record.data[newCol.name] = val;
          record.data.remove(oldName);
          // Update in DB
          await updateRecord(record.id!, record.data);
        }
      }
    }
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

  void recalculateAllRows() {
    if (stateManager.rows.isEmpty) return;
    for (var row in stateManager.rows) {
      recalculateFormulas(row);
    }
  }

  void recalculateFormulas(PlutoRow row) {
    // 1. Prepare values map and name mapping
    final values = <String, double>{};
    final nameMapping = <String, String>{};

    for (var col in form.columns) {
      if (col.type == ColumnType.number) {
        final val = row.cells[col.name]?.value;
        // Normalized key: remove spaces, use underscore
        final key = col.name.trim().replaceAll(RegExp(r'\s+'), '_');
        final doubleVal = double.tryParse(val?.toString() ?? '0') ?? 0.0;

        values[key] = doubleVal;

        // Map original name (lowercase) to normalized key
        nameMapping[col.name.trim().toLowerCase()] = key;
      }
    }

    final formulaColumns = form.columns
        .where((c) => c.type == ColumnType.formula)
        .toList();

    for (var fCol in formulaColumns) {
      if (fCol.formula != null && fCol.formula!.isNotEmpty) {
        String currentFormula = fCol.formula!;

        // Sort names by length descending to match longest variables first
        final sortedOriginalNames = nameMapping.keys.toList()
          ..sort((a, b) => b.length.compareTo(a.length));

        for (var lowerName in sortedOriginalNames) {
          final normalizedKey = nameMapping[lowerName]!;

          // Case-insensitive replacement
          final pattern = RegExp(
            RegExp.escape(lowerName),
            caseSensitive: false,
          );
          currentFormula = currentFormula.replaceAll(pattern, normalizedKey);
        }

        print(
          'Formula Evaluation: ${fCol.formula} -> $currentFormula | Values: $values',
        );

        final result = FormulaEngine.evaluate(currentFormula, values);

        if (row.cells.containsKey(fCol.name)) {
          final finalVal = result.isFinite ? result.toStringAsFixed(2) : '0.00';

          if (row.cells[fCol.name]!.value.toString() != finalVal) {
            stateManager.changeCellValue(
              row.cells[fCol.name]!,
              finalVal,
              force: true,
              callOnChangedEvent: false,
            );
          }
        }
      }
    }
  }
}
