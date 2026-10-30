/// The most results one page of a list tool returns (ticket 13).
const maxPageSize = 200;

/// The page size a tool uses when the request doesn't say.
const defaultPageSize = 50;

/// One page of a list tool's results. [total] is the whole list's length, so
/// a client can ask for the next page.
final class Page<T> {
  const Page({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<T> items;

  /// 1-based.
  final int page;

  /// At most [maxPageSize].
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;
}

/// [all]'s [page], 1-based, at most [maxPageSize] items. A page number below
/// 1 counts as 1 and a limit outside 1..[maxPageSize] is clamped.
Page<T> paginate<T>(List<T> all, {int page = 1, int limit = defaultPageSize}) {
  final size = limit < 1 ? 1 : (limit > maxPageSize ? maxPageSize : limit);
  final number = page < 1 ? 1 : page;
  final start = (number - 1) * size;
  return Page(
    items: start >= all.length
        ? const []
        : List.unmodifiable(all.sublist(start, _min(start + size, all.length))),
    page: number,
    pageSize: size,
    total: all.length,
  );
}

int _min(int a, int b) => a < b ? a : b;
