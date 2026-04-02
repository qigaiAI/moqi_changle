class Question {
  final String id;
  final String text;
  final List<String>? options;
  final bool isCustom;

  const Question({
    required this.id,
    required this.text,
    this.options,
    this.isCustom = false,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String,
        text: json['text'] as String,
        options: json['options'] != null
            ? List<String>.from(json['options'] as List)
            : null,
        isCustom: json['isCustom'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'options': options,
        'isCustom': isCustom,
      };
}
