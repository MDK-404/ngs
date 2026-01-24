enum ColumnType { text, number, date, formula }

class FormModel {
  final int? id;
  final String name;
  final List<ColumnModel> columns;

  FormModel({this.id, required this.name, this.columns = const []});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }

  factory FormModel.fromMap(
    Map<String, dynamic> map, {
    List<ColumnModel> columns = const [],
  }) {
    return FormModel(id: map['id'], name: map['name'], columns: columns);
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

  ColumnModel({
    this.id,
    this.formId,
    required this.name,
    required this.type,
    this.formula,
    this.textColor,
    this.backgroundColor,
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
    );
  }
}
