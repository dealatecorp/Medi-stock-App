import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _databaseName = 'medistock.db';
  static const int _schemaVersion = 5;
  static const int _pinIterations = 50000;

  Future<Database>? _databaseFuture;

  Future<Database> get database => _databaseFuture ??= _openDatabase();

  Future<Database> _openDatabase() async {
    // The web SQLite adapter stores this database in the browser's IndexedDB.
    // Its database path is a logical name, not a device filesystem path.
    const isWeb = bool.fromEnvironment('dart.library.js_interop');
    final databasePath = isWeb
        ? _databaseName
        : path.join(await getDatabasesPath(), _databaseName);
    return openDatabase(
      databasePath,
      version: _schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE medicines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL DEFAULT '',
            barcode_digits TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL,
            generic_name TEXT NOT NULL DEFAULT '',
            brand_name TEXT NOT NULL DEFAULT '',
            composition TEXT NOT NULL DEFAULT '',
            schedule_category TEXT NOT NULL DEFAULT '',
            dosage_form TEXT NOT NULL DEFAULT '',
            sku TEXT NOT NULL,
            manufacturer TEXT NOT NULL DEFAULT '',
            mfg_date TEXT,
            expiry_date TEXT,
            branch TEXT NOT NULL,
            stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
            threshold_qty INTEGER NOT NULL DEFAULT 0
              CHECK (threshold_qty >= 0),
            cost_paise INTEGER NOT NULL DEFAULT 0 CHECK (cost_paise >= 0),
            price_paise INTEGER NOT NULL DEFAULT 0 CHECK (price_paise >= 0),
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_medicines_sku ON medicines(sku COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX idx_medicines_name ON medicines(name COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX idx_medicines_branch ON medicines(branch COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX idx_medicines_barcode_digits '
          'ON medicines(barcode_digits)',
        );

        await db.execute('''
          CREATE TABLE invoices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_number TEXT NOT NULL UNIQUE,
            customer_name TEXT NOT NULL DEFAULT '',
            customer_phone TEXT NOT NULL DEFAULT '',
            subtotal_paise INTEGER NOT NULL DEFAULT 0
              CHECK (subtotal_paise >= 0),
            tax_paise INTEGER NOT NULL DEFAULT 0 CHECK (tax_paise >= 0),
            discount_paise INTEGER NOT NULL DEFAULT 0
              CHECK (discount_paise >= 0),
            total_paise INTEGER NOT NULL DEFAULT 0 CHECK (total_paise >= 0),
            doctor_name TEXT NOT NULL DEFAULT '',
            payment_method TEXT NOT NULL DEFAULT 'Cash',
            next_refill_date TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE invoice_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_id INTEGER NOT NULL,
            medicine_id INTEGER,
            medicine_name TEXT NOT NULL,
            sku TEXT NOT NULL DEFAULT '',
            qty INTEGER NOT NULL CHECK (qty > 0),
            price_paise INTEGER NOT NULL DEFAULT 0 CHECK (price_paise >= 0),
            line_total_paise INTEGER NOT NULL DEFAULT 0
              CHECK (line_total_paise >= 0),
            discount_percent REAL NOT NULL DEFAULT 0
              CHECK (discount_percent >= 0 AND discount_percent <= 100),
            cost_paise INTEGER NOT NULL DEFAULT 0 CHECK (cost_paise >= 0),
            FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE CASCADE,
            FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE SET NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_invoice_items_invoice_id '
          'ON invoice_items(invoice_id)',
        );
        await _createOperationsSchema(db);
        await _createCommerceSchema(db);
        await _createBranchOrdersSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createOperationsSchema(db);
        }
        if (oldVersion < 3) {
          await _upgradeToVersion3(db);
        }
        if (oldVersion < 4) {
          await _addColumnIfMissing(
            db,
            'staff',
            'shift',
            "TEXT NOT NULL DEFAULT 'A' CHECK (shift IN ('A', 'B', 'C'))",
          );
        }
        if (oldVersion < 5) {
          await _createBranchOrdersSchema(db);
        }
      },
    );
  }

  Future<void> _upgradeToVersion3(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      'medicines',
      'schedule_category',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'medicines',
      'dosage_form',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'invoices',
      'doctor_name',
      "TEXT NOT NULL DEFAULT ''",
    );
    await _addColumnIfMissing(
      db,
      'invoices',
      'payment_method',
      "TEXT NOT NULL DEFAULT 'Cash'",
    );
    await _addColumnIfMissing(db, 'invoices', 'next_refill_date', 'TEXT');
    await _addColumnIfMissing(
      db,
      'invoice_items',
      'discount_percent',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'invoice_items',
      'cost_paise',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _createCommerceSchema(db);
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String declaration,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[table],
    );
    if (tables.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((entry) => entry['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
  }

  Future<void> _createCommerceSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE,
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        gst_number TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_suppliers_active '
      'ON suppliers(is_active)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        supplier_name TEXT NOT NULL,
        invoice_number TEXT NOT NULL COLLATE NOCASE,
        invoice_date TEXT NOT NULL,
        branch TEXT NOT NULL COLLATE NOCASE,
        status TEXT NOT NULL DEFAULT 'draft'
          CHECK (status IN ('draft', 'completed')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (supplier_id, invoice_number),
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
          ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (branch) REFERENCES branches(name)
          ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchases_supplier '
      'ON purchases(supplier_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchases_status_date '
      'ON purchases(status, invoice_date DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchase_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        medicine_id INTEGER,
        product_name TEXT NOT NULL,
        batch_number TEXT NOT NULL DEFAULT '',
        expiry_date TEXT,
        billed_quantity INTEGER NOT NULL DEFAULT 0
          CHECK (billed_quantity >= 0),
        free_quantity INTEGER NOT NULL DEFAULT 0
          CHECK (free_quantity >= 0),
        mrp_paise INTEGER NOT NULL DEFAULT 0 CHECK (mrp_paise >= 0),
        purchase_rate_paise INTEGER NOT NULL DEFAULT 0
          CHECK (purchase_rate_paise >= 0),
        gst_percent REAL NOT NULL DEFAULT 0 CHECK (gst_percent >= 0),
        match_state TEXT NOT NULL DEFAULT 'unmatched',
        match_score REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
        FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE SET NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_lines_purchase '
      'ON purchase_lines(purchase_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_lines_medicine '
      'ON purchase_lines(medicine_id)',
    );
  }

  Future<void> _createOperationsSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS branches (
        name TEXT PRIMARY KEY COLLATE NOCASE,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        display_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT NOT NULL COLLATE NOCASE UNIQUE,
        role TEXT NOT NULL,
        branch TEXT NOT NULL COLLATE NOCASE,
        shift TEXT NOT NULL DEFAULT 'A' CHECK (shift IN ('A', 'B', 'C')),
        pin_salt TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        pin_iterations INTEGER NOT NULL CHECK (pin_iterations > 0),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
        last_login_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (branch) REFERENCES branches(name)
          ON UPDATE CASCADE ON DELETE RESTRICT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_staff_branch ON staff(branch)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_staff_active ON staff(is_active)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS staff_attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id INTEGER NOT NULL,
        attendance_date TEXT NOT NULL,
        first_login_at TEXT NOT NULL,
        last_login_at TEXT NOT NULL,
        login_count INTEGER NOT NULL DEFAULT 1 CHECK (login_count > 0),
        UNIQUE (staff_id, attendance_date),
        FOREIGN KEY (staff_id) REFERENCES staff(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_staff_attendance_date '
      'ON staff_attendance(attendance_date)',
    );

    final now = DateTime.now().toIso8601String();
    for (final entry in medistockBranches.indexed) {
      await db.insert('branches', <String, Object?>{
        'name': entry.$2,
        'is_active': 1,
        'display_order': entry.$1,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _createBranchOrdersSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS branch_orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_medicine_id INTEGER,
        medicine_name TEXT NOT NULL,
        sku TEXT NOT NULL,
        source_branch TEXT NOT NULL COLLATE NOCASE,
        destination_branch TEXT NOT NULL COLLATE NOCASE,
        quantity INTEGER NOT NULL CHECK (quantity > 0),
        status TEXT NOT NULL DEFAULT 'requested'
          CHECK (status IN ('requested', 'dispatched', 'received', 'cancelled')),
        requested_by TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        dispatched_at TEXT,
        received_at TEXT,
        cancelled_at TEXT,
        FOREIGN KEY (source_medicine_id) REFERENCES medicines(id)
          ON DELETE SET NULL,
        FOREIGN KEY (source_branch) REFERENCES branches(name),
        FOREIGN KEY (destination_branch) REFERENCES branches(name)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_branch_orders_source '
      'ON branch_orders(source_branch, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_branch_orders_destination '
      'ON branch_orders(destination_branch, status)',
    );
  }

  Future<void> close() async {
    final pending = _databaseFuture;
    _databaseFuture = null;
    if (pending != null) {
      final db = await pending;
      await db.close();
    }
  }

  Future<List<Medicine>> listMedicines({
    String search = '',
    String? branch,
  }) async {
    final db = await database;
    final term = search.trim();
    final scope = branch?.trim();
    final rows = await db.rawQuery(
      '''
        SELECT * FROM medicines
        WHERE (? IS NULL OR branch = ? COLLATE NOCASE)
          AND (? = '' OR instr(lower(name), lower(?)) > 0
            OR instr(lower(sku), lower(?)) > 0
            OR instr(lower(branch), lower(?)) > 0
            OR instr(lower(brand_name), lower(?)) > 0
            OR instr(lower(generic_name), lower(?)) > 0)
        ORDER BY updated_at DESC, id DESC
      ''',
      <Object?>[scope, scope, term, term, term, term, term, term],
    );
    return List<Medicine>.unmodifiable(rows.map(Medicine.fromMap));
  }

  Future<List<Medicine>> searchMedicines(String query, {String? branch}) =>
      listMedicines(search: query, branch: branch);

  Future<List<Medicine>> listInStockMedicines({String? branch}) async {
    final db = await database;
    final rows = await db.query(
      'medicines',
      where: branch == null
          ? 'stock > 0'
          : 'stock > 0 AND branch = ? COLLATE NOCASE',
      whereArgs: branch == null ? null : <Object?>[branch.trim()],
      orderBy: 'updated_at DESC, id DESC',
    );
    return List<Medicine>.unmodifiable(rows.map(Medicine.fromMap));
  }

  Future<List<Medicine>> listLowStockMedicines({
    int? limit,
    String? branch,
  }) async {
    if (limit != null && limit <= 0) return const <Medicine>[];
    final db = await database;
    final rows = await db.query(
      'medicines',
      where: branch == null
          ? 'stock <= threshold_qty'
          : 'stock <= threshold_qty AND branch = ? COLLATE NOCASE',
      whereArgs: branch == null ? null : <Object?>[branch.trim()],
      orderBy: 'updated_at DESC, id DESC',
      limit: limit,
    );
    return List<Medicine>.unmodifiable(rows.map(Medicine.fromMap));
  }

  Future<Medicine?> getMedicine(int id, {String? branch}) async {
    final db = await database;
    final rows = await db.query(
      'medicines',
      where: branch == null ? 'id = ?' : 'id = ? AND branch = ? COLLATE NOCASE',
      whereArgs: <Object?>[id, if (branch != null) branch.trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : Medicine.fromMap(rows.first);
  }

  Future<Medicine?> lookupMedicineByBarcode(
    String barcode, {
    String? branch,
  }) async {
    final digits = _barcodeDigits(barcode);
    if (digits.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'medicines',
      where: branch == null
          ? 'barcode_digits = ?'
          : 'barcode_digits = ? AND branch = ? COLLATE NOCASE',
      whereArgs: <Object?>[digits, if (branch != null) branch.trim()],
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : Medicine.fromMap(rows.first);
  }

  Future<Medicine> insertMedicine(Medicine medicine, {String? branch}) async {
    final normalized = _normalizeAndValidateMedicine(medicine);
    _requireMedicineBranch(normalized.branch, branch);
    final db = await database;
    final now = DateTime.now();
    final values = _medicineValues(
      normalized.copyWith(createdAt: now, updatedAt: now),
    );
    final id = await db.insert(
      'medicines',
      values,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    final saved = await getMedicine(id);
    if (saved == null) {
      throw StateError('The saved medicine could not be read.');
    }
    return saved;
  }

  Future<Medicine> updateMedicine(Medicine medicine, {String? branch}) async {
    final id = medicine.id;
    if (id == null) {
      throw ArgumentError('A medicine ID is required for an update.');
    }
    final normalized = _normalizeAndValidateMedicine(medicine);
    _requireMedicineBranch(normalized.branch, branch);
    final db = await database;
    final values = _medicineValues(
      normalized.copyWith(updatedAt: DateTime.now()),
    )..remove('created_at');
    final count = await db.update(
      'medicines',
      values,
      where: branch == null ? 'id = ?' : 'id = ? AND branch = ? COLLATE NOCASE',
      whereArgs: <Object?>[id, if (branch != null) branch.trim()],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (count != 1) throw StateError('Medicine not found in your branch.');
    final saved = await getMedicine(id);
    if (saved == null) {
      throw StateError('The updated medicine could not be read.');
    }
    return saved;
  }

  Future<Medicine> saveMedicine(Medicine medicine, {String? branch}) =>
      medicine.id == null
      ? insertMedicine(medicine, branch: branch)
      : updateMedicine(medicine, branch: branch);

  Future<bool> deleteMedicine(int id, {String? branch}) async {
    final db = await database;
    return db.transaction((txn) async {
      final activeOrders = await txn.query(
        'branch_orders',
        columns: <String>['id'],
        where:
            "source_medicine_id = ? AND status IN ('requested', 'dispatched')",
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (activeOrders.isNotEmpty) {
        throw StateError(
          'Finish or cancel this medicine’s branch orders first.',
        );
      }
      return await txn.delete(
            'medicines',
            where: branch == null
                ? 'id = ?'
                : 'id = ? AND branch = ? COLLATE NOCASE',
            whereArgs: <Object?>[id, if (branch != null) branch.trim()],
          ) >
          0;
    });
  }

  Future<List<BranchAvailability>> getBranchAvailability(
    int medicineId, {
    String? branch,
  }) async {
    final db = await database;
    final selectedRows = await db.query(
      'medicines',
      where: branch == null ? 'id = ?' : 'id = ? AND branch = ? COLLATE NOCASE',
      whereArgs: <Object?>[medicineId, if (branch != null) branch.trim()],
      limit: 1,
    );
    if (selectedRows.isEmpty) return const <BranchAvailability>[];

    final selected = Medicine.fromMap(selectedRows.first);
    final rows = await db.rawQuery(
      '''
        SELECT * FROM medicines
        WHERE sku = ? COLLATE NOCASE
          AND (? IS NULL OR branch = ? COLLATE NOCASE)
        ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END,
                 updated_at DESC,
                 id DESC
      ''',
      <Object?>[selected.sku, branch?.trim(), branch?.trim(), medicineId],
    );

    return List<BranchAvailability>.unmodifiable(
      rows.indexed.map((entry) {
        final index = entry.$1;
        final medicine = Medicine.fromMap(entry.$2);
        final isCurrent = medicine.id == medicineId;
        return BranchAvailability(
          medicineId: medicine.id!,
          medicineName: medicine.name,
          sku: medicine.sku,
          branch: medicine.branch,
          stock: medicine.stock,
          isCurrent: isCurrent,
          // Matches the web display: Current, 2 km, 3 km, ...
          distanceKm: isCurrent ? null : index + 1,
        );
      }),
    );
  }

  Future<List<BranchOrder>> listBranchOrders({String? branch}) async {
    final db = await database;
    final selectedBranch = branch?.trim();
    final rows = await db.query(
      'branch_orders',
      where: selectedBranch == null
          ? null
          : 'source_branch = ? COLLATE NOCASE OR '
                'destination_branch = ? COLLATE NOCASE',
      whereArgs: selectedBranch == null
          ? null
          : <Object?>[selectedBranch, selectedBranch],
      orderBy: 'created_at DESC, id DESC',
    );
    return List<BranchOrder>.unmodifiable(rows.map(BranchOrder.fromMap));
  }

  Future<BranchOrder?> getBranchOrder(int id) async {
    final db = await database;
    final rows = await db.query(
      'branch_orders',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : BranchOrder.fromMap(rows.single);
  }

  Future<BranchOrder> createBranchOrder({
    required int sourceMedicineId,
    required String destinationBranch,
    required int quantity,
    required String requestedBy,
    String? requestingBranch,
  }) async {
    if (quantity < 1) throw ArgumentError('Order at least one unit.');
    final destination = destinationBranch.trim();
    if (requestingBranch != null &&
        destination.toLowerCase() != requestingBranch.trim().toLowerCase()) {
      throw StateError('Staff can only request stock for their own branch.');
    }
    final db = await database;
    return db.transaction((txn) async {
      final sourceRows = await txn.query(
        'medicines',
        where: 'id = ?',
        whereArgs: <Object?>[sourceMedicineId],
        limit: 1,
      );
      if (sourceRows.isEmpty)
        throw StateError('Source medicine no longer exists.');
      final source = Medicine.fromMap(sourceRows.single);
      if (source.branch.toLowerCase() == destination.toLowerCase()) {
        throw StateError('Choose a different source branch.');
      }
      if (source.stock < quantity) {
        throw StateError(
          'Only ${source.stock} units are available at ${source.branch}.',
        );
      }
      final branches = await txn.query(
        'branches',
        columns: <String>['name'],
        where: 'name = ? COLLATE NOCASE AND is_active = 1',
        whereArgs: <Object?>[destination],
        limit: 1,
      );
      if (branches.isEmpty)
        throw StateError('Destination branch is not active.');
      final now = DateTime.now().toIso8601String();
      final id = await txn.insert('branch_orders', <String, Object?>{
        'source_medicine_id': sourceMedicineId,
        'medicine_name': source.name,
        'sku': source.sku,
        'source_branch': source.branch,
        'destination_branch': branches.single['name'],
        'quantity': quantity,
        'status': 'requested',
        'requested_by': requestedBy.trim(),
        'created_at': now,
        'updated_at': now,
      });
      final rows = await txn.query(
        'branch_orders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      return BranchOrder.fromMap(rows.single);
    });
  }

  Future<BranchOrder> dispatchBranchOrder(int id, {String? actorBranch}) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'branch_orders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Order no longer exists.');
      final order = BranchOrder.fromMap(rows.single);
      if (!order.isRequested)
        throw StateError('Only requested orders can be dispatched.');
      if (actorBranch != null &&
          actorBranch.trim().toLowerCase() !=
              order.sourceBranch.toLowerCase()) {
        throw StateError('Only the source branch can dispatch this order.');
      }
      final sourceId = order.sourceMedicineId;
      if (sourceId == null)
        throw StateError('Source medicine no longer exists.');
      final changed = await txn.rawUpdate(
        '''UPDATE medicines SET stock = stock - ?, updated_at = ?
           WHERE id = ? AND branch = ? COLLATE NOCASE
             AND sku = ? COLLATE NOCASE AND stock >= ?''',
        <Object?>[
          order.quantity,
          DateTime.now().toIso8601String(),
          sourceId,
          order.sourceBranch,
          order.sku,
          order.quantity,
        ],
      );
      if (changed != 1) {
        throw StateError(
          'Source stock changed. Refresh and check availability.',
        );
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'branch_orders',
        <String, Object?>{
          'status': 'dispatched',
          'updated_at': now,
          'dispatched_at': now,
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object?>[id, 'requested'],
      );
      final updated = await txn.query(
        'branch_orders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return BranchOrder.fromMap(updated.single);
    });
  }

  Future<BranchOrder> receiveBranchOrder(int id, {String? actorBranch}) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'branch_orders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Order no longer exists.');
      final order = BranchOrder.fromMap(rows.single);
      if (!order.isDispatched)
        throw StateError('Dispatch the order before receiving it.');
      if (actorBranch != null &&
          actorBranch.trim().toLowerCase() !=
              order.destinationBranch.toLowerCase()) {
        throw StateError('Only the destination branch can receive this order.');
      }
      final sourceId = order.sourceMedicineId;
      if (sourceId == null)
        throw StateError('Source medicine no longer exists.');
      final sourceRows = await txn.query(
        'medicines',
        where: 'id = ?',
        whereArgs: <Object?>[sourceId],
        limit: 1,
      );
      if (sourceRows.isEmpty)
        throw StateError('Source medicine no longer exists.');
      final source = Medicine.fromMap(sourceRows.single);
      final targetRows = await txn.query(
        'medicines',
        where: 'sku = ? COLLATE NOCASE AND branch = ? COLLATE NOCASE',
        whereArgs: <Object?>[order.sku, order.destinationBranch],
        orderBy: 'updated_at DESC, id DESC',
        limit: 1,
      );
      final now = DateTime.now().toIso8601String();
      if (targetRows.isEmpty) {
        final target = Medicine(
          barcode: source.barcode,
          name: source.name,
          genericName: source.genericName,
          brandName: source.brandName,
          composition: source.composition,
          scheduleCategory: source.scheduleCategory,
          dosageForm: source.dosageForm,
          sku: source.sku,
          manufacturer: source.manufacturer,
          mfgDate: source.mfgDate,
          expiryDate: source.expiryDate,
          branch: order.destinationBranch,
          stock: order.quantity,
          reorderThreshold: source.reorderThreshold,
          costPaise: source.costPaise,
          pricePaise: source.pricePaise,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await txn.insert('medicines', _medicineValues(target));
      } else {
        await txn.rawUpdate(
          'UPDATE medicines SET stock = stock + ?, updated_at = ? WHERE id = ?',
          <Object?>[order.quantity, now, targetRows.single['id']],
        );
      }
      await txn.update(
        'branch_orders',
        <String, Object?>{
          'status': 'received',
          'updated_at': now,
          'received_at': now,
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object?>[id, 'dispatched'],
      );
      final updated = await txn.query(
        'branch_orders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return BranchOrder.fromMap(updated.single);
    });
  }

  Future<BranchOrder> cancelBranchOrder(int id, {String? actorBranch}) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'branch_orders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Order no longer exists.');
      final order = BranchOrder.fromMap(rows.single);
      if (!order.isRequested)
        throw StateError('Only requested orders can be cancelled.');
      final branch = actorBranch?.trim().toLowerCase();
      if (branch != null &&
          branch != order.sourceBranch.toLowerCase() &&
          branch != order.destinationBranch.toLowerCase()) {
        throw StateError('This order is not for your branch.');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update(
        'branch_orders',
        <String, Object?>{
          'status': 'cancelled',
          'updated_at': now,
          'cancelled_at': now,
        },
        where: 'id = ? AND status = ?',
        whereArgs: <Object?>[id, 'requested'],
      );
      final updated = await txn.query(
        'branch_orders',
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return BranchOrder.fromMap(updated.single);
    });
  }

  Future<int> seedSampleData() async {
    final db = await database;
    final samples = <Medicine>[
      Medicine(
        barcode: '8901234560011',
        name: 'Paracetamol 500mg Tablets',
        genericName: 'Paracetamol',
        brandName: 'Dolo',
        composition: 'Paracetamol IP 500mg',
        sku: 'PCM500-A1',
        manufacturer: 'Micro Labs',
        mfgDate: DateTime(2026),
        expiryDate: DateTime(2027),
        branch: 'Main Branch',
        stock: 120,
        reorderThreshold: 25,
        costPaise: 120,
        pricePaise: 250,
      ),
      Medicine(
        barcode: '8901234560028',
        name: 'Amoxicillin 500mg Capsules',
        genericName: 'Amoxicillin',
        brandName: 'Mox',
        composition: 'Amoxicillin 500mg',
        sku: 'AMX500-B2',
        manufacturer: 'Cipla',
        mfgDate: DateTime(2026, 2),
        expiryDate: DateTime(2027, 2),
        branch: 'Main Branch',
        stock: 18,
        reorderThreshold: 20,
        costPaise: 450,
        pricePaise: 800,
      ),
      Medicine(
        barcode: '8901234560035',
        name: 'Cetirizine 10mg Tablets',
        genericName: 'Cetirizine',
        brandName: 'Cetzine',
        composition: 'Cetirizine 10mg',
        sku: 'CTZ10-C1',
        manufacturer: 'Dr Reddy',
        mfgDate: DateTime(2026, 3),
        expiryDate: DateTime(2028, 3),
        branch: 'City Branch',
        stock: 75,
        reorderThreshold: 15,
        costPaise: 80,
        pricePaise: 150,
      ),
      Medicine(
        barcode: '8901234560042',
        name: 'Pantoprazole 40mg Tablets',
        genericName: 'Pantoprazole',
        brandName: 'Pan-D',
        composition: 'Pantoprazole 40mg',
        sku: 'PAN40-D4',
        manufacturer: 'Sun Pharma',
        mfgDate: DateTime(2026, 1, 15),
        expiryDate: DateTime(2027, 9, 15),
        branch: 'North Branch',
        stock: 9,
        reorderThreshold: 15,
        costPaise: 300,
        pricePaise: 600,
      ),
    ];

    await db.transaction((txn) async {
      for (final sample in samples) {
        final normalized = _normalizeAndValidateMedicine(sample);
        final now = DateTime.now();
        await txn.insert(
          'medicines',
          _medicineValues(normalized.copyWith(createdAt: now, updatedAt: now)),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
    return samples.length;
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('branch_orders');
      await txn.delete('staff_attendance');
      await txn.delete('staff');
      await txn.delete('purchase_lines');
      await txn.delete('purchases');
      await txn.delete('suppliers');
      await txn.delete('invoice_items');
      await txn.delete('invoices');
      await txn.delete('medicines');
      await txn.update('branches', <String, Object?>{
        'is_active': 1,
        'updated_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<Supplier>> listSuppliers({
    String search = '',
    bool includeInactive = true,
  }) async {
    final db = await database;
    final term = search.trim();
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (!includeInactive) clauses.add('is_active = 1');
    if (term.isNotEmpty) {
      clauses.add('''
        (instr(lower(name), lower(?)) > 0
          OR instr(lower(phone), lower(?)) > 0
          OR instr(lower(email), lower(?)) > 0
          OR instr(lower(gst_number), lower(?)) > 0)
      ''');
      arguments.addAll(<Object?>[term, term, term, term]);
    }
    final rows = await db.query(
      'suppliers',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'is_active DESC, name COLLATE NOCASE ASC',
    );
    return List<Supplier>.unmodifiable(rows.map(Supplier.fromMap));
  }

  Future<Supplier?> getSupplier(int id) async {
    if (id <= 0) return null;
    final db = await database;
    return _getSupplier(db, id);
  }

  Future<Supplier> saveSupplier(Supplier supplier) async {
    final normalized = _normalizeAndValidateSupplier(supplier);
    final db = await database;
    final now = DateTime.now();
    return db.transaction((txn) async {
      final duplicates = await txn.query(
        'suppliers',
        columns: <String>['id'],
        where: normalized.id == null
            ? 'name = ? COLLATE NOCASE'
            : 'name = ? COLLATE NOCASE AND id <> ?',
        whereArgs: normalized.id == null
            ? <Object?>[normalized.name]
            : <Object?>[normalized.name, normalized.id],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        throw ArgumentError.value(
          normalized.name,
          'name',
          'A supplier already uses this name.',
        );
      }

      late final int id;
      if (normalized.id == null) {
        id = await txn.insert('suppliers', <String, Object?>{
          ...normalized.toMap(),
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      } else {
        id = normalized.id!;
        final changed = await txn.update(
          'suppliers',
          <String, Object?>{
            ...normalized.toMap(),
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        if (changed != 1) throw StateError('Supplier not found.');
      }
      final saved = await _getSupplier(txn, id);
      if (saved == null)
        throw StateError('The saved supplier could not be read.');
      return saved;
    });
  }

  Future<bool> deleteSupplier(int id) async {
    if (id <= 0) return false;
    final db = await database;
    return db.transaction((txn) async {
      final linked = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM purchases WHERE supplier_id = ?',
        <Object?>[id],
      );
      if (_asInt(linked.first['count']) > 0) {
        throw StateError('Suppliers with purchase history cannot be deleted.');
      }
      return await txn.delete(
            'suppliers',
            where: 'id = ?',
            whereArgs: <Object?>[id],
          ) >
          0;
    });
  }

  Future<List<PurchaseRecord>> listPurchases({
    String search = '',
    String? status,
  }) async {
    final normalizedStatus = status?.trim().toLowerCase();
    if (normalizedStatus != null &&
        normalizedStatus.isNotEmpty &&
        normalizedStatus != 'draft' &&
        normalizedStatus != 'completed') {
      throw ArgumentError.value(status, 'status', 'Use draft or completed.');
    }
    final term = search.trim();
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (normalizedStatus != null && normalizedStatus.isNotEmpty) {
      clauses.add('status = ?');
      arguments.add(normalizedStatus);
    }
    if (term.isNotEmpty) {
      clauses.add('''
        (instr(lower(invoice_number), lower(?)) > 0
          OR instr(lower(supplier_name), lower(?)) > 0
          OR instr(lower(branch), lower(?)) > 0)
      ''');
      arguments.addAll(<Object?>[term, term, term]);
    }
    final db = await database;
    final rows = await db.query(
      'purchases',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'invoice_date DESC, updated_at DESC, id DESC',
    );
    if (rows.isEmpty) return const <PurchaseRecord>[];
    final ids = rows.map((row) => _asInt(row['id'])).toList(growable: false);
    final lines = await _loadPurchaseLines(db, ids);
    return List<PurchaseRecord>.unmodifiable(
      rows.map((row) {
        final id = _asInt(row['id']);
        return PurchaseRecord.fromMap(
          row,
          lines: lines[id] ?? const <PurchaseLine>[],
        );
      }),
    );
  }

  Future<PurchaseRecord?> getPurchase(int id) async {
    if (id <= 0) return null;
    final db = await database;
    return _getPurchase(db, id);
  }

  /// Inserts or autosaves a draft, replacing its line snapshot atomically.
  Future<PurchaseRecord> savePurchase(PurchaseRecord purchase) async {
    final normalized = _normalizeAndValidatePurchase(purchase);
    if (normalized.status != 'draft') {
      throw StateError('Only draft purchases can be saved.');
    }
    final db = await database;
    final now = DateTime.now();
    return db.transaction((txn) async {
      final supplier = await _getSupplier(txn, normalized.supplierId);
      if (supplier == null) throw StateError('Supplier not found.');

      late final int purchaseId;
      if (normalized.id == null) {
        purchaseId = await txn.insert('purchases', <String, Object?>{
          'supplier_id': supplier.id,
          'supplier_name': supplier.name,
          'invoice_number': normalized.invoiceNumber,
          'invoice_date': _dateOnly(normalized.invoiceDate),
          'branch': normalized.branch,
          'status': 'draft',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      } else {
        purchaseId = normalized.id!;
        final existingRows = await txn.query(
          'purchases',
          columns: <String>['status'],
          where: 'id = ?',
          whereArgs: <Object?>[purchaseId],
          limit: 1,
        );
        if (existingRows.isEmpty) throw StateError('Purchase not found.');
        if (existingRows.first['status'] == 'completed') {
          throw StateError('A completed purchase cannot be edited.');
        }
        final changed = await txn.update(
          'purchases',
          <String, Object?>{
            'supplier_id': supplier.id,
            'supplier_name': supplier.name,
            'invoice_number': normalized.invoiceNumber,
            'invoice_date': _dateOnly(normalized.invoiceDate),
            'branch': normalized.branch,
            'updated_at': now.toIso8601String(),
          },
          where: 'id = ? AND status = ?',
          whereArgs: <Object?>[purchaseId, 'draft'],
        );
        if (changed != 1)
          throw StateError('Purchase draft could not be saved.');
        await txn.delete(
          'purchase_lines',
          where: 'purchase_id = ?',
          whereArgs: <Object?>[purchaseId],
        );
      }

      for (final line in normalized.lines) {
        await txn.insert('purchase_lines', <String, Object?>{
          ...line.toMap(),
          'purchase_id': purchaseId,
        });
      }
      final saved = await _getPurchase(txn, purchaseId);
      if (saved == null)
        throw StateError('The saved purchase could not be read.');
      return saved;
    });
  }

  Future<bool> deletePurchase(int id) async {
    if (id <= 0) return false;
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'purchases',
        columns: <String>['status'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      if (rows.first['status'] == 'completed') {
        throw StateError('A completed purchase cannot be deleted.');
      }
      return await txn.delete(
            'purchases',
            where: 'id = ?',
            whereArgs: <Object?>[id],
          ) >
          0;
    });
  }

  /// Posts a draft into inventory exactly once.
  Future<PurchaseRecord> completePurchase(int id) async {
    if (id <= 0) throw ArgumentError.value(id, 'id', 'Must be positive.');
    final db = await database;
    return db.transaction((txn) async {
      final purchase = await _getPurchase(txn, id);
      if (purchase == null) throw StateError('Purchase not found.');
      if (purchase.isCompleted) {
        throw StateError('This purchase has already been completed.');
      }
      if (purchase.lines.isEmpty) {
        throw StateError('Add at least one purchase line before completing.');
      }
      if (purchase.lines.any((line) => line.medicineId == null)) {
        throw StateError('Every purchase line must be mapped to a medicine.');
      }

      final now = DateTime.now().toIso8601String();
      for (final line in purchase.lines) {
        if (line.receivedQuantity <= 0) {
          throw StateError(
            '${line.productName} must have a received quantity.',
          );
        }
        final changed = await txn.rawUpdate(
          '''
            UPDATE medicines
            SET stock = stock + ?,
                cost_paise = ?,
                price_paise = ?,
                expiry_date = ?,
                updated_at = ?
            WHERE id = ? AND branch = ?
          ''',
          <Object?>[
            line.receivedQuantity,
            line.purchaseRatePaise,
            line.mrpPaise,
            _dateOnly(line.expiryDate),
            now,
            line.medicineId,
            purchase.branch,
          ],
        );
        if (changed != 1) {
          throw StateError(
            'Mapped medicine not found in ${purchase.branch} for ${line.productName}.',
          );
        }
      }
      final changed = await txn.update(
        'purchases',
        <String, Object?>{'status': 'completed', 'updated_at': now},
        where: 'id = ? AND status = ?',
        whereArgs: <Object?>[id, 'draft'],
      );
      if (changed != 1) {
        throw StateError('This purchase has already been completed.');
      }
      final completed = await _getPurchase(txn, id);
      if (completed == null) throw StateError('Completed purchase not found.');
      return completed;
    });
  }

  /// Returns locally saved medicines ordered by an offline fuzzy score.
  Future<List<MedicineMatch>> findMedicineCandidates(
    String query, {
    int limit = 5,
    String? branch,
  }) async {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty || limit <= 0) {
      return const <MedicineMatch>[];
    }
    final medicines = await listMedicines(branch: branch);
    final matches = <MedicineMatch>[];
    for (final medicine in medicines) {
      final fields = <String>[
        medicine.name,
        medicine.genericName,
        medicine.brandName,
        medicine.composition,
        medicine.sku,
      ];
      var best = 0.0;
      for (final field in fields) {
        best = max(best, _fuzzyScore(normalizedQuery, field));
      }
      if (best >= 0.2)
        matches.add(MedicineMatch(medicine: medicine, score: best));
    }
    matches.sort((first, second) {
      final score = second.score.compareTo(first.score);
      if (score != 0) return score;
      return first.medicine.name.compareTo(second.medicine.name);
    });
    return List<MedicineMatch>.unmodifiable(matches.take(limit));
  }

  Future<LastPurchaseInfo?> getLastPurchaseInfo(
    int medicineId, {
    String? branch,
  }) async {
    if (medicineId <= 0) return null;
    final db = await database;
    final rows = await db.rawQuery(
      '''
        SELECT pl.purchase_rate_paise, p.supplier_name, p.invoice_date
        FROM purchase_lines pl
        INNER JOIN purchases p ON p.id = pl.purchase_id
        WHERE pl.medicine_id = ? AND p.status = 'completed'
          AND (? IS NULL OR EXISTS (
            SELECT 1 FROM medicines m
            WHERE m.id = pl.medicine_id AND m.branch = ? COLLATE NOCASE
          ))
        ORDER BY p.invoice_date DESC, p.updated_at DESC, pl.id DESC
        LIMIT 1
      ''',
      <Object?>[medicineId, branch?.trim(), branch?.trim()],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return LastPurchaseInfo(
      purchaseRatePaise: _asInt(row['purchase_rate_paise']),
      supplierName: row['supplier_name']?.toString() ?? '',
      invoiceDate:
          DateTime.tryParse(row['invoice_date']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Future<List<InvoiceRecord>> listInvoices({String search = ''}) async {
    final db = await database;
    final term = search.trim();
    final rows = term.isEmpty
        ? await db.query('invoices', orderBy: 'created_at DESC, id DESC')
        : await db.rawQuery(
            '''
              SELECT * FROM invoices
              WHERE instr(lower(invoice_number), lower(?)) > 0
                 OR instr(lower(customer_name), lower(?)) > 0
                 OR instr(lower(customer_phone), lower(?)) > 0
              ORDER BY created_at DESC, id DESC
            ''',
            <Object?>[term, term, term],
          );
    if (rows.isEmpty) return const <InvoiceRecord>[];

    final ids = rows.map((row) => row['id']! as int).toList(growable: false);
    final itemsByInvoice = await _loadInvoiceItems(db, ids);
    return List<InvoiceRecord>.unmodifiable(
      rows.map((row) {
        final id = row['id']! as int;
        return InvoiceRecord.fromMap(
          row,
          items: itemsByInvoice[id] ?? const <InvoiceItem>[],
        );
      }),
    );
  }

  Future<List<InvoiceRecord>> searchInvoices(String query) =>
      listInvoices(search: query);

  Future<InvoiceRecord?> getInvoice(int id) async {
    final db = await database;
    final rows = await db.query(
      'invoices',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final itemsByInvoice = await _loadInvoiceItems(db, <int>[id]);
    return InvoiceRecord.fromMap(
      rows.first,
      items: itemsByInvoice[id] ?? const <InvoiceItem>[],
    );
  }

  Future<InvoiceRecord> createInvoice({
    required List<CartItem> cartItems,
    String? branch,
    String customerName = 'Walk-in patient',
    required String customerPhone,
    double taxPercent = 0,
    double discountPercent = 0,
    String doctorName = '',
    String paymentMethod = 'Cash',
    DateTime? nextRefillDate,
  }) async {
    if (cartItems.isEmpty) {
      throw ArgumentError('Add at least one bill item.');
    }
    final phone = customerPhone.trim();
    if (phone.isEmpty) {
      throw ArgumentError('Enter patient phone number for WhatsApp invoice.');
    }
    _validatePercentage(taxPercent, 'taxPercent');
    _validatePercentage(discountPercent, 'discountPercent', maximum: 100);
    for (final item in cartItems) {
      _validatePercentage(
        item.discountPercent,
        'item.discountPercent',
        maximum: 100,
      );
    }

    // Merge duplicate medicine IDs before validating stock and writing rows.
    final quantities = <int, int>{};
    for (final item in cartItems) {
      if (item.medicineId <= 0) {
        throw ArgumentError.value(
          item.medicineId,
          'medicineId',
          'Must refer to a saved medicine.',
        );
      }
      if (item.quantity <= 0) {
        throw ArgumentError.value(
          item.quantity,
          'quantity',
          'Bill quantity must be a positive integer.',
        );
      }
      quantities.update(
        item.medicineId,
        (quantity) => quantity + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }

    final db = await database;
    return db.transaction((txn) async {
      final currentMedicines = <int, Medicine>{};
      for (final entry in quantities.entries) {
        final rows = await txn.query(
          'medicines',
          where: branch == null
              ? 'id = ?'
              : 'id = ? AND branch = ? COLLATE NOCASE',
          whereArgs: <Object?>[entry.key, if (branch != null) branch.trim()],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Medicine not found for bill item ${entry.key}.');
        }
        final medicine = Medicine.fromMap(rows.first);
        if (medicine.stock < entry.value) {
          throw StateError(
            '${medicine.name} has only ${medicine.stock} quantity available.',
          );
        }
        currentMedicines[entry.key] = medicine;
      }

      var subtotalPaise = 0;
      var lineDiscountPaise = 0;
      for (final item in cartItems) {
        final medicine = currentMedicines[item.medicineId]!;
        final gross = medicine.pricePaise * item.quantity;
        subtotalPaise += gross;
        lineDiscountPaise += (gross * item.discountPercent / 100).round();
      }
      final taxPaise = (subtotalPaise * taxPercent / 100).round();
      final globalDiscountPaise = (subtotalPaise * discountPercent / 100)
          .round();
      final discountPaise = lineDiscountPaise + globalDiscountPaise;
      final totalPaise = subtotalPaise + taxPaise - discountPaise;
      final safeTotalPaise = totalPaise < 0 ? 0 : totalPaise;
      final now = DateTime.now();
      final number = await _nextInvoiceNumber(txn, now);
      final patient = customerName.trim().isEmpty
          ? 'Walk-in patient'
          : customerName.trim();
      final normalizedDoctor = doctorName.trim();
      final normalizedPayment = paymentMethod.trim().isEmpty
          ? 'Cash'
          : paymentMethod.trim();

      final invoiceId = await txn.insert('invoices', <String, Object?>{
        'invoice_number': number,
        'customer_name': patient,
        'customer_phone': phone,
        'subtotal_paise': subtotalPaise,
        'tax_paise': taxPaise,
        'discount_paise': discountPaise,
        'total_paise': safeTotalPaise,
        'doctor_name': normalizedDoctor,
        'payment_method': normalizedPayment,
        'next_refill_date': _dateOnly(nextRefillDate),
        'created_at': now.toIso8601String(),
      });

      final savedItems = <InvoiceItem>[];
      for (final cartItem in cartItems) {
        final medicine = currentMedicines[cartItem.medicineId]!;
        final quantity = cartItem.quantity;
        final lineGrossPaise = medicine.pricePaise * quantity;
        final itemDiscountPaise =
            (lineGrossPaise * cartItem.discountPercent / 100).round();
        final lineTotalPaise = lineGrossPaise - itemDiscountPaise;
        final itemId = await txn.insert('invoice_items', <String, Object?>{
          'invoice_id': invoiceId,
          'medicine_id': medicine.id,
          'medicine_name': medicine.name,
          'sku': medicine.sku,
          'qty': quantity,
          'price_paise': medicine.pricePaise,
          'line_total_paise': lineTotalPaise,
          'discount_percent': cartItem.discountPercent,
          'cost_paise': medicine.costPaise,
        });

        // The guarded update makes the stock check safe even if this method is
        // called concurrently from more than one UI action.
        final changed = await txn.rawUpdate(
          '''
            UPDATE medicines
            SET stock = stock - ?, updated_at = ?
            WHERE id = ? AND stock >= ?
              AND (? IS NULL OR branch = ? COLLATE NOCASE)
          ''',
          <Object?>[
            quantity,
            now.toIso8601String(),
            medicine.id,
            quantity,
            branch?.trim(),
            branch?.trim(),
          ],
        );
        if (changed != 1) {
          throw StateError(
            '${medicine.name} no longer has enough quantity available.',
          );
        }

        savedItems.add(
          InvoiceItem(
            id: itemId,
            invoiceId: invoiceId,
            medicineId: medicine.id,
            medicineName: medicine.name,
            sku: medicine.sku,
            quantity: quantity,
            unitPricePaise: medicine.pricePaise,
            lineTotalPaise: lineTotalPaise,
            discountPercent: cartItem.discountPercent,
            costPaise: medicine.costPaise,
          ),
        );
      }

      return InvoiceRecord(
        id: invoiceId,
        number: number,
        customerName: patient,
        customerPhone: phone,
        subtotalPaise: subtotalPaise,
        taxPaise: taxPaise,
        discountPaise: discountPaise,
        totalPaise: safeTotalPaise,
        createdAt: now,
        doctorName: normalizedDoctor,
        paymentMethod: normalizedPayment,
        nextRefillDate: nextRefillDate,
        items: List<InvoiceItem>.unmodifiable(savedItems),
      );
    });
  }

  Future<DashboardStats> getDashboardStats({String? branch}) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        (SELECT COUNT(*) FROM medicines
          WHERE (? IS NULL OR branch = ? COLLATE NOCASE)) AS total_medicines,
        (SELECT COALESCE(SUM(stock * cost_paise), 0) FROM medicines
          WHERE (? IS NULL OR branch = ? COLLATE NOCASE))
          AS stock_value_paise,
        (SELECT COUNT(*) FROM medicines WHERE stock <= threshold_qty
          AND (? IS NULL OR branch = ? COLLATE NOCASE))
          AS low_stock_count,
        (SELECT COALESCE(SUM(total_paise), 0) FROM invoices)
          AS total_sales_paise
    ''',
      <Object?>[
        branch?.trim(),
        branch?.trim(),
        branch?.trim(),
        branch?.trim(),
        branch?.trim(),
        branch?.trim(),
      ],
    );
    final row = rows.first;
    return DashboardStats(
      totalMedicines: _asInt(row['total_medicines']),
      stockValuePaise: _asInt(row['stock_value_paise']),
      lowStockCount: _asInt(row['low_stock_count']),
      totalSalesPaise: _asInt(row['total_sales_paise']),
    );
  }

  /// Returns operational totals for every branch, including inactive ones.
  Future<List<BranchSummary>> listBranchSummaries() async {
    final db = await database;
    final today = _dateKey(DateTime.now());
    final rows = await db.rawQuery(
      '''
        SELECT
          b.name AS branch,
          b.is_active,
          (SELECT COUNT(*) FROM medicines m
            WHERE m.branch = b.name COLLATE NOCASE) AS medicine_count,
          (SELECT COALESCE(SUM(m.stock), 0) FROM medicines m
            WHERE m.branch = b.name COLLATE NOCASE) AS total_units,
          (SELECT COUNT(*) FROM medicines m
            WHERE m.branch = b.name COLLATE NOCASE
              AND m.stock <= m.threshold_qty) AS low_stock_count,
          (SELECT COALESCE(SUM(m.stock * m.cost_paise), 0) FROM medicines m
            WHERE m.branch = b.name COLLATE NOCASE) AS stock_value_paise,
          (SELECT COUNT(*) FROM staff s
            WHERE s.branch = b.name COLLATE NOCASE
              AND s.is_active = 1) AS active_staff_count,
          (SELECT COALESCE(SUM(a.login_count), 0)
             FROM staff_attendance a
             INNER JOIN staff s ON s.id = a.staff_id
            WHERE s.branch = b.name COLLATE NOCASE
              AND a.attendance_date = ?) AS today_check_ins
        FROM branches b
        ORDER BY b.display_order ASC, b.name COLLATE NOCASE ASC
      ''',
      <Object?>[today],
    );
    return List<BranchSummary>.unmodifiable(rows.map(BranchSummary.fromMap));
  }

  /// Changes whether a branch is operational and returns its refreshed totals.
  Future<BranchSummary> setBranchActive(String name, bool isActive) async {
    final branch = _normalizeBranch(name);
    final db = await database;
    final changed = await db.update(
      'branches',
      <String, Object?>{
        'is_active': isActive ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'name = ? COLLATE NOCASE',
      whereArgs: <Object?>[branch],
    );
    if (changed != 1) throw StateError('Branch not found.');
    final summaries = await listBranchSummaries();
    return summaries.firstWhere(
      (summary) => summary.name.toLowerCase() == branch.toLowerCase(),
    );
  }

  Future<List<StaffMember>> listStaff({String query = ''}) async {
    final db = await database;
    final today = _dateKey(DateTime.now());
    final term = query.trim();
    final filter = term.isEmpty
        ? ''
        : '''
          AND (instr(lower(s.name), lower(?)) > 0
            OR instr(lower(s.email), lower(?)) > 0
            OR instr(lower(s.role), lower(?)) > 0
            OR instr(lower(s.branch), lower(?)) > 0)
        ''';
    final args = <Object?>[
      today,
      if (term.isNotEmpty) ...<Object?>[term, term, term, term],
    ];
    final rows = await db.rawQuery('''
        SELECT s.*, COALESCE(a.login_count, 0) AS today_login_count
        FROM staff s
        LEFT JOIN staff_attendance a
          ON a.staff_id = s.id AND a.attendance_date = ?
        WHERE 1 = 1 $filter
        ORDER BY s.is_active DESC, s.last_login_at DESC,
                 s.name COLLATE NOCASE ASC
      ''', args);
    return List<StaffMember>.unmodifiable(rows.map(StaffMember.fromMap));
  }

  Future<StaffMember?> getStaffById(int id) async {
    if (id <= 0) return null;
    final db = await database;
    return _getStaffById(db, id, _dateKey(DateTime.now()));
  }

  /// Creates or updates a staff profile.
  ///
  /// A 4-8 digit PIN is mandatory when creating a profile. During an update,
  /// omit [pin] to preserve the existing credential. Only a salted PBKDF2
  /// digest is persisted; the raw PIN is never written to storage.
  Future<StaffMember> saveStaff(StaffMember staff, {String? pin}) async {
    final normalized = _normalizeAndValidateStaff(staff);
    final creating = normalized.id == null;
    final normalizedPin = pin?.trim();
    if (creating && (normalizedPin == null || normalizedPin.isEmpty)) {
      throw ArgumentError('A PIN is required when creating staff.');
    }
    if (normalizedPin != null && normalizedPin.isNotEmpty) {
      _validatePin(normalizedPin);
    }

    final db = await database;
    final now = DateTime.now();
    return db.transaction((txn) async {
      final duplicates = await txn.query(
        'staff',
        columns: <String>['id'],
        where: creating
            ? 'email = ? COLLATE NOCASE'
            : 'email = ? COLLATE NOCASE AND id <> ?',
        whereArgs: creating
            ? <Object?>[normalized.email]
            : <Object?>[normalized.email, normalized.id],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        throw ArgumentError.value(
          normalized.email,
          'email',
          'A staff member already uses this email address.',
        );
      }

      late final int id;
      if (creating) {
        final credential = _createPinCredential(normalizedPin!);
        id = await txn.insert('staff', <String, Object?>{
          'name': normalized.name,
          'email': normalized.email,
          'role': normalized.role,
          'branch': normalized.branch,
          'shift': normalized.shift,
          'pin_salt': credential.salt,
          'pin_hash': credential.hash,
          'pin_iterations': _pinIterations,
          'is_active': normalized.isActive ? 1 : 0,
          'last_login_at': null,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      } else {
        id = normalized.id!;
        final existing = await txn.query(
          'staff',
          columns: <String>['id'],
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        if (existing.isEmpty) throw StateError('Staff member not found.');

        final values = <String, Object?>{
          'name': normalized.name,
          'email': normalized.email,
          'role': normalized.role,
          'branch': normalized.branch,
          'shift': normalized.shift,
          'is_active': normalized.isActive ? 1 : 0,
          'updated_at': now.toIso8601String(),
        };
        if (normalizedPin != null && normalizedPin.isNotEmpty) {
          final credential = _createPinCredential(normalizedPin);
          values.addAll(<String, Object?>{
            'pin_salt': credential.salt,
            'pin_hash': credential.hash,
            'pin_iterations': _pinIterations,
          });
        }
        final changed = await txn.update(
          'staff',
          values,
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
        if (changed != 1) throw StateError('Staff member not found.');
      }

      final saved = await _getStaffById(txn, id, _dateKey(now));
      if (saved == null) {
        throw StateError('The saved staff member could not be read.');
      }
      return saved;
    });
  }

  Future<bool> deleteStaff(int id) async {
    if (id <= 0) return false;
    final db = await database;
    return await db.delete('staff', where: 'id = ?', whereArgs: <Object?>[id]) >
        0;
  }

  /// Validates an active staff member and records today's check-in atomically.
  /// Inactive staff and staff assigned to inactive branches cannot check in.
  Future<StaffMember?> authenticateStaff(String email, String pin) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPin = pin.trim();
    if (!_isValidEmail(normalizedEmail) || !_isValidPin(normalizedPin)) {
      return null;
    }

    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
          SELECT s.*
          FROM staff s
          INNER JOIN branches b ON b.name = s.branch COLLATE NOCASE
          WHERE s.email = ? COLLATE NOCASE
            AND s.is_active = 1
            AND b.is_active = 1
          LIMIT 1
        ''',
        <Object?>[normalizedEmail],
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      final iterations = _asInt(row['pin_iterations']);
      final calculated = _derivePinHash(
        normalizedPin,
        row['pin_salt']!.toString(),
        iterations,
      );
      if (!_constantTimeEquals(calculated, row['pin_hash']!.toString())) {
        return null;
      }

      final id = _asInt(row['id']);
      final now = DateTime.now();
      final nowText = now.toIso8601String();
      final today = _dateKey(now);
      final attendance = await txn.query(
        'staff_attendance',
        columns: <String>['id'],
        where: 'staff_id = ? AND attendance_date = ?',
        whereArgs: <Object?>[id, today],
        limit: 1,
      );
      if (attendance.isEmpty) {
        await txn.insert('staff_attendance', <String, Object?>{
          'staff_id': id,
          'attendance_date': today,
          'first_login_at': nowText,
          'last_login_at': nowText,
          'login_count': 1,
        });
      } else {
        await txn.rawUpdate(
          '''
            UPDATE staff_attendance
            SET last_login_at = ?, login_count = login_count + 1
            WHERE id = ?
          ''',
          <Object?>[nowText, attendance.first['id']],
        );
      }
      await txn.update(
        'staff',
        <String, Object?>{'last_login_at': nowText, 'updated_at': nowText},
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return _getStaffById(txn, id, today);
    });
  }

  Future<StaffMember?> _getStaffById(
    DatabaseExecutor db,
    int id,
    String today,
  ) async {
    final rows = await db.rawQuery(
      '''
        SELECT s.*, COALESCE(a.login_count, 0) AS today_login_count
        FROM staff s
        LEFT JOIN staff_attendance a
          ON a.staff_id = s.id AND a.attendance_date = ?
        WHERE s.id = ?
        LIMIT 1
      ''',
      <Object?>[today, id],
    );
    return rows.isEmpty ? null : StaffMember.fromMap(rows.first);
  }

  Future<Supplier?> _getSupplier(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      'suppliers',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Supplier.fromMap(rows.first);
  }

  Future<PurchaseRecord?> _getPurchase(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      'purchases',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final lines = await _loadPurchaseLines(db, <int>[id]);
    return PurchaseRecord.fromMap(
      rows.first,
      lines: lines[id] ?? const <PurchaseLine>[],
    );
  }

  Future<Map<int, List<PurchaseLine>>> _loadPurchaseLines(
    DatabaseExecutor db,
    List<int> purchaseIds,
  ) async {
    if (purchaseIds.isEmpty) return <int, List<PurchaseLine>>{};
    final placeholders = List<String>.filled(purchaseIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM purchase_lines '
      'WHERE purchase_id IN ($placeholders) ORDER BY id ASC',
      purchaseIds,
    );
    final result = <int, List<PurchaseLine>>{};
    for (final row in rows) {
      final line = PurchaseLine.fromMap(row);
      final purchaseId = line.purchaseId;
      if (purchaseId != null) {
        result.putIfAbsent(purchaseId, () => <PurchaseLine>[]).add(line);
      }
    }
    return result;
  }

  Future<Map<int, List<InvoiceItem>>> _loadInvoiceItems(
    DatabaseExecutor db,
    List<int> invoiceIds,
  ) async {
    if (invoiceIds.isEmpty) return <int, List<InvoiceItem>>{};
    final placeholders = List<String>.filled(invoiceIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT * FROM invoice_items '
      'WHERE invoice_id IN ($placeholders) ORDER BY id ASC',
      invoiceIds,
    );
    final result = <int, List<InvoiceItem>>{};
    for (final row in rows) {
      final item = InvoiceItem.fromMap(row);
      result.putIfAbsent(item.invoiceId!, () => <InvoiceItem>[]).add(item);
    }
    return result;
  }

  Future<String> _nextInvoiceNumber(Transaction txn, DateTime now) async {
    final base = 'INV-${now.millisecondsSinceEpoch}';
    var candidate = base;
    var suffix = 1;
    while (true) {
      final rows = await txn.query(
        'invoices',
        columns: <String>['id'],
        where: 'invoice_number = ?',
        whereArgs: <Object?>[candidate],
        limit: 1,
      );
      if (rows.isEmpty) return candidate;
      candidate = '$base-${suffix++}';
    }
  }

  void _requireMedicineBranch(String medicineBranch, String? allowedBranch) {
    if (allowedBranch != null &&
        medicineBranch.trim().toLowerCase() !=
            allowedBranch.trim().toLowerCase()) {
      throw StateError(
        'Staff can only change medicines in their assigned branch.',
      );
    }
  }

  Medicine _normalizeAndValidateMedicine(Medicine medicine) {
    final normalized = medicine.copyWith(
      barcode: medicine.barcode.trim(),
      name: medicine.name.trim(),
      genericName: medicine.genericName.trim(),
      brandName: medicine.brandName.trim(),
      composition: medicine.composition.trim(),
      scheduleCategory: medicine.scheduleCategory.trim(),
      dosageForm: medicine.dosageForm.trim(),
      sku: medicine.sku.trim(),
      manufacturer: medicine.manufacturer.trim(),
      branch: medicine.branch.trim(),
    );
    if (normalized.name.isEmpty ||
        normalized.sku.isEmpty ||
        normalized.branch.isEmpty) {
      throw ArgumentError(
        'Medicine name, batch/code, and branch are required.',
      );
    }
    if (!medistockBranches.contains(normalized.branch)) {
      throw ArgumentError.value(
        normalized.branch,
        'branch',
        'Must be one of the four MediStock branches.',
      );
    }
    if (normalized.stock < 0 ||
        normalized.reorderThreshold < 0 ||
        normalized.costPaise < 0 ||
        normalized.pricePaise < 0) {
      throw ArgumentError(
        'Quantity, threshold, cost, and price cannot be negative.',
      );
    }
    return normalized;
  }

  Supplier _normalizeAndValidateSupplier(Supplier supplier) {
    final normalized = supplier.copyWith(
      name: supplier.name.trim(),
      phone: supplier.phone.trim(),
      email: supplier.email.trim().toLowerCase(),
      gstNumber: supplier.gstNumber.trim().toUpperCase(),
      address: supplier.address.trim(),
    );
    if (normalized.id != null && normalized.id! <= 0) {
      throw ArgumentError.value(normalized.id, 'id', 'Must be positive.');
    }
    if (normalized.name.isEmpty || normalized.name.length > 150) {
      throw ArgumentError.value(
        normalized.name,
        'name',
        'Supplier name is required and must be at most 150 characters.',
      );
    }
    if (normalized.email.isNotEmpty && !_isValidEmail(normalized.email)) {
      throw ArgumentError.value(
        normalized.email,
        'email',
        'Enter a valid email address.',
      );
    }
    return normalized;
  }

  PurchaseRecord _normalizeAndValidatePurchase(PurchaseRecord purchase) {
    final normalizedStatus = purchase.status.trim().toLowerCase();
    final normalizedLines = purchase.lines
        .map((line) {
          final normalizedState = line.matchState.trim().isEmpty
              ? 'unmatched'
              : line.matchState.trim().toLowerCase();
          final normalized = line.copyWith(
            productName: line.productName.trim(),
            batchNumber: line.batchNumber.trim(),
            matchState: normalizedState,
          );
          if (normalized.productName.isEmpty) {
            throw ArgumentError('Every purchase line needs a product name.');
          }
          if (normalized.medicineId != null && normalized.medicineId! <= 0) {
            throw ArgumentError.value(
              normalized.medicineId,
              'medicineId',
              'Must refer to a saved medicine.',
            );
          }
          if (normalized.billedQuantity < 0 ||
              normalized.freeQuantity < 0 ||
              normalized.mrpPaise < 0 ||
              normalized.purchaseRatePaise < 0) {
            throw ArgumentError(
              'Purchase quantities and prices cannot be negative.',
            );
          }
          _validatePercentage(normalized.gstPercent, 'gstPercent');
          if (!normalized.matchScore.isFinite ||
              normalized.matchScore < 0 ||
              normalized.matchScore > 1) {
            throw ArgumentError.value(
              normalized.matchScore,
              'matchScore',
              'Must be between 0 and 1.',
            );
          }
          return normalized;
        })
        .toList(growable: false);
    final normalized = purchase.copyWith(
      supplierName: purchase.supplierName.trim(),
      invoiceNumber: purchase.invoiceNumber.trim(),
      branch: _normalizeBranch(purchase.branch),
      status: normalizedStatus,
      lines: List<PurchaseLine>.unmodifiable(normalizedLines),
    );
    if (normalized.id != null && normalized.id! <= 0) {
      throw ArgumentError.value(normalized.id, 'id', 'Must be positive.');
    }
    if (normalized.supplierId <= 0) {
      throw ArgumentError.value(
        normalized.supplierId,
        'supplierId',
        'Must refer to a saved supplier.',
      );
    }
    if (normalized.invoiceNumber.isEmpty) {
      throw ArgumentError('Supplier invoice number is required.');
    }
    if (normalizedStatus != 'draft' && normalizedStatus != 'completed') {
      throw ArgumentError.value(
        normalized.status,
        'status',
        'Use draft or completed.',
      );
    }
    return normalized;
  }

  StaffMember _normalizeAndValidateStaff(StaffMember staff) {
    final normalized = staff.copyWith(
      name: staff.name.trim(),
      email: staff.email.trim().toLowerCase(),
      role: staff.role.trim(),
      branch: _normalizeBranch(staff.branch),
      shift: staff.shift.trim().toUpperCase(),
    );
    if (normalized.id != null && normalized.id! <= 0) {
      throw ArgumentError.value(normalized.id, 'id', 'Must be positive.');
    }
    if (normalized.name.length < 2 || normalized.name.length > 100) {
      throw ArgumentError.value(
        normalized.name,
        'name',
        'Must contain between 2 and 100 characters.',
      );
    }
    if (!_isValidEmail(normalized.email)) {
      throw ArgumentError.value(
        normalized.email,
        'email',
        'Enter a valid email address.',
      );
    }
    if (normalized.role.length < 2 || normalized.role.length > 60) {
      throw ArgumentError.value(
        normalized.role,
        'role',
        'Must contain between 2 and 60 characters.',
      );
    }
    if (!staffShifts.contains(normalized.shift)) {
      throw ArgumentError.value(
        normalized.shift,
        'shift',
        'Must be A, B, or C.',
      );
    }
    return normalized;
  }

  String _normalizeBranch(String value) {
    final candidate = value.trim();
    for (final branch in medistockBranches) {
      if (branch.toLowerCase() == candidate.toLowerCase()) return branch;
    }
    throw ArgumentError.value(
      value,
      'branch',
      'Must be one of the four MediStock branches.',
    );
  }

  void _validatePin(String value) {
    if (!_isValidPin(value)) {
      throw ArgumentError('PIN must contain 4 to 8 digits.');
    }
  }

  bool _isValidPin(String value) => RegExp(r'^\d{4,8}$').hasMatch(value);

  bool _isValidEmail(String value) {
    return value.length <= 254 &&
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  ({String salt, String hash}) _createPinCredential(String pin) {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = base64Encode(saltBytes);
    return (salt: salt, hash: _derivePinHash(pin, salt, _pinIterations));
  }

  String _derivePinHash(String pin, String salt, int iterations) {
    if (iterations <= 0) throw StateError('Invalid PIN digest configuration.');
    final passwordBytes = utf8.encode(pin);
    final saltBytes = base64Decode(salt);
    final block = Uint8List(saltBytes.length + 4)
      ..setRange(0, saltBytes.length, saltBytes)
      ..setRange(saltBytes.length, saltBytes.length + 4, const <int>[
        0,
        0,
        0,
        1,
      ]);
    final hmac = Hmac(sha256, passwordBytes);
    var previous = hmac.convert(block).bytes;
    final derived = Uint8List.fromList(previous);
    for (var round = 1; round < iterations; round++) {
      previous = hmac.convert(previous).bytes;
      for (var index = 0; index < derived.length; index++) {
        derived[index] ^= previous[index];
      }
    }
    return base64Encode(derived);
  }

  bool _constantTimeEquals(String first, String second) {
    final firstUnits = first.codeUnits;
    final secondUnits = second.codeUnits;
    var difference = firstUnits.length ^ secondUnits.length;
    final length = max(firstUnits.length, secondUnits.length);
    for (var index = 0; index < length; index++) {
      final firstUnit = index < firstUnits.length ? firstUnits[index] : 0;
      final secondUnit = index < secondUnits.length ? secondUnits[index] : 0;
      difference |= firstUnit ^ secondUnit;
    }
    return difference == 0;
  }

  String _dateKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String? _dateOnly(DateTime? value) => value == null ? null : _dateKey(value);

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  double _fuzzyScore(String normalizedQuery, String candidate) {
    final normalizedCandidate = _normalizeSearchText(candidate);
    if (normalizedCandidate.isEmpty) return 0;
    if (normalizedQuery == normalizedCandidate) return 1;

    var score = 0.0;
    if (normalizedCandidate.contains(normalizedQuery) ||
        normalizedQuery.contains(normalizedCandidate)) {
      final ratio =
          min(normalizedQuery.length, normalizedCandidate.length) /
          max(normalizedQuery.length, normalizedCandidate.length);
      score = max(score, 0.82 + (0.12 * ratio));
    }

    final queryTokens = normalizedQuery.split(' ').toSet();
    final candidateTokens = normalizedCandidate.split(' ').toSet();
    final intersection = queryTokens.intersection(candidateTokens).length;
    final union = queryTokens.union(candidateTokens).length;
    if (union > 0) score = max(score, 0.9 * intersection / union);

    var tokenSimilarity = 0.0;
    for (final queryToken in queryTokens) {
      var best = 0.0;
      for (final candidateToken in candidateTokens) {
        best = max(best, _editSimilarity(queryToken, candidateToken));
      }
      tokenSimilarity += best;
    }
    if (queryTokens.isNotEmpty) {
      score = max(score, 0.9 * tokenSimilarity / queryTokens.length);
    }
    score = max(
      score,
      0.85 * _editSimilarity(normalizedQuery, normalizedCandidate),
    );
    return score.clamp(0, 1).toDouble();
  }

  double _editSimilarity(String first, String second) {
    if (first == second) return 1;
    if (first.isEmpty || second.isEmpty) return 0;
    var previous = List<int>.generate(second.length + 1, (index) => index);
    for (var firstIndex = 1; firstIndex <= first.length; firstIndex++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = firstIndex;
      for (var secondIndex = 1; secondIndex <= second.length; secondIndex++) {
        final substitution =
            previous[secondIndex - 1] +
            (first.codeUnitAt(firstIndex - 1) ==
                    second.codeUnitAt(secondIndex - 1)
                ? 0
                : 1);
        current[secondIndex] = min(
          min(current[secondIndex - 1] + 1, previous[secondIndex] + 1),
          substitution,
        );
      }
      previous = current;
    }
    final longest = max(first.length, second.length);
    return 1 - (previous.last / longest);
  }

  Map<String, Object?> _medicineValues(Medicine medicine) {
    return medicine.toMap()
      ..['barcode_digits'] = _barcodeDigits(medicine.barcode);
  }

  void _validatePercentage(double value, String name, {double? maximum}) {
    if (!value.isFinite || value < 0 || (maximum != null && value > maximum)) {
      final range = maximum == null
          ? 'zero or greater'
          : 'between 0 and $maximum';
      throw ArgumentError.value(value, name, 'Must be $range.');
    }
  }

  String _barcodeDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
