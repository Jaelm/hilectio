import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CuestionarioService {
  static const int recompensa = 20;
  static const int minAciertos = 2; // de 3 preguntas

  DocumentReference<Map<String, dynamic>> get _userDoc => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(FirebaseAuth.instance.currentUser!.uid);

  Future<bool> puedeHacerCuestionario() async {
    final snap = await _userDoc.get();
    final Timestamp? ultima = snap.data()?['cuestionarioUltimaFecha'];
    if (ultima == null) return true;
    final dias = DateTime.now().difference(ultima.toDate()).inDays;
    return dias >= 7;
  }

  Future<int> reclamarRecompensa(bool aprobo) async {
    if (!aprobo) {
      await _userDoc.set({
        'cuestionarioUltimaFecha': Timestamp.now(),
      }, SetOptions(merge: true));
      return 0;
    }
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_userDoc);
      final tokensActuales = snap.data()?['tokens'] ?? 0;
      final nuevosTokens = tokensActuales + recompensa;
      tx.set(_userDoc, {
        'tokens': nuevosTokens,
        'cuestionarioUltimaFecha': Timestamp.now(),
      }, SetOptions(merge: true));
      return recompensa;
    });
  }
}