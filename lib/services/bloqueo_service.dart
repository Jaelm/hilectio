import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Bloqueo entre usuarios: es direccional (si A bloquea a B, A deja de ver
/// los resúmenes de B y B deja de poder ver el perfil de A; no hace falta
/// que B también bloquee a A). Se guarda como un documento por bloqueado en
/// `usuarios/{uid}/bloqueados/{bloqueadoUid}`, igual de simple que el
/// patrón de "me gusta"/votos que ya usa el resto de la app.
class BloqueoService {
  String get _miUid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _miBloqueo(String otroUid) =>
      FirebaseFirestore.instance.collection('usuarios').doc(_miUid).collection('bloqueados').doc(otroUid);

  Future<void> bloquear(String otroUid) async {
    await _miBloqueo(otroUid).set({'bloqueadoEn': FieldValue.serverTimestamp()});
  }

  Future<void> desbloquear(String otroUid) async {
    await _miBloqueo(otroUid).delete();
  }

  /// Si YO tengo bloqueado a [otroUid] (para el botón "Bloquear"/"Desbloquear").
  Stream<bool> yoLoBloqueeStream(String otroUid) {
    return _miBloqueo(otroUid).snapshots().map((s) => s.exists);
  }

  /// Si [otroUid] ME tiene bloqueado a mí (para ocultarle mi perfil). Solo
  /// lee UN documento puntual (no lista la colección de nadie), que es lo
  /// único que permiten las reglas de Firestore para no exponer a quién
  /// bloqueó cada quien.
  Future<bool> meBloqueo(String otroUid) async {
    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(otroUid)
        .collection('bloqueados')
        .doc(_miUid)
        .get();
    return snap.exists;
  }

  /// Todos los uid que yo tengo bloqueados (para filtrar resúmenes/listas).
  Future<Set<String>> misBloqueados() async {
    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(_miUid)
        .collection('bloqueados')
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }
}