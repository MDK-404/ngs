import 'dart:convert';

class RecordModel {
  final int? id;
  final int formId;
  final Map<String, dynamic> data;
  final DateTime? createdAt;

  RecordModel({
    this.id,
    required this.formId,
    required this.data,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {'id': id, 'form_id': formId, 'data': jsonEncode(data)};
  }

  factory RecordModel.fromMap(Map<String, dynamic> map) {
    return RecordModel(
      id: map['id'],
      formId: map['form_id'],
      data: jsonDecode(map['data']),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : null,
    );
  }
}
