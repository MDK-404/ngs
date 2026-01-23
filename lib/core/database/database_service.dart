import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

class DatabaseService {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path;
    if (Platform.isWindows) {
      final textDir = Directory('D:\\ngs_db');
      if (!await textDir.exists()) {
        await textDir.create(recursive: true);
      }
      path = join(textDir.path, 'ngs_recordbook.db');
    } else {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      path = join(documentsDirectory.path, 'ngs_recordbook.db');
    }
    print('Opening database at: $path');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  static Future _onCreate(Database db, int version) async {
    // Settings Table
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY DEFAULT 1,
        store_name TEXT DEFAULT 'Noor Grocery Store',
        username TEXT DEFAULT 'admin',
        login_pin_hash TEXT,
        edit_pin_hash TEXT,
        is_separate_pin_enabled INTEGER DEFAULT 0
      )
    ''');

    // Forms Table
    await db.execute('''
      CREATE TABLE forms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Form Columns Table
    await db.execute('''
      CREATE TABLE form_columns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL, -- TEXT, NUMBER, DATE, FORMULA
        formula TEXT,
        FOREIGN KEY (form_id) REFERENCES forms (id) ON DELETE CASCADE
      )
    ''');

    // Records Table
    // Using a simple JSON-based storage for flexible dynamic columns in SQLite
    await db.execute('''
      CREATE TABLE form_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        form_id INTEGER NOT NULL,
        data TEXT NOT NULL, -- JSON format string
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (form_id) REFERENCES forms (id) ON DELETE CASCADE
      )
    ''');

    // Insert Default Settings
    await db.insert('settings', {
      'id': 1,
      'store_name': 'Noor Grocery Store',
      'username': 'admin',
      // Default PINs will be set on first launch if not exists
    });
  }
}
