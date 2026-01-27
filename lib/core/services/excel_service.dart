import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:ngs_recordbook/features/forms/models/form_model.dart';
import 'package:path/path.dart';

class ExcelService {
  /// Reads an Excel file
  static Future<Excel?> readFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        print('File does not exist at path: $path');
        return null;
      }
      var bytes = await file.readAsBytes();
      var excel = Excel.decodeBytes(bytes);
      return excel;
    } catch (e) {
      print('Error reading Excel file: $e');
      return null;
    }
  }

  /// Returns a list of sheet names
  static List<String> getSheetNames(Excel excel) {
    return excel.tables.keys.toList();
  }

  /// Validates headers and extracts data
  static List<Map<String, dynamic>> parseSheetData({
    required Excel excel,
    required String sheetName,
    required List<ColumnModel> formColumns,
  }) {
    final table = excel.tables[sheetName];
    if (table == null) throw 'Sheet not found';

    if (table.maxRows == 0) throw 'Sheet is empty';

    final rows = table.rows;
    if (rows.isEmpty) throw 'Sheet is empty';

    // Find Header Row (first non-empty row)
    final headerRow = rows.first;

    // Create Header Map: Lowercase Name -> Column Index
    final headerMap = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final val = _getCellValue(headerRow[i]?.value);
      if (val != null) {
        final h = val.toString().trim().toLowerCase();
        if (h.isNotEmpty) {
          headerMap[h] = i;
        }
      }
    }

    // Verify columns
    for (var col in formColumns) {
      if (!headerMap.containsKey(col.name.toLowerCase())) {
        throw 'Missing column in Excel: "${col.name}"';
      }
    }

    final parsedData = <Map<String, dynamic>>[];

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      final rowData = <String, dynamic>{};
      bool hasData = false;

      for (var colDef in formColumns) {
        if (colDef.type == ColumnType.formula) continue;

        final colIndex = headerMap[colDef.name.toLowerCase()]!;

        if (colIndex >= row.length) continue;

        final cellValueObj = row[colIndex]?.value;

        // Check for FormulaCellValue via type check if available
        if (cellValueObj is FormulaCellValue) {
          rowData[colDef.name] = '####';
          hasData = true;
          continue;
        }

        final val = _getCellValue(cellValueObj);

        if (val != null && val.toString().isNotEmpty) {
          hasData = true;

          if (colDef.type == ColumnType.number) {
            if (val is num) {
              rowData[colDef.name] = val;
            } else {
              String valStr = val.toString();
              if (valStr.startsWith('=')) {
                rowData[colDef.name] = '####';
              } else {
                valStr = valStr.replaceAll(',', '');
                valStr = valStr.replaceAll(RegExp(r'[^0-9.\-]'), '');
                rowData[colDef.name] = double.tryParse(valStr) ?? 0.0;
              }
            }
          } else if (colDef.type == ColumnType.date) {
            if (val is num) {
              // Serial date
              final double dVal = val.toDouble();
              final date = DateTime(
                1900,
                1,
                1,
              ).add(Duration(milliseconds: ((dVal - 2) * 86400000).round()));
              rowData[colDef.name] = date.toIso8601String();
            } else {
              final str = val.toString();
              if (str.startsWith('=')) {
                rowData[colDef.name] = '####';
              } else {
                rowData[colDef.name] = str;
              }
            }
          } else {
            // Text
            final str = val.toString();
            if (str.startsWith('=')) {
              rowData[colDef.name] = '####';
            } else {
              rowData[colDef.name] = str;
            }
          }
        }
      }

      if (hasData) {
        parsedData.add(rowData);
      }
    }

    return parsedData;
  }

  static dynamic _getCellValue(CellValue? cellValue) {
    if (cellValue == null) return null;
    if (cellValue is TextCellValue) return cellValue.value;
    if (cellValue is IntCellValue) return cellValue.value;
    if (cellValue is DoubleCellValue) return cellValue.value;
    if (cellValue is DateCellValue) return cellValue.asDateTimeLocal;
    // Fallback
    return cellValue.toString();
  }

  /// Exports data to an Excel file
  static Future<List<int>?> exportToExcel({
    required String sheetName,
    required List<String> headers,
    required List<List<dynamic>> data,
  }) async {
    try {
      final excel = Excel.createExcel();
      // Rename default sheet
      final defaultSheet = excel.sheets.keys.first;
      excel.rename(defaultSheet, sheetName);

      final sheet = excel[sheetName];

      // Add Headers
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      // Add Data
      for (final row in data) {
        final excelRow = row.map<CellValue>((cell) {
          if (cell == null) return TextCellValue('');
          if (cell is num) {
            return DoubleCellValue(cell.toDouble());
          }
          if (cell is DateTime) {
            // Excel dates are sometimes tricky, string is safer for now unless needed
            return TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(cell));
          }
          return TextCellValue(cell.toString());
        }).toList();
        sheet.appendRow(excelRow);
      }

      return excel.encode();
    } catch (e) {
      print('Error exporting Excel: $e');
      return null;
    }
  }
}
