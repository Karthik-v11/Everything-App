import 'package:everything_app/data/models/article.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/news_service.dart';

/// [NewsRepository] defines the contract for news headlines.
abstract class NewsRepository {
  /// [headlines] is the top headlines for one [category].
  Future<JsonResponse> headlines({required NewsCategory category});
}

class NewsRepositoryImpl implements NewsRepository {
  const NewsRepositoryImpl({required this.newsService});

  final NewsService newsService;

  @override
  Future<JsonResponse> headlines({required NewsCategory category}) =>
      newsService.headlines(category: category);
}
