import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TokensService {
  static const List<int> recompensasRacha = [1, 3, 5, 7, 9, 11, 15];

  DocumentReference<Map<String, dynamic>> get _userDoc => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(FirebaseAuth.instance.currentUser!.uid);

  DateTime _soloFecha(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Llamar cada vez que el usuario actualiza una lectura (crear o editar).
  /// Devuelve info de lo que pasó para poder avisarle al usuario.
  Future<Map<String, dynamic>> registrarActividadDiaria() async {
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_userDoc);
      final data = snap.data() ?? {};

      final int tokensActuales = data['tokens'] ?? 0;
      final int rachaActual = data['rachaActual'] ?? 0;
      final Timestamp? ultimaTs = data['rachaUltimaFecha'];
      final DateTime hoy = _soloFecha(DateTime.now());

      if (ultimaTs == null) {
        const recompensa = 1;
        tx.set(_userDoc, {
          'tokens': tokensActuales + recompensa,
          'rachaActual': 1,
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

      // Se rompió la racha (pasó más de un día sin actualizar).
      const recompensa = 1;
      final nuevosTokens = tokensActuales + recompensa;
      tx.set(_userDoc, {
        'tokens': nuevosTokens,
        'rachaActual': 1,
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
  }
}