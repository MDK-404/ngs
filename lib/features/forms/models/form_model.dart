enum ColumnType { text, number, date, formula }

class FormModel {
  final int? id;
  final String name;
  final int? collectionId;
  final List<ColumnModel> columns;

  FormModel({
    this.id,
    required this.name,
    this.collectionId,
    this.columns = const [],
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'collection_id': collectionId};
  }

  factory FormModel.fromMap(
    Map<String, dynamic> map, {
    List<ColumnModel> columns = const [],
  }) {
    return FormModel(
      id: map['id'],
      name: map['name'],
      collectionId: map['collection_id'],
      columns: columns,
    );
  }
}

class CollectionModel {
  final int? id;
  final String name;
  final DateTime? createdAt;
  final List<FormModel> forms; // Forms in this collection

  CollectionModel({
    this.id,
    required this.name,
    this.createdAt,
    this.forms = const [],
  });

  // Basic to/from map if needed
  factory CollectionModel.fromMap(
    Map<String, dynamic> map, {
    List<FormModel> forms = const [],
  }) {
    return CollectionModel(
      id: map['id'],
      name: map['name'],
      forms: forms,
      // createdAt parsing if needed
    );
  }
}

class ColumnModel {
  final int? id;
  final int? formId;
  final String name;
  final ColumnType type;
  final String? formula;
  final String? textColor;
  final String? backgroundColor;
  final bool isHidden;

  ColumnModel({
    this.id,
    this.formId,
    required this.name,
    required this.type,
    this.formula,
    this.textColor,
    this.backgroundColor,
    this.isHidden = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'form_id': formId,
      'name': name,
      'type': type.name,
      'formula': formula,
      'text_color': textColor,
      'background_color': backgroundColor,
      'is_hidden': isHidden ? 1 : 0,
    };
  }

  factory ColumnModel.fromMap(Map<String, dynamic> map) {
    return ColumnModel(
      id: map['id'],
      formId: map['form_id'],
      name: map['name'],
      type: ColumnType.values.firstWhere((e) => e.name == map['type']),
      formula: map['formula'],
      textColor: map['text_color'],
      backgroundColor: map['background_color'],
      isHidden: map['is_hidden'] == 1,
    );
  }
}
