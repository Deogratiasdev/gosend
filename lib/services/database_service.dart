import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static DatabaseService get instance => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'gosend_pro_v13.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT,
            size TEXT,
            type TEXT, 
            timestamp TEXT,
            status TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE favorites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            ip TEXT,
            port INTEGER
          )
        ''');
      },
    );
  }

  Future<void> insertHistory(Map<String, dynamic> row) async {
    try {
      final db = await database;
      await db.insert('history', row);
    } catch (e) {
      debugPrint("DB Insert Error: \$e");
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    try {
      final db = await database;
      return await db.query('history', orderBy: 'id DESC', limit: 30);
    } catch (e) {
      return [];
    }
  }

  Future<void> insertFavorite(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert('favorites', row);
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    final db = await database;
    return await db.query('favorites');
  }

  Future<void> deleteFavorite(int id) async {
    final db = await database;
    await db.delete('favorites', where: 'id = ?', whereArgs: [id]);
  }
}
