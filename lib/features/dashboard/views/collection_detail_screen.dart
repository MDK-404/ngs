import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../forms/models/form_model.dart';
import '../../records/views/record_grid_screen.dart';
import '../../forms/views/form_builder_screen.dart';
import '../../forms/controllers/form_controller.dart';

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
}
