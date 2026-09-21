import 'dart:io';

import 'package:medistock_backend/medistock_backend.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.close();
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'medistock_backend_test_',
    );
    await databaseFactory.setDatabasesPath(temporaryDirectory.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'seeds branches and records staff attendance without storing raw PIN',
    () async {
      final database = AppDatabase.instance;
      final initialBranches = await database.listBranchSummaries();

      expect(initialBranches.map((branch) => branch.name), medistockBranches);
      expect(initialBranches.every((branch) => branch.isActive), isTrue);

      final saved = await database.saveStaff(
        const StaffMember(
          name: 'Asha Rao',
          email: 'ASHA@example.com',
          role: 'Pharmacist',
          branch: 'Main Branch',
        ),
        pin: '4826',
      );
      expect(saved.email, 'asha@example.com');
      expect(saved.shift, 'A');
      expect(saved.checkedInToday, isFalse);

      final rawRows = await (await database.database).query('staff');
      expect(rawRows.single['pin_hash'], isNot('4826'));
      expect(rawRows.single['pin_salt'], isNotEmpty);
      expect(rawRows.single.values, isNot(contains('4826')));

      expect(await database.authenticateStaff(saved.email, '0000'), isNull);
      final firstLogin = await database.authenticateStaff(saved.email, '4826');
      final secondLogin = await database.authenticateStaff(saved.email, '4826');
      expect(firstLogin?.todayLoginCount, 1);
      expect(secondLogin?.todayLoginCount, 2);
      expect(secondLogin?.lastLoginAt, isNotNull);

      final mainBranch = (await database.listBranchSummaries()).first;
      expect(mainBranch.activeStaffCount, 1);
      expect(mainBranch.todayCheckIns, 2);

      await database.setBranchActive('main branch', false);
      expect(await database.authenticateStaff(saved.email, '4826'), isNull);
    },
  );

  test('saves and updates assigned staff shifts', () async {
    final database = AppDatabase.instance;
    final saved = await database.saveStaff(
      const StaffMember(
        name: 'Meera Shah',
        email: 'meera@example.com',
        role: 'Pharmacist',
        branch: 'Main Branch',
        shift: 'C',
      ),
      pin: '4826',
    );

    expect(saved.shift, 'C');
    expect((await database.listStaff()).single.shift, 'C');
    expect(staffShiftHours[saved.shift], '5:00 PM - 9:00 PM');

    final updated = await database.saveStaff(saved.copyWith(shift: 'B'));
    expect(updated.shift, 'B');
    expect((await database.getStaffById(saved.id!))?.shift, 'B');
    expect(staffShiftHours[updated.shift], '1:00 PM - 5:00 PM');

    await expectLater(
      database.saveStaff(updated.copyWith(shift: 'night')),
      throwsArgumentError,
    );
  });

  test(
    'clearAllData removes staff data and reactivates every branch',
    () async {
      final database = AppDatabase.instance;
      final member = await database.saveStaff(
        const StaffMember(
          name: 'Ravi Kumar',
          email: 'ravi@example.com',
          role: 'Cashier',
          branch: 'City Branch',
        ),
        pin: '1234',
      );
      await database.authenticateStaff(member.email, '1234');
      await database.setBranchActive('South Branch', false);

      await database.clearAllData();

      expect(await database.listStaff(), isEmpty);
      final attendance = await (await database.database).query(
        'staff_attendance',
      );
      expect(attendance, isEmpty);
      expect(
        (await database.listBranchSummaries()).every(
          (branch) => branch.isActive,
        ),
        isTrue,
      );
    },
  );

  test('upgrades a version 1 database without losing inventory', () async {
    final legacy = await databaseFactory.openDatabase(
      path.join(temporaryDirectory.path, 'medistock.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE medicines (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              branch TEXT NOT NULL,
              stock INTEGER NOT NULL,
              threshold_qty INTEGER NOT NULL,
              cost_paise INTEGER NOT NULL
            )
          ''');
          await database.insert('medicines', <String, Object?>{
            'branch': 'Main Branch',
            'stock': 12,
            'threshold_qty': 5,
            'cost_paise': 250,
          });
        },
      ),
    );
    await legacy.close();

    final summaries = await AppDatabase.instance.listBranchSummaries();
    expect(summaries, hasLength(4));
    expect(summaries.first.medicineCount, 1);
    expect(summaries.first.totalUnits, 12);
    expect(summaries.first.stockValuePaise, 3000);

    final database = await AppDatabase.instance.database;
    expect(await database.getVersion(), 5);
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']);
    expect(
      tableNames,
      containsAll(<String>[
        'branches',
        'staff',
        'staff_attendance',
        'branch_orders',
      ]),
    );
  });

  test('upgrades version 3 staff with a default morning shift', () async {
    final legacy = await databaseFactory.openDatabase(
      path.join(temporaryDirectory.path, 'medistock.db'),
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE staff (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL
            )
          ''');
          await database.insert('staff', <String, Object?>{
            'id': 1,
            'name': 'Existing employee',
          });
        },
      ),
    );
    await legacy.close();

    final upgraded = await AppDatabase.instance.database;
    expect(await upgraded.getVersion(), 5);
    final rows = await upgraded.query('staff');
    expect(rows.single['shift'], 'A');
  });
}
