import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tzdata.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> programarRecordatorio({
    required String lecturaId,
    required String titulo,
    required DateTime fechaBase,
    required int frecuenciaDias,
  }) async {
    final id = lecturaId.hashCode;
    final fechaNotif = fechaBase.add(Duration(days: frecuenciaDias));

    await _plugin.zonedSchedule(
      id,
      'Hilectio',
      '¿Ya salió capítulo nuevo de "$titulo"? Toca para revisar.',
      tz.TZDateTime.from(fechaNotif, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'actualizaciones_lectura',
          'Actualizaciones de lectura',
          channelDescription: 'Avisa cuando toca revisar una lectura',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancelar(String lecturaId) async {
    await _plugin.cancel(lecturaId.hashCode);
  }
}