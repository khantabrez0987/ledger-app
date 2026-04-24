import 'dart:async';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models/company.dart';
import 'models/ledger_mode.dart';
import 'models/ledger_transaction.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._init();
  static Database? _database;

  DbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = await _createDatabasePath();
    _database = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _createDb,
        onUpgrade: (db, oldVersion, newVersion) => _migrateDb(db),
        onOpen: _migrateDb,
      ),
    );
    return _database!;
  }

  Future<String> _createDatabasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, 'ledger_app.db');
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE companies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        address TEXT NOT NULL DEFAULT '',
        mobile_number TEXT NOT NULL DEFAULT '',
        ledger_mode TEXT NOT NULL DEFAULT 'sales',
        created_at TEXT NOT NULL,
        UNIQUE(name, ledger_mode)
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company TEXT NOT NULL,
        ledger_mode TEXT NOT NULL DEFAULT 'sales',
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT,
        note TEXT,
        payment_mode TEXT,
        date TEXT NOT NULL,
        file_number TEXT,
        invoice_number TEXT,
        is_cleared INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future<List<Company>> getCompanies({LedgerMode? mode}) async {
    final db = await database;
    final maps = await db.query(
      'companies',
      where: mode == null ? null : 'ledger_mode = ?',
      whereArgs: mode == null ? null : [mode.name],
      orderBy: 'name COLLATE NOCASE',
    );
    return maps.map((row) => Company.fromMap(row)).toList();
  }

  Future<int> addCompany(Company company) async {
    final db = await database;
    return await db.insert('companies', company.toMap());
  }

  Future<void> updateCompany({
    required Company company,
    required String previousName,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'companies',
        company.toMap(),
        where: 'id = ?',
        whereArgs: [company.id],
      );

      if (previousName != company.name) {
        await txn.update(
          'transactions',
          {'company': company.name},
          where: 'company = ? AND ledger_mode = ?',
          whereArgs: [previousName, company.ledgerMode.name],
        );
      }
    });
  }

  Future<int> deleteCompany(int id) async {
    final db = await database;
    return await db.delete('companies', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<LedgerTransaction>> getTransactions(String companyName,
      {String? searchQuery,
      DateTime? from,
      DateTime? to,
      LedgerMode? mode}) async {
    final db = await database;
    final whereClauses = <String>['company = ?'];
    final whereArgs = <Object>[companyName];
    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClauses.add('''
        (
          category LIKE ? OR
          note LIKE ? OR
          payment_mode LIKE ? OR
          file_number LIKE ? OR
          invoice_number LIKE ?
        )
      ''');
      whereArgs.addAll([
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%',
        '%$searchQuery%',
      ]);
    }

    if (from != null) {
      whereClauses.add('date >= ?');
      whereArgs.add(from.toIso8601String());
    }
    if (to != null) {
      whereClauses.add('date <= ?');
      whereArgs.add(to.toIso8601String());
    }

    final maps = await db.query(
      'transactions',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'date DESC',
    );
    return maps.map((row) => LedgerTransaction.fromMap(row)).toList();
  }

  Future<double> getCompanyBalance(String companyName,
      {LedgerMode? mode}) async {
    final db = await database;
    final whereClauses = <String>['company = ?', 'is_cleared = 0'];
    final whereArgs = <Object>[companyName];
    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }
    final result = await db.rawQuery(
      '''
      SELECT
        SUM(
          CASE
            WHEN type IN ('income', 'credit') THEN amount
            ELSE -amount
          END
        ) AS balance
      FROM transactions
      WHERE ${whereClauses.join(' AND ')}
      ''',
      whereArgs,
    );
    final balanceValue = result.first['balance'];
    if (balanceValue == null) {
      return 0.0;
    }
    return balanceValue is int
        ? balanceValue.toDouble()
        : balanceValue as double;
  }

  Future<int> addTransaction(LedgerTransaction transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction.toMap());
  }

  Future<LedgerTransaction?> getTransactionByInvoiceNumber(
      String companyName, String invoiceNumber,
      {LedgerMode? mode}) async {
    final db = await database;
    final whereClauses = <String>['company = ?', 'invoice_number = ?'];
    final whereArgs = <Object>[companyName, invoiceNumber.trim()];
    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }
    final maps = await db.query(
      'transactions',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return LedgerTransaction.fromMap(maps.first);
  }

  Future<int> updateTransaction(LedgerTransaction transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> updateInvoiceClearStatus({
    required String companyName,
    required String invoiceNumber,
    required bool isCleared,
    LedgerMode? mode,
  }) async {
    final trimmedInvoiceNumber = invoiceNumber.trim();
    if (trimmedInvoiceNumber.isEmpty) {
      return 0;
    }

    final db = await database;
    final whereClauses = <String>['company = ?', 'invoice_number = ?'];
    final whereArgs = <Object>[companyName, trimmedInvoiceNumber];
    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }

    return db.update(
      'transactions',
      {'is_cleared': isCleared ? 1 : 0},
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _migrateDb(Database db) async {
    final companyColumns = await db.rawQuery('PRAGMA table_info(companies)');
    final companyColumnNames =
        companyColumns.map((row) => row['name'] as String).toSet();
    if (!companyColumnNames.contains('ledger_mode')) {
      await db.transaction((txn) async {
        await txn.execute('ALTER TABLE companies RENAME TO companies_old');
        await txn.execute('''
          CREATE TABLE companies(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            address TEXT NOT NULL DEFAULT '',
            mobile_number TEXT NOT NULL DEFAULT '',
            ledger_mode TEXT NOT NULL DEFAULT 'sales',
            created_at TEXT NOT NULL,
            UNIQUE(name, ledger_mode)
          )
        ''');
        await txn.execute('''
          INSERT INTO companies(id, name, address, mobile_number, ledger_mode, created_at)
          SELECT id, name, address, mobile_number, 'sales', created_at
          FROM companies_old
        ''');
        await txn.execute('DROP TABLE companies_old');
      });
    }
    if (!companyColumnNames.contains('address')) {
      await db.execute(
        "ALTER TABLE companies ADD COLUMN address TEXT NOT NULL DEFAULT ''",
      );
    }
    if (!companyColumnNames.contains('mobile_number')) {
      await db.execute(
        "ALTER TABLE companies ADD COLUMN mobile_number TEXT NOT NULL DEFAULT ''",
      );
    }

    final columns = await db.rawQuery('PRAGMA table_info(transactions)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();
    if (!columnNames.contains('file_number')) {
      await db.execute('ALTER TABLE transactions ADD COLUMN file_number TEXT');
    }
    if (!columnNames.contains('invoice_number')) {
      await db
          .execute('ALTER TABLE transactions ADD COLUMN invoice_number TEXT');
    }
    if (!columnNames.contains('payment_mode')) {
      await db.execute('ALTER TABLE transactions ADD COLUMN payment_mode TEXT');
    }
    if (!columnNames.contains('ledger_mode')) {
      await db.execute(
          "ALTER TABLE transactions ADD COLUMN ledger_mode TEXT NOT NULL DEFAULT 'sales'");
    }
    if (!columnNames.contains('is_cleared')) {
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_cleared INTEGER NOT NULL DEFAULT 0');
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
