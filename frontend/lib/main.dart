import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'platform/database_platform.dart' as database_platform;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  database_platform.configureDatabasePlatform();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MediStockBootstrap());
}
