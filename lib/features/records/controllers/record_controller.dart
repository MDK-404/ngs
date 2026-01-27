import 'package:get/get.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:ngs_recordbook/core/database/database_service.dart';
import '../models/record_model.dart';
import '../../forms/models/form_model.dart';
import '../utils/formula_engine.dart';

class RecordController extends GetxController {
  final FormModel form;
  final RxList<RecordModel> records = <RecordModel>[].obs;
  final RxBool isLoading = true.obs; // Start loading effectively

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
      'is_hidden': col.isHidden ? 1 : 0,
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
        'is_hidden': newCol.isHidden ? 1 : 0,
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

  Future<void> batchDeleteRecords(List<int> ids) async {
    final db = await DatabaseService.database;
    final batch = db.batch();
    for (var id in ids) {
      batch.delete('form_records', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    await loadRecords();
  }

  void recalculateAllRows() {
    if (stateManager.rows.isEmpty) return;
    for (var row in stateManager.rows) {
      recalculateFormulas(row);
    }
  }

  void recalculateFormulas(PlutoRow row, {String? excludeColumn}) {
    int iterations = 0;
    bool changed = true;

    // Run up to 3 passes to resolve dependencies (e.g. Total -> Tax)
    // regardless of column order.
    while (changed && iterations < 3) {
      changed = false;
      iterations++;

      // Refresh values from current row state
      final values = _getRowValues(row);

      final formulaColumns = form.columns
          .where((c) => c.type == ColumnType.formula)
          .toList();

      for (var fCol in formulaColumns) {
        // Skip if this column was the one manually edited
        if (excludeColumn != null && fCol.name == excludeColumn) continue;

        if (fCol.formula != null && fCol.formula!.isNotEmpty) {
          final result = _evaluateExpression(fCol.formula!, values);
          if (result != null) {
            final finalVal = result.isFinite
                ? result.toStringAsFixed(2)
                : '0.00';
            if (row.cells.containsKey(fCol.name) &&
                row.cells[fCol.name]!.value.toString() != finalVal) {
              stateManager.changeCellValue(
                row.cells[fCol.name]!,
                finalVal,
                force: true,
                callOnChangedEvent: false,
              );
              changed = true;
            }
          }
        }
      }
    }
  }

  // Helper to parse cell input like "Price / 20"
  String evaluateCellInput(PlutoRow row, String colName, String input) {
    if (input.isEmpty) return input;

    // Check if it looks like a formula (contains operators or starts with =)
    if (!input.contains(RegExp(r'[+\-*/=]'))) return input;

    String expression = input;
    if (expression.startsWith('=')) expression = expression.substring(1);

    final values = _getRowValues(row);
    final result = _evaluateExpression(expression, values);

    if (result != null && result.isFinite) {
      return result.toStringAsFixed(2);
    }

    return input;
  }

  Map<String, double> _getRowValues(PlutoRow row) {
    final values = <String, double>{};
    for (var col in form.columns) {
      if (col.type == ColumnType.number || col.type == ColumnType.formula) {
        final val = row.cells[col.name]?.value;
        // Normalized key: remove spaces, use underscore
        final key = col.name.trim().replaceAll(RegExp(r'\s+'), '_');
        final doubleVal = double.tryParse(val?.toString() ?? '0') ?? 0.0;
        values[key] = doubleVal;
      }
    }
    return values;
  }

  double? _evaluateExpression(String formula, Map<String, double> values) {
    // Name mapping for case-insensitive replacement
    final nameMapping = <String, String>{};
    for (var col in form.columns) {
      final key = col.name.trim().replaceAll(RegExp(r'\s+'), '_');
      nameMapping[col.name.trim().toLowerCase()] = key;
    }

    String currentFormula = formula;

    // Sort names by length descending
    final sortedOriginalNames = nameMapping.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (var lowerName in sortedOriginalNames) {
      final normalizedKey = nameMapping[lowerName]!;
      final pattern = RegExp(RegExp.escape(lowerName), caseSensitive: false);
      currentFormula = currentFormula.replaceAll(pattern, normalizedKey);
    }

    try {
      return FormulaEngine.evaluate(currentFormula, values);
    } catch (e) {
      return null;
    }
  }

  Future<void> batchImportRecords(
    List<Map<String, dynamic>> recordsData,
  ) async {
    final db = await DatabaseService.database;
    if (form.id == null) return;

    final batch = db.batch();
    for (var data in recordsData) {
      final record = RecordModel(formId: form.id!, data: data);
      batch.insert('form_records', record.toMap());
    }
    await batch.commit(noResult: true);
    await loadRecords();
  }
}
