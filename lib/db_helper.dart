import 'dart:async';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models/bill.dart';
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

    // Bills table for tracking invoices with partial payments
    await db.execute('''
      CREATE TABLE bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company TEXT NOT NULL,
        bill_id TEXT NOT NULL,
        date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'unpaid',
        ledger_mode TEXT NOT NULL DEFAULT 'sales',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company, bill_id, ledger_mode)
      )
    ''');

    // Bill payments table for tracking individual payments against bills
    await db.execute('''
      CREATE TABLE bill_payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bill_id INTEGER NOT NULL,
        payment_amount REAL NOT NULL,
        payment_date TEXT NOT NULL,
        payment_mode TEXT NOT NULL DEFAULT 'CASH',
        notes TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(bill_id) REFERENCES bills(id) ON DELETE CASCADE
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

    // Create bills table if it doesn't exist (for new migrations)
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='bills'",
    );
    if (tables.isEmpty) {
      await db.execute('''
        CREATE TABLE bills(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company TEXT NOT NULL,
          bill_id TEXT NOT NULL,
          date TEXT NOT NULL,
          total_amount REAL NOT NULL,
          paid_amount REAL NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'unpaid',
          ledger_mode TEXT NOT NULL DEFAULT 'sales',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          UNIQUE(company, bill_id, ledger_mode)
        )
      ''');
    }

    // Create bill_payments table if it doesn't exist
    final billPaymentTables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='bill_payments'",
    );
    if (billPaymentTables.isEmpty) {
      await db.execute('''
        CREATE TABLE bill_payments(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bill_id INTEGER NOT NULL,
          payment_amount REAL NOT NULL,
          payment_date TEXT NOT NULL,
          payment_mode TEXT NOT NULL DEFAULT 'CASH',
          notes TEXT DEFAULT '',
          created_at TEXT NOT NULL,
          FOREIGN KEY(bill_id) REFERENCES bills(id) ON DELETE CASCADE
        )
      ''');
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ==================== BILL MANAGEMENT FUNCTIONS ====================

  /// Create a new bill for a company
  /// Parameters: company name, bill_id (unique invoice ID), amount, ledger_mode
  Future<int> createBill(Bill bill) async {
    final db = await database;
    return await db.insert('bills', bill.toMap());
  }

  /// Get all bills for a company
  Future<List<Bill>> getBillsByCompany(
    String companyName, {
    LedgerMode? mode,
  }) async {
    final db = await database;
    final whereClauses = <String>['company = ?'];
    final whereArgs = <Object>[companyName];

    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }

    final maps = await db.query(
      'bills',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'date DESC',
    );
    return maps.map((row) => Bill.fromMap(row)).toList();
  }

  /// Get bills by status (unpaid, partial, paid)
  Future<List<Bill>> getBillsByStatus(
    String companyName,
    BillStatus status, {
    LedgerMode? mode,
  }) async {
    final db = await database;
    final whereClauses = <String>['company = ?', 'status = ?'];
    final whereArgs = <Object>[companyName, status.name];

    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }

    final maps = await db.query(
      'bills',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'date ASC',
    );
    return maps.map((row) => Bill.fromMap(row)).toList();
  }

  /// Get a single bill by bill_id
  Future<Bill?> getBillByBillId(
    String companyName,
    String billId, {
    LedgerMode? mode,
  }) async {
    final db = await database;
    final whereClauses = <String>['company = ?', 'bill_id = ?'];
    final whereArgs = <Object>[companyName, billId];

    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }

    final maps = await db.query(
      'bills',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Bill.fromMap(maps.first);
  }

  /// Apply payment to a specific bill
  /// Updates bill's paid_amount and status automatically
  Future<void> applyPaymentToBill({
    required int billId,
    required double paymentAmount,
    required String paymentMode,
    String notes = '',
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // Fetch the bill
      final billMaps = await txn.query(
        'bills',
        where: 'id = ?',
        whereArgs: [billId],
        limit: 1,
      );
      if (billMaps.isEmpty) throw Exception('Bill not found');

      final bill = Bill.fromMap(billMaps.first);

      // Prevent overpayment
      final newPaidAmount = bill.paidAmount + paymentAmount;
      if (newPaidAmount > bill.totalAmount) {
        throw Exception(
          'Payment exceeds bill amount. Max allowed: ${bill.totalAmount - bill.paidAmount}',
        );
      }

      // Create bill payment record
      final payment = BillPayment(
        billId: billId,
        paymentAmount: paymentAmount,
        paymentDate: DateTime.now(),
        paymentMode: paymentMode,
        notes: notes,
      );
      await txn.insert('bill_payments', payment.toMap());

      // Update bill's paid_amount and status
      final updatedBill = bill.copyWith(
        paidAmount: newPaidAmount,
        updatedAt: DateTime.now(),
      );
      await txn.update(
        'bills',
        {
          'paid_amount': updatedBill.paidAmount,
          'status': updatedBill.status.name,
          'updated_at': updatedBill.updatedAt.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [billId],
      );
    });
  }

  /// Auto-adjust payment: Apply payment to oldest unpaid bills (FIFO)
  /// Loops through unpaid/partial bills sorted by date and deducts payment
  Future<List<int>> autoAdjustPayment({
    required String companyName,
    required double paymentAmount,
    required String paymentMode,
    String notes = '',
    LedgerMode? mode,
  }) async {
    final db = await database;
    final appliedToBills = <int>[]; // Track which bills received payment

    await db.transaction((txn) async {
      // Get unpaid and partial bills sorted by date (oldest first)
      final whereClauses = <String>['company = ?', 'status IN (?, ?)'];
      final whereArgs = <Object>[companyName, BillStatus.unpaid.name, BillStatus.partial.name];

      if (mode != null) {
        whereClauses.add('ledger_mode = ?');
        whereArgs.add(mode.name);
      }

      final billMaps = await txn.query(
        'bills',
        where: whereClauses.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'date ASC',
      );

      var remainingPayment = paymentAmount;

      // Apply payment to each bill
      for (final billMap in billMaps) {
        if (remainingPayment <= 0) break;

        final bill = Bill.fromMap(billMap);
        final amountToApply = remainingPayment > bill.remainingAmount
            ? bill.remainingAmount
            : remainingPayment;

        // Apply payment
        final payment = BillPayment(
          billId: bill.id!,
          paymentAmount: amountToApply,
          paymentDate: DateTime.now(),
          paymentMode: paymentMode,
          notes: notes,
        );
        await txn.insert('bill_payments', payment.toMap());

        // Update bill
        final newPaidAmount = bill.paidAmount + amountToApply;
        final updatedBill = bill.copyWith(
          paidAmount: newPaidAmount,
          updatedAt: DateTime.now(),
        );

        await txn.update(
          'bills',
          {
            'paid_amount': updatedBill.paidAmount,
            'status': updatedBill.status.name,
            'updated_at': updatedBill.updatedAt.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [bill.id],
        );

        appliedToBills.add(bill.id!);
        remainingPayment -= amountToApply;
      }
    });

    return appliedToBills;
  }

  /// Get total due amount from unpaid/partial bills for a company
  /// Replaces old balance logic for bill-specific balances
  Future<double> calculateTotalDueByBills(
    String companyName, {
    LedgerMode? mode,
  }) async {
    final db = await database;
    final whereClauses = <String>['company = ?', 'status IN (?, ?)'];
    final whereArgs = <Object>[companyName, BillStatus.unpaid.name, BillStatus.partial.name];

    if (mode != null) {
      whereClauses.add('ledger_mode = ?');
      whereArgs.add(mode.name);
    }

    final result = await db.rawQuery(
      '''
      SELECT SUM(total_amount - paid_amount) AS total_due
      FROM bills
      WHERE ${whereClauses.join(' AND ')}
      ''',
      whereArgs,
    );

    final dueValue = result.first['total_due'];
    if (dueValue == null) return 0.0;
    return dueValue is int ? dueValue.toDouble() : dueValue as double;
  }

  /// Get all payments for a specific bill
  Future<List<BillPayment>> getPaymentsByBill(int billId) async {
    final db = await database;
    final maps = await db.query(
      'bill_payments',
      where: 'bill_id = ?',
      whereArgs: [billId],
      orderBy: 'payment_date DESC',
    );
    return maps.map((row) => BillPayment.fromMap(row)).toList();
  }

  /// Update bill status (for manual status corrections)
  Future<int> updateBillStatus(int billId, BillStatus status) async {
    final db = await database;
    return await db.update(
      'bills',
      {
        'status': status.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [billId],
    );
  }

  /// Delete a bill and its associated payments
  Future<int> deleteBill(int billId) async {
    final db = await database;
    return await db.delete('bills', where: 'id = ?', whereArgs: [billId]);
  }

  /// Get unpaid bills due (for dashboard/summary)
  Future<List<Bill>> getUnpaidBills(
    String companyName, {
    LedgerMode? mode,
  }) async {
    return getBillsByStatus(companyName, BillStatus.unpaid, mode: mode);
  }

  /// Get partially paid bills
  Future<List<Bill>> getPartiallyPaidBills(
    String companyName, {
    LedgerMode? mode,
  }) async {
    return getBillsByStatus(companyName, BillStatus.partial, mode: mode);
  }
}
