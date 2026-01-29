import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import '../../forms/models/form_model.dart';
import '../../records/views/record_grid_screen.dart';
import '../../forms/views/form_builder_screen.dart';
import '../../forms/controllers/form_controller.dart';
import '../../records/controllers/record_controller.dart';
import '../../../core/services/excel_service.dart';

class CollectionDetailScreen extends StatelessWidget {
  final CollectionModel collection;

  const CollectionDetailScreen({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<FormController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(collection.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _exportCollectionToExcel(context),
            icon: const Icon(Icons.download, color: Colors.white),
            label: const Text(
              'EXPORT TO EXCEL',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: () {
              Get.to(() => FormBuilderScreen(collectionId: collection.id));
            },
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'ADD FORM',
              style: TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Obx(() {
        // Find the latest version of this collection from the controller
        final liveCollection = controller.collections.firstWhere(
          (c) => c.id == collection.id,
          orElse: () => collection,
        );

        return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${liveCollection.forms.length} Forms',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: liveCollection.forms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            const Text('This collection is empty'),
                          ],
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 1.5,
                            ),
                        itemCount: liveCollection.forms.length,
                        itemBuilder: (context, index) {
                          final form = liveCollection.forms[index];
                          return Card(
                            child: InkWell(
                              onTap: () {
                                Get.to(() => RecordGridScreen(form: form));
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.table_chart,
                                          color: Colors.indigo,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            form.name,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleLarge,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${form.columns.length} Columns',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _exportCollectionToExcel(BuildContext context) async {
    final controller = Get.find<FormController>();

    // Find the latest version of this collection
    final liveCollection = controller.collections.firstWhere(
      (c) => c.id == collection.id,
      orElse: () => collection,
    );

    if (liveCollection.forms.isEmpty) {
      Get.snackbar(
        'Info',
        'Collection is empty. Add forms before exporting.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      // Show loading
      Get.dialog(
        const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing Excel export...'),
                ],
              ),
            ),
          ),
        ),
        barrierDismissible: false,
      );

      // Prepare data for each form (sheet)
      final sheetsData = <String, Map<String, dynamic>>{};

      for (var form in liveCollection.forms) {
        // Create a temporary RecordController to fetch records
        final recordController = RecordController(form);
        await recordController.loadRecords();

        // Prepare headers (S.No + column names)
        final headers = ['S.No', ...form.columns.map((c) => c.name)];

        // Prepare data rows
        final data = <List<dynamic>>[];
        for (var i = 0; i < recordController.records.length; i++) {
          final record = recordController.records[i];
          final rowData = <dynamic>[];
          rowData.add(i + 1); // S.No

          for (var col in form.columns) {
            final val = record.data[col.name];
            rowData.add(val ?? '');
          }
          data.add(rowData);
        }

        sheetsData[form.name] = {'headers': headers, 'data': data};

        // Clean up temporary controller
        Get.delete<RecordController>(tag: form.id.toString());
      }

      // Generate Excel bytes
      final bytes = await ExcelService.exportCollectionToExcel(
        collectionName: liveCollection.name,
        sheetsData: sheetsData,
      );

      // Close loading dialog
      Get.back();

      if (bytes == null) {
        Get.snackbar(
          'Error',
          'Failed to generate Excel file',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      // Save File
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel File',
        fileName: '${liveCollection.name}_export.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        try {
          // Ensure extension
          String path = result;
          if (!path.endsWith('.xlsx')) {
            path += '.xlsx';
          }

          final file = File(path);
          await file.writeAsBytes(bytes);
          Get.snackbar(
            'Success',
            'Collection exported to $path',
            backgroundColor: Colors.green,
            colorText: Colors.white,
          );
        } catch (e) {
          Get.snackbar(
            'Error',
            'Failed to save file: $e',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (Get.isDialogOpen ?? false) {
        Get.back();
      }
      Get.snackbar(
        'Error',
        'Export failed: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }
}
