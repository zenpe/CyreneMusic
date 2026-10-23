/// Per-platform pagination. Page advances only after a successful response.
class SearchPageState {
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final String? error;
  final bool blocked;
  final String? fingerprint;

  const SearchPageState({
    this.page = 0,
    this.hasMore = false,
    this.loadingMore = false,
    this.error,
    this.blocked = false,
    this.fingerprint,
  });

  SearchPageState stopLoading() => SearchPageState(
    page: page,
    hasMore: hasMore,
    blocked: blocked,
    fingerprint: fingerprint,
  );
}
