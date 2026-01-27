import 'dart:convert';
import 'package:get/get.dart';
import 'package:ngs_recordbook/core/database/database_service.dart';
import 'package:ngs_recordbook/core/services/excel_service.dart';
import '../models/form_model.dart';

class FormController extends GetxController {
  final RxList<FormModel> forms = <FormModel>[].obs; // Standalone forms
  final RxList<CollectionModel> collections =
      <CollectionModel>[].obs; // Collections (Grouped Forms)
  final RxBool isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadForms();
  }

  Future<void> loadForms() async {
    try {
      isLoading.value = true;
      final db = await DatabaseService.database;
      print('Loading forms and collections...');

      // 1. Fetch Collections
      // Check if table exists (handled by migration, but just to be safe in dev envs)
      final List<Map<String, dynamic>> collectionMaps = await db.query(
        'collections',
      );
      final allCollections = collectionMaps
          .map((m) => CollectionModel.fromMap(m))
          .toList();

      // 2. Fetch Forms
      final List<Map<String, dynamic>> formMaps = await db.query('forms');
      final List<FormModel> allForms = [];

      for (var formMap in formMaps) {
        final List<Map<String, dynamic>> columnMaps = await db.query(
          'form_columns',
          where: 'form_id = ?',
          whereArgs: [formMap['id']],
        );
        final columns = columnMaps.map((c) => ColumnModel.fromMap(c)).toList();
        allForms.add(FormModel.fromMap(formMap, columns: columns));
      }

      // 3. Separate Standalone and Collecton Forms
      final standalone = <FormModel>[];
      final collectionFormsMap = <int, List<FormModel>>{};

      for (var c in allCollections) {
        collectionFormsMap[c.id!] = [];
      }

      for (var form in allForms) {
        if (form.collectionId != null &&
            collectionFormsMap.containsKey(form.collectionId)) {
          collectionFormsMap[form.collectionId]!.add(form);
        } else {
          standalone.add(form);
        }
      }

      // 4. Update Collections with their Forms
      final populatedCollections = <CollectionModel>[];
      for (var c in allCollections) {
        populatedCollections.add(
          CollectionModel(
            id: c.id,
            name: c.name,
            createdAt: c.createdAt,
            forms: collectionFormsMap[c.id!] ?? [],
          ),
        );
      }

      forms.value = standalone;
      collections.value = populatedCollections;

      print(
        'Loaded: ${forms.length} standalone forms, ${collections.length} collections',
      );
    } catch (e) {
      print('Error loading forms: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<int> createForm(
    String name,
    List<ColumnModel> columns, {
    int? collectionId,
  }) async {
    final db = await DatabaseService.database;
    int formId = -1;

    await db.transaction((txn) async {
      formId = await txn.insert('forms', {
        'name': name,
        'collection_id': collectionId,
      });

      for (var col in columns) {
        final isHidden =
            col.isHidden || col.name.toLowerCase().contains('purchase');
        await txn.insert('form_columns', {
          'form_id': formId,
          'name': col.name,
          'type': col.type.name,
          'formula': col.formula,
          'is_hidden': isHidden ? 1 : 0,
        });
      }
    });

    await loadForms();
    print('Form created with ID: $formId');
    return formId;
  }

  Future<void> deleteForm(int formId) async {
    final db = await DatabaseService.database;
    await db.delete('forms', where: 'id = ?', whereArgs: [formId]);
    await loadForms();
  }

  // Method to delete collection? Maybe user wants that too.
  Future<void> deleteCollection(int collectionId) async {
    final db = await DatabaseService.database;
    await db.delete('collections', where: 'id = ?', whereArgs: [collectionId]);
    // Forms cascading deletion usually handled by FK or manual
    // SQLite FKs ON DELETE CASCADE are enabled if configured. DatabaseService enables them?
    // Often need `PRAGMA foreign_keys = ON;`.
    // If not, we should manually delete forms.
    // Safest to manual delete for now or assume configured.
    // Let's delete forms manually to be safe.
    await db.delete(
      'forms',
      where: 'collection_id = ?',
      whereArgs: [collectionId],
    );
    await loadForms();
  }

  Future<void> importFormsFromExcel(String path) async {
    isLoading.value = true;
    try {
      final decoder = ExcelService.decodeFile(path);
      if (decoder == null) throw 'Could not read Excel file';

      final sheets = ExcelService.getSheetNames(decoder);
      if (sheets.isEmpty) throw 'No sheets found';

      final db = await DatabaseService.database;

      // Extract filename
      String filename = path.split(RegExp(r'[/\\]')).last;
      if (filename.contains('.')) {
        filename = filename.substring(0, filename.lastIndexOf('.'));
      }

      await db.transaction((txn) async {
        // 1. Create Collection
        final collectionId = await txn.insert('collections', {
          'name': filename,
        });

        for (var sheetName in sheets) {
          try {
            final result = ExcelService.inferSheetData(
              decoder: decoder,
              sheetName: sheetName,
            );
            final headers = result['headers'] as List<String>;
            final data = result['data'] as List<Map<String, dynamic>>;

            if (headers.isEmpty) continue;

            // 2. Create Form linked to Collection
            final formId = await txn.insert('forms', {
              'name': sheetName,
              'collection_id': collectionId,
            });

            // 3. Create Columns
            for (var header in headers) {
              final isHidden = header.toLowerCase().contains('purchase');
              await txn.insert('form_columns', {
                'form_id': formId,
                'name': header,
                'type': ColumnType.text.name,
                'formula': null,
                'is_hidden': isHidden ? 1 : 0,
              });
            }

            // 4. Insert Records
            final batch = txn.batch();
            for (var row in data) {
              batch.insert('form_records', {
                'form_id': formId,
                'data': jsonEncode(row),
              });
            }
            await batch.commit(noResult: true);
          } catch (e) {
            print('Error importing sheet $sheetName: $e');
          }
        }
      });

      await loadForms();
    } catch (e) {
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }
}
