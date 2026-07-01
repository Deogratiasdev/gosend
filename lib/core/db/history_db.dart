import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/history_item.dart';

class HistoryDB {
  static final HistoryDB instance = HistoryDB._init();
  static Database? _database;

  HistoryDB._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE transfers (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  peerName TEXT NOT NULL,
  fileName TEXT NOT NULL,
  filePath TEXT NOT NULL,
  size INTEGER NOT NULL,
  timestamp INTEGER NOT NULL,
  status TEXT NOT NULL
)
''');
  }

  Future<void> insertItem(HistoryItem item) async {
    final db = await instance.database;
    await db.insert(
      'transfers',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HistoryItem>> getAllItems() async {
    final db = await instance.database;
    final orderBy = 'timestamp DESC';
    final result = await db.query('transfers', orderBy: orderBy);
    return result.map((json) => HistoryItem.fromMap(json)).toList();
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await instance.database;
    await db.update(
      'transfers',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteItem(String id) async {
    final db = await instance.database;
    await db.delete(
      'transfers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearHistory() async {
    final db = await instance.database;
    await db.delete('transfers');
  }
}
