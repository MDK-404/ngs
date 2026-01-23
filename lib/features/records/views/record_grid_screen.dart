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
    ColumnType selectedType = ColumnType.text;

    await Get.dialog(
      AlertDialog(
        title: const Text('Add New Column'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
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
              ],
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

                // Add column to form model
                final newCol = ColumnModel(
                  formId: widget.form.id,
                  name: nameController.text,
                  type: selectedType,
                );

                // Save to DB (We need a method in controller/service for this really, but for now we do it here or pass to controller if method existed)
                // Assuming we need to add it to database first.
                // Since this requires schema migration or updates, let's use a new controller method.
                // For this snippet, I will call a hypothetical or new method on controller.
                await _controller.addColumn(newCol);

                setState(() {
                  widget.form.columns.add(newCol);
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
          key: ValueKey('grid_${widget.form.id}_$_isEditing'),
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
