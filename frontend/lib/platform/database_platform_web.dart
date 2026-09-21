import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Keep browser preview data local to this browser and localhost port.
void configureDatabasePlatform() {
  databaseFactory = databaseFactoryFfiWeb;
}
