import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'logros_service.dart';

class TokensService {
  static const List<int> recompensasRacha = [1, 3, 5, 7, 9, 11, 15];
  static const int costoSalvarRacha = 40;

  DocumentReference<Map<String, dynamic>> get _userDoc => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(FirebaseAuth.instance.currentUser!.uid);

  DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Suma tokens al saldo de cualquier usuario (no necesariamente el actual).
  /// Se usa, por ejemplo, cuando el admin aprueba una propuesta de datos de obra.
  Future<void> otorgarTokensAUsuario({required String uid, required int cantidad}) async {
    if (cantidad <= 0) return;
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
      'tokens': FieldValue.increment(cantidad),
    }, SetOptions(merge: true));
    await LogrosService().registrarGananciaTokens(uid);
  }

  /// Resta tokens del saldo de cualquier usuario (ej. penalización por un
  /// resumen que viola las reglas). Nunca deja el saldo en negativo.
  Future<void> quitarTokensAUsuario({required String uid, required int cantidad}) async {
    if (cantidad <= 0) return;
    final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final actuales = (snap.data()?['tokens'] as num?)?.toInt() ?? 0;
      final nuevos = actuales - cantidad;
      tx.set(ref, {'tokens': nuevos < 0 ? 0 : nuevos}, SetOptions(merge: true));
    });
  }

  /// Lee el estado actual sin modificar nada. Úsalo antes de guardar una lectura
  /// para saber si hay que preguntarle al usuario si quiere salvar la racha.
  Future<Map<String, dynamic>> verificarRacha() async {
    final snap = await _userDoc.get();
    final data = snap.data() ?? {};
    final int tokensActuales = data['tokens'] ?? 0;
    final int rachaActual = data['rachaActual'] ?? 0;
    final Timestamp? ultimaTs = data['rachaUltimaFecha'];
    final DateTime hoy = _soloFecha(DateTime.now());

    if (ultimaTs == null) {
      return {'estado': 'primeraVez'};
    }

    final ultima = _soloFecha(ultimaTs.toDate());
    final diferenciaDias = hoy.difference(ultima).inDays;

    if (diferenciaDias == 0) {
      return {'estado': 'alDia', 'racha': rachaActual, 'tokens': tokensActuales};
    }
    if (diferenciaDias == 1) {
      return {'estado': 'continuable', 'racha': rachaActual, 'tokens': tokensActuales};
    }
    return {
      'estado': 'rota',
      'racha': rachaActual,
      'tokens': tokensActuales,
      'puedeSalvar': tokensActuales >= costoSalvarRacha,
    };
  }

  /// Llamar después de guardar una lectura. [salvarRacha] solo importa si el
  /// estado era "rota" y el usuario eligió pagar para salvarla.
  Future<Map<String, dynamic>> confirmarActividad({bool salvarRacha = false}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final resultado = await FirebaseFirestore.instance.runTransaction<Map<String, dynamic>>((tx) async {
      final snap = await tx.get(_userDoc);
      final data = snap.data() ?? {};
      final int tokensActuales = data['tokens'] ?? 0;
      final int rachaActual = data['rachaActual'] ?? 0;
      // A diferencia de `rachaActual` (que se reinicia a 1 cada 7 días porque
      // ahí es donde se repite la tabla de recompensas), `rachaDiasTotal`
      // cuenta los días consecutivos reales sin tope, para los logros de
      // "30 días" y "365 días".
      final int rachaDiasTotal = data['rachaDiasTotal'] ?? 0;
      final Timestamp? ultimaTs = data['rachaUltimaFecha'];
      final DateTime hoy = _soloFecha(DateTime.now());

      if (ultimaTs == null) {
        const recompensa = 1;
        tx.set(_userDoc, {
          'tokens': tokensActuales + recompensa,
          'rachaActual': 1,
          'rachaDiasTotal': 1,
          'rachaUltimaFecha': Timestamp.fromDate(hoy),
        }, SetOptions(merge: true));
        return {
          'cambio': true,
          'tokens': tokensActuales + recompensa,
          'racha': 1,
          'recompensa': recompensa,
          'rachaRota': false,
        };
      }

      final ultima = _soloFecha(ultimaTs.toDate());
      final diferenciaDias = hoy.difference(ultima).inDays;

      if (diferenciaDias == 0) {
        return {'cambio': false, 'tokens': tokensActuales, 'racha': rachaActual};
      }

      if (diferenciaDias == 1) {
        final nuevaRacha = rachaActual >= 7 ? 1 : rachaActual + 1;
        final recompensa = recompensasRacha[nuevaRacha - 1];
        final nuevosTokens = tokensActuales + recompensa;
        tx.set(_userDoc, {
          'tokens': nuevosTokens,
          'rachaActual': nuevaRacha,
          'rachaDiasTotal': rachaDiasTotal + 1,
          'rachaUltimaFecha': Timestamp.fromDate(hoy),
        }, SetOptions(merge: true));
        return {
          'cambio': true,
          'tokens': nuevosTokens,
          'racha': nuevaRacha,
          'recompensa': recompensa,
          'rachaRota': false,
        };
      }

      // Pasó más de un día: la racha se rompió.
      if (salvarRacha && tokensActuales >= costoSalvarRacha) {
        final nuevaRacha = rachaActual >= 7 ? 1 : rachaActual + 1;
        final recompensa = recompensasRacha[nuevaRacha - 1];
        final nuevosTokens = tokensActuales - costoSalvarRacha + recompensa;
        tx.set(_userDoc, {
          'tokens': nuevosTokens,
          'rachaActual': nuevaRacha,
          'rachaDiasTotal': rachaDiasTotal + 1,
          'rachaUltimaFecha': Timestamp.fromDate(hoy),
        }, SetOptions(merge: true));
        return {
          'cambio': true,
          'tokens': nuevosTokens,
          'racha': nuevaRacha,
          'recompensa': recompensa,
          'rachaRota': false,
          'rachaSalvada': true,
        };
      }

      const recompensa = 1;
      final nuevosTokens = tokensActuales + recompensa;
      tx.set(_userDoc, {
        'tokens': nuevosTokens,
        'rachaActual': 1,
        'rachaDiasTotal': 1,
        'rachaUltimaFecha': Timestamp.fromDate(hoy),
      }, SetOptions(merge: true));
      return {
        'cambio': true,
        'tokens': nuevosTokens,
        'racha': 1,
        'recompensa': recompensa,
        'rachaRota': true,
      };
    });

    if (resultado['cambio'] == true) {
      await LogrosService().registrarGananciaTokens(uid);
    }
    return resultado;
  }
}