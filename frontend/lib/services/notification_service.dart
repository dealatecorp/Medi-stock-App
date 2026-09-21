import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:medistock_backend/medistock_backend.dart';

typedef NotificationTapCallback = void Function(String? payload);

/// Manages local, on-device MediStock alerts.
class NotificationService {
  NotificationService._();

  static const String _lowStockChannelId = 'medistock_low_stock';
  static const String _lowStockChannelName = 'Low-stock alerts';
  static const String _lowStockChannelDescription =
      'Alerts when medicine quantity reaches its reorder threshold.';

  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool _permissionGranted = true;

  /// Initializes platform notification support and requests permission.
  ///
  /// Call once during app startup. [onNotificationTap] receives the medicine
  /// payload when the user opens a low-stock alert.
  static Future<bool> initialize({
    NotificationTapCallback? onNotificationTap,
  }) async {
    if (_initialized) return _permissionGranted;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    final initialized = await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call(response.payload);
      },
    );

    if (initialized != true) {
      _permissionGranted = false;
      return false;
    }

    final androidPermission = await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    final iosPermission = await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _permissionGranted = androidPermission != false && iosPermission != false;
    _initialized = true;
    return _permissionGranted;
  }

  /// Shows an immediate low-stock alert for [medicine].
  ///
  /// Medicines above their reorder threshold are ignored defensively.
  static Future<void> showLowStock(Medicine medicine) async {
    if (!medicine.isLowStock) return;
    if (!_initialized) await initialize();
    if (!_permissionGranted) return;

    final unitLabel = medicine.stock == 1 ? 'unit' : 'units';
    final body =
        '${medicine.name} has ${medicine.stock} $unitLabel left at '
        '${medicine.branch}. Reorder level: ${medicine.reorderThreshold}.';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _lowStockChannelId,
        _lowStockChannelName,
        channelDescription: _lowStockChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
        ticker: 'MediStock low-stock alert',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
      ),
    );

    await _notifications.show(
      id: _notificationId(medicine),
      title: 'Low stock: ${medicine.name}',
      body: body,
      notificationDetails: details,
      payload: 'medicine:${medicine.id ?? medicine.sku}',
    );
  }

  static int _notificationId(Medicine medicine) {
    final id = medicine.id;
    if (id != null) return id & 0x7fffffff;
    return Object.hash(medicine.sku, medicine.branch) & 0x7fffffff;
  }
}
