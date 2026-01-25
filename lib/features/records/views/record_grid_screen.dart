import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:ngs_recordbook/core/services/excel_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../forms/models/form_model.dart';
import '../controllers/record_controller.dart';
import '../../auth/controllers/auth_controller.dart';

class RecordGridScreen extends StatefulWidget {
  final FormModel form;
  const RecordGridScreen({super.key, required this.form});

  @override
  State<RecordGridScreen> createState() => _RecordGridScreenState();
}

class _RecordGridScreenState extends State<RecordGridScreen> {
  late final RecordController _controller;
  final AuthController _authController = Get.find<AuthController>();
  final TextEditingController _searchController = TextEditingController();
  bool _isEditing = false;
  bool _isDeleteMode = false;
  bool _gridInitialized = false;
  int _gridVersion = 0;

  @override
  void initState() {
    super.initState();
    _controller = Get.put(
      RecordController(widget.form),
      tag: widget.form.id.toString(),
    );
  }

  List<PlutoColumn> _buildColumns() {
    final seen = <String>{};
    final uniqueCols = widget.form.columns
        .where((col) => seen.add(col.name))
        .toList();

    final cols = uniqueCols.asMap().entries.map((entry) {
      final index = entry.key;
      final col = entry.value;

      PlutoColumnType type = PlutoColumnType.text();
      if (col.type == ColumnType.date) {
        type = PlutoColumnType.date();
      }
      // For number, we NOW use text() to allow entering formulas like "=500/2" or "Price/2"
      // PlutoColumnType.number() restricts to digits only.

      final isLocked = index == 0; // Lock the first user column

      // Parse colors
      Color? bgColor;
      Color? txtColor;
      if (col.backgroundColor != null) {
        bgColor = Color(
          int.parse(col.backgroundColor!.replaceFirst('#', '0xFF')),
        );
      }
      if (col.textColor != null) {
        txtColor = Color(int.parse(col.textColor!.replaceFirst('#', '0xFF')));
      }

      return PlutoColumn(
        title: col.name,
        field: col.name,
        type: type,
        readOnly: !_isEditing,
        enableEditingMode: _isEditing,
        frozen: isLocked ? PlutoColumnFrozen.start : PlutoColumnFrozen.none,
        enableColumnDrag: !isLocked,
        enableContextMenu: true, // Enable context menu
        backgroundColor:
            bgColor, // Header background? No, this might be mostly for decoration
        renderer: (rendererContext) {
          final cell = rendererContext.cell;
          final displayValue = rendererContext.column.formatter?.call(
            cell.value,
          );
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: bgColor, // Cell background
            width: double.infinity,
            height: double.infinity,
            child: Text(
              displayValue!,
              style: TextStyle(color: txtColor ?? Colors.black),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
        formatter: (value) {
          if (col.type == ColumnType.date && value.toString().isNotEmpty) {
            try {
              final date = DateTime.tryParse(value);
              if (date != null) {
                return DateFormat('dd MMM yyyy').format(date);
              }
            } catch (_) {}
          }
          return value.toString();
        },
      );
    }).toList();

    // Add Serial Number column at the beginning
    cols.insert(
      0,
      PlutoColumn(
        title: 'S.No',
        field: 'serial_no',
        type: PlutoColumnType.number(),
        readOnly: true,
        width: 70,
        enableRowChecked: _isDeleteMode,
        frozen: PlutoColumnFrozen.start,
        enableColumnDrag: false,
      ),
    );

    // Add hidden ID column
    cols.add(
      PlutoColumn(
        title: 'ID',
        field: '__id',
        type: PlutoColumnType.text(),
        readOnly: true,
        hide: true, // Hidden
        enableColumnDrag: false,
      ),
    );

    return cols;
  }

  List<PlutoRow> _buildRows() {
    return _controller.records.asMap().entries.map((entry) {
      final index = entry.key;
      final record = entry.value;

      final cells = widget.form.columns.asMap().map((i, col) {
        return MapEntry(
          col.name,
          PlutoCell(value: record.data[col.name] ?? ''),
        );
      });

      // Add ID
      cells['__id'] = PlutoCell(value: record.id.toString());

      // Add Serial No
      cells['serial_no'] = PlutoCell(value: (index + 1).toString());

      return PlutoRow(cells: cells);
    }).toList();
  }

  void _promptPinForEdit() async {
    final pinController = TextEditingController();
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Enter PIN to Edit'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'PIN'),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final isValid = await _authController.verifyEditAction(
                pinController.text,
              );
              Get.back(result: isValid);
            },
            child: const Text('VERIFY'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() {
        _isEditing = true;
      });
      Get.snackbar('Success', 'Edit mode enabled');
    } else if (result == false) {
      Get.snackbar(
        'Error',
        'Invalid PIN',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _saveChanges() async {
    // Force commit current edit
    if (_controller.stateManager.isEditing) {
      _controller.stateManager.setEditing(false);
    }
    FocusScope.of(context).unfocus();

    final rows = _controller.stateManager.rows;
    for (var row in rows) {
      final data = <String, dynamic>{};
      bool hasData = false;

      for (var col in widget.form.columns) {
        final val = row.cells[col.name]?.value;
        data[col.name] = val;
        if (val != null && val.toString().trim().isNotEmpty) {
          hasData = true;
        }
      }

      // Skip empty rows
      if (!hasData) continue;

      final idCell = row.cells['__id'];
      if (idCell != null &&
          idCell.value != null &&
          idCell.value.toString().isNotEmpty) {
        // Update existing
        final id = int.tryParse(idCell.value.toString());
        if (id != null) {
          await _controller.updateRecord(id, data);
        }
      } else {
        // Insert new
        await _controller.saveRecord(data);
      }
    }

    // Reload to refresh IDs
    await _controller.loadRecords();

    setState(() {
      _isEditing = false;
    });
    Get.snackbar('Success', 'Records saved successfully');
  }

  void _showAddColumnDialog() async {
    final nameController = TextEditingController();
    final formulaController = TextEditingController();
    ColumnType selectedType = ColumnType.text;

    await Get.dialog(
      AlertDialog(
        title: const Text('Add New Column'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Column Name'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ColumnType>(
                    value: selectedType,
                    items: ColumnType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(type.name.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedType = val);
                    },
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  if (selectedType == ColumnType.formula) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Formula:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextField(
                      controller: formulaController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Purchase Price / 2',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Type numbers (e.g. / 100) or select variables:',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...widget.form.columns
                            .where((c) => c.type == ColumnType.number)
                            .map(
                              (c) => ActionChip(
                                label: Text(c.name),
                                onPressed: () {
                                  final text = formulaController.text;
                                  final selection = formulaController.selection;
                                  final newText = text.replaceRange(
                                    selection.start >= 0
                                        ? selection.start
                                        : text.length,
                                    selection.end >= 0
                                        ? selection.end
                                        : text.length,
                                    ' ${c.name} ',
                                  );
                                  formulaController.text = newText;
                                },
                              ),
                            ),
                        ActionChip(
                          label: const Text('/'),
                          onPressed: () {
                            formulaController.text += ' / ';
                          },
                        ),
                        ActionChip(
                          label: const Text('*'),
                          onPressed: () {
                            formulaController.text += ' * ';
                          },
                        ),
                        ActionChip(
                          label: const Text('+'),
                          onPressed: () {
                            formulaController.text += ' + ';
                          },
                        ),
                        ActionChip(
                          label: const Text('-'),
                          onPressed: () {
                            formulaController.text += ' - ';
                          },
                        ),
                        ActionChip(
                          label: const Text('('),
                          onPressed: () {
                            formulaController.text += ' ( ';
                          },
                        ),
                        ActionChip(
                          label: const Text(')'),
                          onPressed: () {
                            formulaController.text += ' ) ';
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                if (widget.form.columns.any(
                  (c) => c.name == nameController.text,
                )) {
                  Get.snackbar(
                    'Error',
                    'Column "${nameController.text}" already exists',
                  );
                  return;
                }

                String? formula;
                if (selectedType == ColumnType.formula) {
                  if (formulaController.text.isEmpty) {
                    Get.snackbar('Error', 'Please enter a formula');
                    return;
                  }
                  formula = formulaController.text;
                }

                // Add column to form model
                final newCol = ColumnModel(
                  formId: widget.form.id,
                  name: nameController.text,
                  type: selectedType,
                  formula: formula,
                );

                await _controller.addColumn(newCol);

                setState(() {
                  widget.form.columns.add(newCol);
                  _gridVersion++; // Force rebuild
                });

                // Trigger formula update
                // Give a small delay for PlutoGrid to rebuild with new column
                Future.delayed(const Duration(milliseconds: 300), () {
                  _controller.recalculateAllRows();
                });

                Get.back();
              }
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }

  void _showManageColumnsDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('Manage Columns'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.lock, color: Colors.grey),
                title: Text('S.No'),
                subtitle: Text('NUMBER (System)'),
              ),
              const Divider(),
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setDtState) {
                    return ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: widget.form.columns.length,
                      onReorder: (oldIndex, newIndex) {
                        // Prevent moving the first column (Item column)
                        if (oldIndex == 0) return;

                        // Prevent moving content to the first position
                        if (newIndex <= 0) newIndex = 1;

                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }

                        setState(() {
                          final item = widget.form.columns.removeAt(oldIndex);
                          widget.form.columns.insert(newIndex, item);
                          _gridVersion++; // Force grid rebuild
                        });
                        setDtState(() {});
                      },
                      itemBuilder: (context, index) {
                        final col = widget.form.columns[index];
                        final isLocked = index == 0; // Lock first column

                        return ListTile(
                          key: ValueKey(col.name),
                          title: Text(col.name),
                          subtitle: Text(col.type.name.toUpperCase()),
                          leading: isLocked
                              ? const Icon(Icons.lock, color: Colors.grey)
                              : ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle),
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.palette,
                                  color: Colors.orange,
                                ),
                                onPressed: () async {
                                  await _showColumnStyleDialog(col);
                                  setDtState(() {});
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () async {
                                  await _showEditColumnDialog(col);
                                  setDtState(() {}); // Refresh list
                                },
                              ),
                              if (!isLocked)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    Get.defaultDialog(
                                      title: 'Delete Column',
                                      middleText:
                                          'Delete "${col.name}"? This cannot be undone.',
                                      textConfirm: 'DELETE',
                                      confirmTextColor: Colors.white,
                                      onConfirm: () async {
                                        Get.back(); // Close confirm dialog first

                                        // Ask for PIN
                                        final pinController =
                                            TextEditingController();
                                        final pinResult =
                                            await Get.dialog<bool>(
                                              AlertDialog(
                                                title: const Text(
                                                  'Enter PIN to Delete',
                                                ),
                                                content: TextField(
                                                  controller: pinController,
                                                  obscureText: true,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      const InputDecoration(
                                                        labelText: 'PIN',
                                                      ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Get.back(result: false),
                                                    child: const Text('CANCEL'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      final isValid =
                                                          await _authController
                                                              .verifyEditAction(
                                                                pinController
                                                                    .text,
                                                              );
                                                      Get.back(result: isValid);
                                                    },
                                                    child: const Text('VERIFY'),
                                                  ),
                                                ],
                                              ),
                                            );

                                        if (pinResult == true) {
                                          await _controller.deleteColumn(
                                            col.name,
                                          );
                                          setState(() {
                                            widget.form.columns.removeAt(index);
                                            _gridVersion++;
                                          });
                                          setDtState(() {});

                                          // Trigger reload
                                          _controller.recalculateAllRows();
                                          Get.snackbar(
                                            'Success',
                                            'Column deleted successfully',
                                          );
                                        } else if (pinResult == false) {
                                          Get.snackbar(
                                            'Error',
                                            'Invalid PIN',
                                            backgroundColor: Colors.red,
                                            colorText: Colors.white,
                                          );
                                        }
                                      },
                                      textCancel: 'CANCEL',
                                    );
                                  },
                                )
                              else
                                const IconButton(
                                  icon: Icon(Icons.delete, color: Colors.grey),
                                  onPressed: null,
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('CLOSE')),
        ],
      ),
    );
  }

  Future<void> _importExcel() async {
    // 1. PIN Verification
    final pinController = TextEditingController();
    final verified = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Enter PIN to Import'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PIN',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) async {
            final isValid = await _authController.verifyEditAction(
              pinController.text,
            );
            Get.back(result: isValid);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final isValid = await _authController.verifyEditAction(
                pinController.text,
              );
              Get.back(result: isValid);
            },
            child: const Text('VERIFY'),
          ),
        ],
      ),
    );

    if (verified != true) {
      Get.snackbar(
        'Error',
        'Invalid PIN or Cancelled',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    // 2. Pick File
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path!;
    final fileName = result.files.single.name;

    try {
      // 3. Read Excel
      _controller.isLoading.value = true;
      final excel = await ExcelService.readFile(path);
      _controller.isLoading.value = false;

      if (excel == null) {
        Get.snackbar('Error', 'Could not read Excel file');
        return;
      }

      final sheets = ExcelService.getSheetNames(excel);
      if (sheets.isEmpty) {
        Get.snackbar('Error', 'No sheets found');
        return;
      }

      // 4. Select Sheet
      String selectedSheet = sheets.first;
      if (sheets.length > 1) {
        final selection = await Get.dialog<String>(
          AlertDialog(
            title: const Text('Select Sheet'),
            content: SizedBox(
              width: 300,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sheets.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(sheets[i]),
                  onTap: () => Get.back(result: sheets[i]),
                ),
              ),
            ),
          ),
        );
        if (selection == null) return;
        selectedSheet = selection;
      }

      // 5. Parse & Validate
      _controller.isLoading.value = true;
      List<Map<String, dynamic>> parsedData;
      try {
        parsedData = ExcelService.parseSheetData(
          excel: excel,
          sheetName: selectedSheet,
          formColumns: widget.form.columns,
        );
      } catch (e) {
        _controller.isLoading.value = false;
        Get.defaultDialog(
          title: 'Validation Error',
          middleText: e.toString(),
          textConfirm: 'OK',
          onConfirm: () => Get.back(),
        );
        return;
      }
      _controller.isLoading.value = false;

      // 6. Confirmation
      final confirm = await Get.defaultDialog<bool>(
        title: 'Confirm Import',
        content: Column(
          children: [
            Text('File: $fileName'),
            Text('Sheet: $selectedSheet'),
            const SizedBox(height: 8),
            Text(
              'Rows to Import: ${parsedData.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Warning: Ensure column order matches exactly!',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        textConfirm: 'IMPORT',
        textCancel: 'CANCEL',
        onConfirm: () => Get.back(result: true),
        onCancel: () => Get.back(result: false),
      );

      if (confirm == true) {
        // 7. Import
        await _controller.batchImportRecords(parsedData);
        Get.snackbar(
          'Success',
          'Successfully imported ${parsedData.length} records',
        );

        // Fix S.No by forcing rebuild or reload
        setState(() {
          _gridVersion++;
        });
      }
    } catch (e) {
      _controller.isLoading.value = false;
      Get.snackbar('Error', 'Import failed: $e');
    }
  }

  Future<void> _showEditColumnDialog(ColumnModel col) async {
    final nameController = TextEditingController(text: col.name);
    final formulaController = TextEditingController(text: col.formula ?? '');
    ColumnType selectedType = col.type;
    final oldName = col.name;

    await Get.dialog(
      AlertDialog(
        title: const Text('Edit Column'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Column Name'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ColumnType>(
                    value: selectedType,
                    items: ColumnType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.name.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => selectedType = val);
                    },
                    decoration: const InputDecoration(labelText: 'Type'),
                  ),
                  if (selectedType == ColumnType.formula) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Formula:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextField(
                      controller: formulaController,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Price * Qty',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Type numbers (e.g. / 100) or select variables:',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...widget.form.columns
                            .where(
                              (c) =>
                                  c.type == ColumnType.number &&
                                  c.name != oldName,
                            )
                            .map(
                              (c) => ActionChip(
                                label: Text(c.name),
                                onPressed: () {
                                  final text = formulaController.text;
                                  final selection = formulaController.selection;
                                  final newText = text.replaceRange(
                                    selection.start >= 0
                                        ? selection.start
                                        : text.length,
                                    selection.end >= 0
                                        ? selection.end
                                        : text.length,
                                    ' ${c.name} ',
                                  );
                                  formulaController.text = newText;
                                },
                              ),
                            ),
                        ActionChip(
                          label: const Text('/'),
                          onPressed: () => formulaController.text += ' / ',
                        ),
                        ActionChip(
                          label: const Text('*'),
                          onPressed: () => formulaController.text += ' * ',
                        ),
                        ActionChip(
                          label: const Text('+'),
                          onPressed: () => formulaController.text += ' + ',
                        ),
                        ActionChip(
                          label: const Text('-'),
                          onPressed: () => formulaController.text += ' - ',
                        ),
                        ActionChip(
                          label: const Text('('),
                          onPressed: () => formulaController.text += ' ( ',
                        ),
                        ActionChip(
                          label: const Text(')'),
                          onPressed: () => formulaController.text += ' ) ',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                // Check unique name only if changed
                if (nameController.text != oldName &&
                    widget.form.columns.any(
                      (c) => c.name == nameController.text,
                    )) {
                  Get.snackbar('Error', 'Name already exists');
                  return;
                }

                String? formula;
                if (selectedType == ColumnType.formula)
                  formula = formulaController.text;

                final newCol = ColumnModel(
                  formId: col.formId,
                  name: nameController.text,
                  type: selectedType,
                  formula: formula,
                );

                await _controller.updateColumn(oldName, newCol);

                setState(() {
                  final idx = widget.form.columns.indexWhere(
                    (c) => c.name == oldName,
                  );
                  if (idx != -1) widget.form.columns[idx] = newCol;
                });

                Future.delayed(const Duration(milliseconds: 300), () {
                  _controller.recalculateAllRows();
                });

                Get.back();
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _showColumnStyleDialog(ColumnModel col) async {
    Color? currentBg;
    if (col.backgroundColor != null) {
      currentBg = Color(
        int.parse(col.backgroundColor!.replaceFirst('#', '0xFF')),
      );
    }
    Color? currentText;
    if (col.textColor != null) {
      currentText = Color(int.parse(col.textColor!.replaceFirst('#', '0xFF')));
    }

    final colors = [
      Colors.transparent,
      Colors.white,
      Colors.black,
      Colors.red,
      Colors.redAccent,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
    ];

    Color? selectedBg = currentBg ?? Colors.transparent;
    Color? selectedText = currentText ?? Colors.black;

    await Get.dialog(
      AlertDialog(
        title: Text('Style "${col.name}"'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Background Color',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((c) {
                      return InkWell(
                        onTap: () => setState(() => selectedBg = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c == Colors.transparent ? Colors.white : c,
                            border: Border.all(
                              color: selectedBg == c
                                  ? Colors.blue
                                  : Colors.grey,
                              width: selectedBg == c ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: c == Colors.transparent
                              ? const Icon(
                                  Icons.format_color_reset,
                                  size: 20,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Text Color',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: colors.map((c) {
                      return InkWell(
                        onTap: () => setState(() => selectedText = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c == Colors.transparent ? Colors.white : c,
                            border: Border.all(
                              color: selectedText == c
                                  ? Colors.blue
                                  : Colors.grey,
                              width: selectedText == c ? 3 : 1,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: c == Colors.transparent
                              ? const Icon(
                                  Icons.format_color_reset,
                                  size: 20,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              // Convert to hex string
              String? bgStr;
              if (selectedBg != Colors.transparent && selectedBg != null) {
                bgStr =
                    '#${selectedBg!.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
              }
              String? txtStr;
              if (selectedText != Colors.transparent && selectedText != null) {
                txtStr =
                    '#${selectedText!.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
              }

              // Create updated column model
              final newCol = ColumnModel(
                formId: col.formId,
                name: col.name,
                type: col.type,
                formula: col.formula,
                textColor: txtStr,
                backgroundColor: bgStr,
                id: col.id,
              );

              // Update in DB
              // We need updateColumn to support full update. Currently it might replace.
              await _controller.updateColumn(col.name, newCol);

              setState(() {
                final idx = widget.form.columns.indexWhere(
                  (c) => c.name == col.name,
                );
                if (idx != -1) widget.form.columns[idx] = newCol;
                _gridVersion++;
              });

              Get.back();
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToPdf() async {
    final pdf = pw.Document();

    // Prepare data
    // Headers
    final headers = ['S.No', ...widget.form.columns.map((c) => c.name)];

    // Data Rows
    final data = <List<String>>[];
    for (var i = 0; i < _controller.records.length; i++) {
      final record = _controller.records[i];
      // Check if emptiness check is needed? User said "whole data"
      // But if we have 20 empty rows at the start... maybe we skip them if they are truly empty?
      // The user said "if user has too much data", implying real data.
      // Let's include everything found in _controller.records (which loaded from DB).
      // Note DB load doesn't include the "new blank rows" unless they were saved.

      final rowData = <String>[];
      rowData.add((i + 1).toString()); // S.No

      for (var col in widget.form.columns) {
        final val = record.data[col.name];

        // Format date if needed
        String cellText = val?.toString() ?? '';
        if (col.type == ColumnType.date && cellText.isNotEmpty) {
          try {
            final date = DateTime.tryParse(cellText);
            if (date != null) {
              cellText = DateFormat('dd MMM yyyy').format(date);
            }
          } catch (_) {}
        }

        rowData.add(cellText);
      }
      data.add(rowData);
    }

    if (data.isEmpty) {
      Get.snackbar('Info', 'No records to export');
      return;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                widget.form.name,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              headers: headers,
              data: data,
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ];
        },
      ),
    );

    // Print/Save
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${widget.form.name}_export.pdf',
    );
  }

  // Method to safely filter
  void _onSearchChanged(String val) {
    if (!_gridInitialized) return;

    _controller.stateManager.setFilter((PlutoRow row) {
      if (val.isEmpty) return true;
      return widget.form.columns.any((col) {
        final cellVal = row.cells[col.name]?.value.toString() ?? '';
        return cellVal.toLowerCase().contains(val.toLowerCase());
      });
    });
  }

  void _addRows(int count) {
    if (!_isEditing) return;
    if (count <= 0) return;

    final stateManager = _controller.stateManager;

    // Force commit
    if (stateManager.isEditing) {
      stateManager.setEditing(false);
    }

    final newRows = <PlutoRow>[];
    final currentLength = stateManager.rows.length;

    for (var i = 0; i < count; i++) {
      final newRow = stateManager.getNewRow();

      // Set S.No
      newRow.cells['serial_no']?.value = (currentLength + i + 1).toString();

      // Ensure other cells are empty
      for (var col in widget.form.columns) {
        newRow.cells[col.name]?.value = '';
      }
      newRows.add(newRow);
    }

    // Append to BOTTOM
    stateManager.insertRows(stateManager.rows.length, newRows);

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (stateManager.rows.length > 0) {
        stateManager.moveScrollByRow(
          PlutoMoveDirection.down,
          stateManager.rows.length,
        );
      }
    });
  }

  void _onRowSecondaryTap(PlutoGridOnRowSecondaryTapEvent event) {
    if (!_isEditing) return;

    // Calculate position for the menu
    // offset is typically local to the grid. We need global for showMenu.
    // However, event.offset isn't always reliable for showMenu's generic positioning.
    // We can use a trick with RenderBox or just approximation if offset is global-ish.
    // PlutoGrid 6.x: event.offset is local to the cell or row?
    // Let's assume we can get a position.
    // Actually, `showMenu` require `position` (RelativeRect).

    // Better strategy: Calculate rect from tap offset?
    // Since we don't have the TapDownDetails here, we rely on event.offset.
    // Let's try to use the cell position.

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    // We might need the pointer position which isn't fully in event.
    // But let's try displaying a Get.dialog or BottomSheet as it's safer than positioning a Menu blindly?
    // Or use PlutoGrid's built-in context menu handling if available.
    // Let's stick to a Context Menu using `showMenu` if we can guess position, or just a Dialog.
    // User asked for "Right click... give option". Context Menu is best.

    // For now, I'll use a fixed position based on the mouse pointer if possible, but Flutter web/desktop
    // usually requires `Listener` to get pointer.
    // PlutoGrid `onRowSecondaryTap` triggers on right click.

    // Let's use `Get.customMenu` or similar? No.

    // Allow users to delete focused row or selected rows.

    final selectedRows = _controller.stateManager.checkedRows;
    final targetRow = event.row;
    final bool isTargetSelected = selectedRows.contains(targetRow);

    // If user right-clicked a row, and it's not in selection, maybe select it?
    // Standard OS behavior: Right click selects the item if not selected.
    if (!isTargetSelected && selectedRows.isEmpty) {
      // Just operate on targetRow
    }

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Row Actions'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Get.back();
              _deleteSingleRow(targetRow);
            },
            child: const Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete this row'),
              ],
            ),
          ),
          if (selectedRows.isNotEmpty)
            SimpleDialogOption(
              onPressed: () {
                Get.back();
                _deleteMultipleRows(selectedRows);
              },
              child: Row(
                children: [
                  const Icon(Icons.delete_sweep, color: Colors.red),
                  const SizedBox(width: 8),
                  Text('Delete ${selectedRows.length} selected rows'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteSingleRow(PlutoRow row) async {
    final idStr = row.cells['__id']?.value.toString();
    if (idStr != null && idStr.isNotEmpty) {
      final id = int.tryParse(idStr);
      if (id != null) {
        await _controller.deleteRecord(id);
        Get.snackbar('Success', 'Row deleted');
        setState(() {
          _gridVersion++;
        });
      }
    } else {
      _controller.stateManager.removeRows([row]);
      Get.snackbar('Success', 'Row deleted');
    }
  }

  Future<void> _deleteMultipleRows(List<PlutoRow> rows) async {
    Get.defaultDialog(
      title: 'Delete Rows',
      middleText: 'Delete ${rows.length} rows?',
      textConfirm: 'DELETE',
      confirmTextColor: Colors.white,
      onConfirm: () async {
        Get.back();
        final idsToDelete = <int>[];
        for (var r in rows) {
          final idStr = r.cells['__id']?.value.toString();
          if (idStr != null && idStr.isNotEmpty) {
            final id = int.tryParse(idStr);
            if (id != null) idsToDelete.add(id);
          }
        }
        if (idsToDelete.isNotEmpty) {
          await _controller.batchDeleteRecords(idsToDelete);
        }
        // Also remove temp rows if any in valid selection
        // But batchDelete reloads grid so temp rows disappear or stay?
        // reloadRecords reloads from DB. Temp rows (not saved) will be lost if we reload.
        // Saved rows are deleted.
        // So pure UI remove is redundant if we reload.
        _controller.stateManager.removeRows(
          rows,
        ); // Remove unsaved rows from UI
        Get.snackbar('Success', 'Deleted ${rows.length} rows');
        setState(() {
          _gridVersion++;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.form.name} Records'),
        actions: [
          // Responsive Actions
          if (isWide) ...[
            ElevatedButton.icon(
              onPressed: () => _exportToPdf(),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('EXPORT PDF'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _importExcel(),
              icon: const Icon(Icons.file_upload),
              label: const Text('IMPORT EXCEL'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],

          if (!_isEditing)
            ElevatedButton.icon(
              onPressed: _promptPinForEdit,
              icon: const Icon(Icons.edit),
              label: const Text('ENABLE EDITING'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _saveChanges,
              icon: const Icon(Icons.check),
              label: const Text('SAVE & LOCK'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),

          const SizedBox(width: 8),

          ElevatedButton.icon(
            onPressed: _showManageColumnsDialog,
            icon: const Icon(Icons.settings),
            label: const Text('MANAGE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
          ),

          if (_isEditing) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _showAddColumnDialog,
              icon: const Icon(Icons.view_column),
              label: const Text('ADD COL'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],

          // If small screen, show More menu for hidden items
          if (!isWide)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More Actions',
              onSelected: (val) {
                if (val == 'export') _exportToPdf();
                if (val == 'import') _importExcel();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf, color: Colors.teal),
                    title: Text('Export PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(
                    leading: Icon(Icons.file_upload, color: Colors.indigo),
                    title: Text('Import Excel'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),

          const SizedBox(width: 16),
        ],
      ),
      body: Obx(() {
        if (_controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // Header Row (Search & Actions) - Moved OUT of PlutoGrid
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  // ADD ROW Buttons
                  if (_isEditing && _gridInitialized)
                    PopupMenuButton<String>(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.add, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'ADD DATA',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: Colors.white),
                          ],
                        ),
                      ),
                      onSelected: (val) {
                        if (val == 'single') _addRows(1);
                        if (val == 'multiple') {
                          _showAddMultipleDialog();
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'single',
                          child: Text('Add Single Row'),
                        ),
                        const PopupMenuItem(
                          value: 'multiple',
                          child: Text('Add Multiple Rows'),
                        ),
                      ],
                    ),

                  if (_isEditing) const SizedBox(width: 16),
                  const Text(
                    'Right-click rows to delete',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                  const Spacer(),
                  // Search Bar
                  SizedBox(
                    width: 300,
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      style: const TextStyle(color: Colors.black),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PlutoGrid(
                key: ValueKey(
                  'grid_${widget.form.id}_${_isEditing}_$_gridVersion',
                ),
                columns: _buildColumns(),
                rows: _buildRows(),
                onChanged: (PlutoGridOnChangedEvent event) {
                  String? excludeColName;

                  // Intercept change to check for inline formula
                  if (event.column.field.isNotEmpty) {
                    final colModel = widget.form.columns.firstWhereOrNull(
                      (c) => c.name == event.column.field,
                    );

                    if (colModel != null) {
                      // Allow inline math for Number AND Formula columns
                      if (colModel.type == ColumnType.number ||
                          colModel.type == ColumnType.formula) {
                        final input = event.value.toString();
                        final evaluated = _controller.evaluateCellInput(
                          event.row,
                          colModel.name,
                          input,
                        );
                        if (evaluated != input) {
                          // Update with evaluated result
                          _controller.stateManager.changeCellValue(
                            event.row.cells[event.column.field]!,
                            evaluated,
                            callOnChangedEvent: false,
                          );
                        }
                      }

                      // If currently editing a formula column, exclude it from recalculation
                      // so the manual override isn't immediately overwritten
                      if (colModel.type == ColumnType.formula) {
                        excludeColName = colModel.name;
                      }
                    }
                  }

                  try {
                    _controller.recalculateFormulas(
                      event.row,
                      excludeColumn: excludeColName,
                    );
                  } catch (e) {
                    debugPrint('Error calculating formulas: $e');
                  }

                  // Save changes to DB if it's an existing row
                  final idStr = event.row.cells['__id']?.value;
                  if (idStr != null && idStr.toString().isNotEmpty) {
                    final id = int.tryParse(idStr.toString());
                    final data = <String, dynamic>{};
                    event.row.cells.forEach((key, cell) {
                      if (key != 'serial_no' && key != '__id') {
                        data[key] = cell.value;
                      }
                    });
                    if (id != null) {
                      _controller.updateRecord(id, data);
                    }
                  }
                },
                onColumnsMoved: (PlutoGridOnColumnsMovedEvent event) {
                  // Update the form model to reflect the new column order
                  final sortedColumns = _controller.stateManager.columns;
                  final newOrderNames = sortedColumns
                      .where((c) => c.field != 'serial_no' && c.field != '__id')
                      .map((c) => c.field)
                      .toList();

                  final oldColumnsMap = {
                    for (var c in widget.form.columns) c.name: c,
                  };
                  final newColumnsList = <ColumnModel>[];

                  for (var name in newOrderNames) {
                    if (oldColumnsMap.containsKey(name)) {
                      newColumnsList.add(oldColumnsMap[name]!);
                    }
                  }

                  // Update references
                  widget.form.columns.clear();
                  widget.form.columns.addAll(newColumnsList);
                },
                onLoaded: (PlutoGridOnLoadedEvent event) {
                  _controller.stateManager = event.stateManager;
                  event.stateManager.setSelectingMode(
                    PlutoGridSelectingMode.row,
                  );
                  event.stateManager.setShowColumnFilter(
                    false,
                  ); // Hidden as requested

                  // Mark grid as initialized so search can work
                  if (!_gridInitialized) {
                    // Use a post frame callback or SetState to update UI safely
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _gridInitialized = true;
                        });
                        // Re-apply search if controller has text
                        if (_searchController.text.isNotEmpty) {
                          _onSearchChanged(_searchController.text);
                        }
                      }
                    });
                  }

                  // If no records, automatically enter edit mode and add default rows
                  if (_controller.records.isEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      // No auto edit
                    });
                  }
                },
                onRowSecondaryTap: _onRowSecondaryTap, // Right Click Handler
                configuration: const PlutoGridConfiguration(
                  scrollbar: PlutoGridScrollbarConfig(
                    isAlwaysShown: true,
                    scrollbarThickness: 10,
                    scrollbarRadius: Radius.circular(5),
                  ),
                  columnSize: PlutoGridColumnSizeConfig(
                    autoSizeMode: PlutoAutoSizeMode.scale,
                  ),
                  style: PlutoGridStyleConfig(),
                  enableMoveDownAfterSelecting: true,
                  enterKeyAction: PlutoGridEnterKeyAction.editingAndMoveDown,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  void _showAddMultipleDialog() async {
    final countController = TextEditingController();
    final count = await Get.dialog<int>(
      AlertDialog(
        title: const Text('Add Multiple Rows'),
        content: TextField(
          controller: countController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Number of rows'),
          onSubmitted: (val) => Get.back(result: int.tryParse(val) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              Get.back(result: int.tryParse(countController.text) ?? 0);
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
    if (count != null && count > 0) _addRows(count);
  }
}
