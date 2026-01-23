import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:intl/intl.dart';
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
    final cols = widget.form.columns
        .where((col) => seen.add(col.name)) // deduplicate
        .map((col) {
          // ... existing mapping logic ...
          PlutoColumnType type = PlutoColumnType.text();
          if (col.type == ColumnType.number || col.type == ColumnType.formula) {
            type = PlutoColumnType.number();
          } else if (col.type == ColumnType.date) {
            type = PlutoColumnType.date();
          }

          return PlutoColumn(
            title: col.name,
            field: col.name,
            type: type,
            readOnly: col.type == ColumnType.formula || !_isEditing,
            enableEditingMode: col.type != ColumnType.formula && _isEditing,
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
        })
        .toList();

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
      for (var col in widget.form.columns) {
        data[col.name] = row.cells[col.name]?.value;
      }

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
                      'Insert Variable:',
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
          child: StatefulBuilder(
            builder: (context, setDtState) {
              return ListView.builder(
                shrinkWrap: true,
                itemCount: widget.form.columns.length,
                itemBuilder: (context, index) {
                  final col = widget.form.columns[index];
                  return ListTile(
                    title: Text(col.name),
                    subtitle: Text(col.type.name.toUpperCase()),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () async {
                            // Close manage dialog first or stack? Stack is fine.
                            await _showEditColumnDialog(col);
                            setDtState(() {}); // Refresh list
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
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
                                final pinController = TextEditingController();
                                final pinResult = await Get.dialog<bool>(
                                  AlertDialog(
                                    title: const Text('Enter PIN to Delete'),
                                    content: TextField(
                                      controller: pinController,
                                      obscureText: true,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
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
                                          final isValid = await _authController
                                              .verifyEditAction(
                                                pinController.text,
                                              );
                                          Get.back(result: isValid);
                                        },
                                        child: const Text('VERIFY'),
                                      ),
                                    ],
                                  ),
                                );

                                if (pinResult == true) {
                                  await _controller.deleteColumn(col.name);
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
                        ),
                      ],
                    ),
                  );
                },
              );
            },
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
                    Wrap(
                      spacing: 8,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.form.name} Records'),
        actions: [
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
            try {
              _controller.recalculateFormulas(event.row);
            } catch (e) {
              print('Error calculating formulas: $e');
            }
          },
          onLoaded: (PlutoGridOnLoadedEvent event) {
            _controller.stateManager = event.stateManager;
            event.stateManager.setSelectingMode(PlutoGridSelectingMode.row);
          },
          configuration: const PlutoGridConfiguration(
            style: PlutoGridStyleConfig(),
          ),
          createHeader: (stateManager) => Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isEditing
                      ? () {
                          // Force commit current edit
                          if (stateManager.isEditing) {
                            stateManager.setEditing(false);
                          }

                          final newRow = stateManager.getNewRow();
                          // Set S.No for new row
                          newRow.cells['serial_no']?.value =
                              (stateManager.rows.length + 1).toString();
                          // Ensure other cells are empty
                          for (var col in widget.form.columns) {
                            newRow.cells[col.name]?.value = '';
                          }
                          // Append to BOTTOM
                          stateManager.insertRows(stateManager.rows.length, [
                            newRow,
                          ]);

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
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('ADD ROW'),
                ),
                const SizedBox(width: 16),
                const Text(
                  'Use TAB or ENTER to navigate',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
