import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/form_controller.dart';
import '../models/form_model.dart';

class FormBuilderScreen extends StatefulWidget {
  const FormBuilderScreen({super.key});

  @override
  State<FormBuilderScreen> createState() => _FormBuilderScreenState();
}

class _FormBuilderScreenState extends State<FormBuilderScreen> {
  final _formController = Get.find<FormController>();
  final _nameController = TextEditingController();
  final List<ColumnModel> _columns = [
    ColumnModel(name: 'Item Name', type: ColumnType.text),
    ColumnModel(name: 'Purchase Price', type: ColumnType.number),
    ColumnModel(name: 'Wholesale ', type: ColumnType.number),
    ColumnModel(name: 'Retail', type: ColumnType.number),
  ];

  void _addColumn() {
    setState(() {
      _columns.add(ColumnModel(name: 'New Column', type: ColumnType.text));
    });
  }

  void _removeColumn(int index) {
    if (_columns.length > 1) {
      setState(() {
        _columns.removeAt(index);
      });
    }
  }

  void _saveForm() async {
    if (_nameController.text.isEmpty) {
      Get.snackbar('Error', 'Please enter a form name');
      return;
    }

    try {
      print('Saving form: ${_nameController.text}');
      await _formController.createForm(_nameController.text, _columns);
      Get.back();
      Get.snackbar(
        'Success',
        'Form "${_nameController.text}" created successfully',
      );
    } catch (e) {
      print('Error saving form: $e');
      Get.snackbar('Error', 'Failed to save form: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Form'),
        actions: [
          TextButton.icon(
            onPressed: _saveForm,
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text(
              'SAVE FORM',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Form Name (e.g., Stock, Category, Sales)',
                border: OutlineInputBorder(),
              ),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Define Columns',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ElevatedButton.icon(
                  onPressed: _addColumn,
                  icon: const Icon(Icons.add),
                  label: const Text('ADD COLUMN'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _columns.length,
                itemBuilder: (context, index) {
                  final col = _columns[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: col.name,
                              onChanged: (val) => _columns[index] = ColumnModel(
                                name: val,
                                type: _columns[index].type,
                                formula: _columns[index].formula,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Column Name',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<ColumnType>(
                              value: col.type,
                              items: ColumnType.values
                                  .map(
                                    (type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(type.name.toUpperCase()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _columns[index] = ColumnModel(
                                      name: _columns[index].name,
                                      type: val,
                                      formula: _columns[index].formula,
                                    );
                                  });
                                }
                              },
                              decoration: const InputDecoration(
                                labelText: 'Type',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (col.type == ColumnType.formula)
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                initialValue: col.formula,
                                onChanged: (val) =>
                                    _columns[index] = ColumnModel(
                                      name: _columns[index].name,
                                      type: _columns[index].type,
                                      formula: val,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'Formula (e.g., A + B)',
                                ),
                              ),
                            )
                          else
                            const Spacer(flex: 3),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.grey,
                            ),
                            onPressed: () => _removeColumn(index),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
