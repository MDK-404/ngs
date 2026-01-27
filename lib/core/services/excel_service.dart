import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:ngs_recordbook/features/forms/models/form_model.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

class ExcelService {
  /// Reads an Excel file using SpreadsheetDecoder
  static SpreadsheetDecoder? decodeFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        print('File not found: $path');
        return null;
      }
      final bytes = file.readAsBytesSync();
      return SpreadsheetDecoder.decodeBytes(bytes);
    } catch (e) {
      print('Error decoding Excel: $e');
      return null;
    }
  }

  /// Returns a list of sheet names
  static List<String> getSheetNames(SpreadsheetDecoder decoder) {
    return decoder.tables.keys.toList();
  }

  /// Validates headers and extracts data (legacy fixed columns)
  static List<Map<String, dynamic>> parseSheetData({
    required SpreadsheetDecoder decoder,
    required String sheetName,
    required List<ColumnModel> formColumns,
  }) {
    final table = decoder.tables[sheetName];
    if (table == null) throw 'Sheet not found';
    if (table.rows.isEmpty) throw 'Sheet is empty';

    final rows = table.rows;
    // Header is first row
    final headerRow = rows.first;

    // Header Map
    final headerMap = <String, int>{};
    for (int i = 0; i < headerRow.length; i++) {
      final val = headerRow[i]?.toString().trim().toLowerCase();
      if (val != null && val.isNotEmpty) {
        headerMap[val] = i;
      }
    }

    // Verify
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

        final val = row[colIndex];
        if (val != null && val.toString().isNotEmpty) {
          hasData = true;
          // Basic type conversion if needed, SpreadsheetDecoder returns generic types
          // Dates might be strings or numbers? SpreadsheetDecoder usually handles dates if configured?
          // Actually defaults to serial or string.
          // Let's assume generic usage.
          rowData[colDef.name] = val;
        }
      }
      if (hasData) parsedData.add(rowData);
    }
    return parsedData;
  }

  /// Infers columns and reads data from a sheet
  /// Handles "title rows" by scanning for the row with the most columns.
  /// Handles empty header gaps and duplicate header names efficiently.
  static Map<String, dynamic> inferSheetData({
    required SpreadsheetDecoder decoder,
    required String sheetName,
  }) {
    final table = decoder.tables[sheetName];
    if (table == null) throw 'Sheet not found';
    if (table.rows.isEmpty)
      return {'headers': <String>[], 'data': <Map<String, dynamic>>[]};

    final rows = table.rows;

    // 1. Smart Header Detection
    // Scan first 50 rows to find the one with the most data (likely the header)
    int headerRowIndex = 0;
    int maxNonEmpty = -1;

    final scanLimit = rows.length < 50 ? rows.length : 50;

    for (int i = 0; i < scanLimit; i++) {
      int count = 0;
      for (var cell in rows[i]) {
        if (cell != null && cell.toString().trim().isNotEmpty) {
          count++;
        }
      }
      // We prefer the first row that hits the max count (top-most candidate),
      // but strict > ensures we upgrade if we find WIDER row.
      // If header is row 4 (10 cols) and row 2 is title (1 col), row 4 wins.
      if (count > maxNonEmpty) {
        maxNonEmpty = count;
        headerRowIndex = i;
      }
    }

    // If no data found at all
    if (maxNonEmpty <= 0) {
      return {'headers': <String>[], 'data': <Map<String, dynamic>>[]};
    }

    final headerRow = rows[headerRowIndex];

    // Map of Final Header Name -> Actual Column Index
    final headerIndices = <String, int>{};
    final headers = <String>[];
    // Set to track duplicates for checking
    final seenHeaders = <String>{};

    for (int i = 0; i < headerRow.length; i++) {
      final cell = headerRow[i];
      if (cell != null && cell.toString().trim().isNotEmpty) {
        String name = cell.toString().trim();

        // Handle Duplicate Names
        String originalName = name;
        int dupCount = 2;
        while (seenHeaders.contains(name)) {
          name = '$originalName $dupCount';
          dupCount++;
        }

        seenHeaders.add(name);
        headers.add(name);
        headerIndices[name] = i;
      }
    }

    if (headers.isEmpty)
      return {'headers': <String>[], 'data': <Map<String, dynamic>>[]};

    final data = <Map<String, dynamic>>[];
    for (int i = headerRowIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      final rowMap = <String, dynamic>{};
      bool hasData = false;

      // We iterate through our identified headers to pull data from correct indices
      for (var h in headers) {
        final colIndex = headerIndices[h]!;

        if (colIndex < row.length) {
          final val = row[colIndex];
          if (val != null && val.toString().isNotEmpty) {
            rowMap[h] = val;
            hasData = true;
          }
        }
      }

      if (hasData) data.add(rowMap);
    }

    return {'headers': headers, 'data': data};
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
