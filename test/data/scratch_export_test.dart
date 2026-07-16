import 'dart:convert';
import 'dart:io';

import 'package:everything_app/data/database/app_database.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('replicate _exportSnapshot against a real drift_flutter database', () async {
    final docs = await Directory.systemTemp.createTemp('exp_docs');
    final tmp = await Directory.systemTemp.createTemp('exp_tmp');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => call.method == 'getApplicationDocumentsDirectory'
          ? docs.path
          : tmp.path,
    );

    final db = AppDatabase.encrypted(
      encryptionKey: 'a' * 64,
      databaseDirectory: docs.path,
      temporaryDirectory: tmp.path,
    );

    try {
      final tables = <String, List<Map<String, dynamic>>>{};
      for (final table in db.allTables) {
        try {
          final rows =
              await db.customSelect('SELECT * FROM ${table.actualTableName}').get();
          tables[table.actualTableName] = rows.map((r) => r.data).toList();
          // ignore: avoid_print
          print('OK   ${table.actualTableName} (${rows.length} rows)');
        } catch (e) {
          // ignore: avoid_print
          print('FAIL ${table.actualTableName}: ${e.runtimeType}: $e');
        }
      }
      final json = jsonEncode({'tables': tables});
      // ignore: avoid_print
      print('JSON OK: ${json.length} chars');
    } catch (e, s) {
      // ignore: avoid_print
      print('THREW: ${e.runtimeType}: $e\n$s');
    }

    await db.close();
    await docs.delete(recursive: true);
    await tmp.delete(recursive: true);
  });
}
