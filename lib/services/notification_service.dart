import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../models/lectura.dart' show numeroDiaSemana;

/// Hora del día (hora local) en la que se dispara el recordatorio semanal.
/// No hay un campo para que el usuario elija la hora, así que se usa una
/// fija y razonable para revisar lecturas.
const int _horaRecordatorio = 9;
const int _minutoRecordatorio = 0;

/// Próxima fecha (a partir de [desde]) que caiga en el día de la semana
/// [diaSemana] (1=lunes ... 7=domingo), a la hora del recordatorio. Si hoy
/// mismo es ese día pero la hora del recordatorio ya pasó, salta a la
/// semana siguiente para no programar una notificación en el pasado.
DateTime _proximaFechaParaDia(DateTime desde, int diaSemana) {
  var fecha = DateTime(desde.year, desde.month, desde.day, _horaRecordatorio, _minutoRecordatorio);
  var diferencia = (diaSemana - fecha.weekday) % 7;
  if (diferencia < 0) diferencia += 7;
  fecha = fecha.add(Duration(days: diferencia));
  if (!fecha.isAfter(desde)) fecha = fecha.add(const Duration(days: 7));
  return fecha;
}

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

  /// Programa el recordatorio semanal de esta lectura para el próximo
  /// [diaActualizacion] (clave de [diasSemana], ej. 'lunes'). Al pasar
  /// `matchDateTimeComponents: dayOfWeekAndTime` queda repitiéndose solo
  /// cada semana ese mismo día y hora, sin tener que reprogramarlo a mano.
  Future<void> programarRecordatorio({
    required String lecturaId,
    required String titulo,
    required DateTime fechaBase,
    required String diaActualizacion,
  }) async {
    final id = lecturaId.hashCode;
    final fechaNotif = _proximaFechaParaDia(fechaBase, numeroDiaSemana(diaActualizacion));

    await _plugin.zonedSchedule(
      id,
      'Hilectio',
      'Puede que ya haya salido capítulo nuevo de "$titulo". Dale un vistazo.',
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
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> cancelar(String lecturaId) async {
    await _plugin.cancel(lecturaId.hashCode);
  }
}