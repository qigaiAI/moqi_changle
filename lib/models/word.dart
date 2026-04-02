class Word {
  final String id;
  final String text;
  final String difficulty; // 'easy', 'medium', 'hard'
  final String category;

  const Word({
    required this.id,
    required this.text,
    required this.difficulty,
    required this.category,
  });

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        id: json['id'] as String,
        text: json['text'] as String,
        difficulty: json['difficulty'] as String,
        category: json['category'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'difficulty': difficulty,
        'category': category,
      };
}
