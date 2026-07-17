import 'package:flutter/foundation.dart' show listEquals;

/// [WatchDistinct] suppresses stream re-emissions equal to the previous list.
///
/// drift re-runs a streaming query on *any* write to a table it reads, even when
/// the result is unchanged — each firing re-maps every row (up to four
/// `jsonDecode` per task) and rebuilds every listening widget. Drift rows carry
/// value equality, so this O(n) field walk is cheaper than the work it drops.
extension WatchDistinct<T> on Stream<List<T>> {
  Stream<List<T>> distinctList() => distinct(listEquals);
}
