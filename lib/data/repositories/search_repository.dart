import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/services/search_service.dart';

/// [SearchRepository] defines the contract for Global Search (Requirement 17).
abstract class SearchRepository {
  /// [search] returns up to [limit] results across all eight modules for
  /// [query], ranked by relevance. A blank query returns no results, not an
  /// error.
  Future<JsonResponse> search(String query, {int limit});
}

class SearchRepositoryImpl implements SearchRepository {
  const SearchRepositoryImpl({required this.searchService});

  final SearchService searchService;

  @override
  Future<JsonResponse> search(String query, {int limit = 50}) =>
      searchService.search(query, limit: limit);
}
