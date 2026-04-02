import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/question.dart';
import '../models/word.dart';

class LocalDataService {
  static List<Question>? _questions;
  static List<Word>? _words;

  static Future<List<Question>> loadQuestions() async {
    if (_questions != null) return _questions!;
    final raw = await rootBundle.loadString('assets/data/questions.json');
    final list = jsonDecode(raw) as List;
    _questions = list.map((e) => Question.fromJson(e as Map<String, dynamic>)).toList();
    return _questions!;
  }

  static Future<List<Word>> loadWords({String? difficulty}) async {
    if (_words == null) {
      final raw = await rootBundle.loadString('assets/data/words.json');
      final list = jsonDecode(raw) as List;
      _words = list.map((e) => Word.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (difficulty != null) {
      return _words!.where((w) => w.difficulty == difficulty).toList();
    }
    return _words!;
  }

  /// 随机抽取 4 个词供作画者选择
  static Future<List<Word>> drawWords({String? difficulty}) async {
    final pool = await loadWords(difficulty: difficulty);
    pool.shuffle();
    return pool.take(4).toList();
  }

  /// 随机抽取一道题
  static Future<Question> randomQuestion() async {
    final pool = await loadQuestions();
    pool.shuffle();
    return pool.first;
  }
}
