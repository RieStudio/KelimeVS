import '../domain/models.dart';

abstract class QuestionRepository {
  Future<List<Question>> loadAll();
}

