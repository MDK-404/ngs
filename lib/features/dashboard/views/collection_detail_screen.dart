import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../forms/models/form_model.dart';
import '../../records/views/record_grid_screen.dart';

class CollectionDetailScreen extends StatelessWidget {
  final CollectionModel collection;

  const CollectionDetailScreen({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    // We assume the collection model passed here already has 'forms' populated by the controller.
    // However, if we want strict reactivity, we might want to lookup the collection again from controller
    // or just use the passed list. The controller rebuilds the whole list on load.
    // For simplicity, we use the passed collection forms.

    return Scaffold(
      appBar: AppBar(
        title: Text(collection.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${collection.forms.length} Forms',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: collection.forms.isEmpty
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
                      itemCount: collection.forms.length,
                      itemBuilder: (context, index) {
                        final form = collection.forms[index];
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
                                    style: const TextStyle(color: Colors.grey),
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
      ),
    );
  }
}
