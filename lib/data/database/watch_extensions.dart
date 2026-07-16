import 'package:flutter/foundation.dart' show listEquals;

/// [WatchDistinct] suppresses stream re-emissions equal to the previous list.
///
/// drift re-runs a streaming query on *any* write to a table it reads, even when
/// that write does not change the query's own result — inserting a task on
/// another date does not change today's list, but `watchForDate` still fires, and
/// each firing re-maps every row (up to four `jsonDecode` per task) and rebuilds
/// every widget listening downstream. Gating on element-wise list equality here
/// drops those no-op emissions before any of that work happens.
///
/// The drift row classes it compares carry value equality, so this is an O(n)
/// field walk over data the query has just produced anyway — paid once here to
/// save a re-map plus a widget rebuild every time it dedupes.
extension WatchDistinct<T> on Stream<List<T>> {
  Stream<List<T>> distinctList() => distinct(listEquals);
}
