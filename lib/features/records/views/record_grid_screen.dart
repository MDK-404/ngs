import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:intl/intl.dart';
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
        enableRowChecked: false,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.form.name} Records'),
        actions: [
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
          const SizedBox(width: 8),
          if (_isEditing)
            ElevatedButton.icon(
              onPressed: _showAddColumnDialog,
              icon: const Icon(Icons.view_column),
              label: const Text('ADD COLUMN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Obx(() {
        if (_controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return PlutoGrid(
          key: ValueKey('grid_${widget.form.id}_${_isEditing}_$_gridVersion'),
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
            event.stateManager.setSelectingMode(PlutoGridSelectingMode.row);

            // If no records, automatically enter edit mode and add default rows
            if (_controller.records.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  _isEditing = true;
                });
                // We need to bypass the _isEditing check in _addRows or just reproduce logic
                event.stateManager.setEditing(true);

                final newRows = <PlutoRow>[];
                for (var i = 0; i < 20; i++) {
                  final newRow = event.stateManager.getNewRow();
                  newRow.cells['serial_no']?.value = (i + 1).toString();
                  for (var col in widget.form.columns) {
                    newRow.cells[col.name]?.value = '';
                  }
                  newRows.add(newRow);
                }
                event.stateManager.insertRows(0, newRows);
              });
            }
          },
          configuration: const PlutoGridConfiguration(
            scrollbar: PlutoGridScrollbarConfig(
              isAlwaysShown: true,
              scrollbarThickness: 10,
              scrollbarRadius: Radius.circular(5),
            ),
            style: PlutoGridStyleConfig(),
            enableMoveDownAfterSelecting: true,
            enterKeyAction: PlutoGridEnterKeyAction.editingAndMoveDown,
          ),
          createHeader: (stateManager) => Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isEditing ? () => _addRows(1) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('ADD ROW'),
                ),
                const SizedBox(width: 8),
                if (_isEditing)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.playlist_add, color: Colors.blue),
                      tooltip: 'Add Multiple Rows',
                      onPressed: () async {
                        final countController = TextEditingController();
                        final count = await Get.dialog<int>(
                          AlertDialog(
                            title: const Text('Add Multiple Rows'),
                            content: TextField(
                              controller: countController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Number of rows',
                                hintText: 'e.g., 5',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Get.back(),
                                child: const Text('CANCEL'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  final n = int.tryParse(countController.text);
                                  if (n != null && n > 0) {
                                    Get.back(result: n);
                                  }
                                },
                                child: const Text('ADD'),
                              ),
                            ],
                          ),
                        );

                        if (count != null) {
                          _addRows(count);
                        }
                      },
                    ),
                  ),
                const SizedBox(width: 16),
                const Text(
                  'Use TAB or ENTER to navigate',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Spacer(),
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
                        vertical: 0,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    style: const TextStyle(color: Colors.black),
                    onChanged: (val) {
                      stateManager.setFilter((PlutoRow row) {
                        if (val.isEmpty) return true;
                        return widget.form.columns.any((col) {
                          final cellVal =
                              row.cells[col.name]?.value.toString() ?? '';
                          return cellVal.toLowerCase().contains(
                            val.toLowerCase(),
                          );
                        });
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
