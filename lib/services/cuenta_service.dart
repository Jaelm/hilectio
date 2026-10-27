import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Borra la cuenta del usuario actual: su documento y subcolecciones en
/// `usuarios/{uid}`, la reserva de su apodo, los resúmenes que escribió y
/// sus entradas de "estoy leyendo esto" (`lectores/{uid}`) en cualquier
/// obra, y finalmente la cuenta de Firebase Auth.
///
/// No se tocan los votos que este usuario dio en resúmenes de otros (son
/// solo un +1 a favor de otra persona, no quedan datos suyos) ni los
/// reportes que hizo (mismo caso). Firebase requiere que la sesión sea
/// "reciente" para borrar la cuenta, así que la pantalla debe reautenticar
/// con la contraseña justo antes de llamar a [eliminarCuenta].
class CuentaService {
  Future<void> eliminarCuenta() async {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;
    final db = FirebaseFirestore.instance;

    // 1. Libera la reserva de apodo (si tiene uno).
    final apodos = await db.collection('apodos').where('uid', isEqualTo: uid).get();
    for (final doc in apodos.docs) {
      await doc.reference.delete();
    }

    // 2. Borra sus entradas de "estoy leyendo esto" en cualquier obra (el id
    // del documento siempre es el uid, así que se filtra por eso).
    final lectores = await db.collectionGroup('lectores').get();
    for (final doc in lectores.docs) {
      if (doc.id == uid) await doc.reference.delete();
    }

    // 3. Borra los resúmenes que escribió (quedarían huérfanos sin autor).
    final resumenes = await db
        .collectionGroup('resumenes')
        .where('uid', isEqualTo: uid)
        .get();
    for (final doc in resumenes.docs) {
      await doc.reference.delete();
    }

    // 4. Borra el documento de usuario y sus subcolecciones conocidas.
    final usuarioRef = db.collection('usuarios').doc(uid);
    for (final sub in ['lecturas', 'misPropuestas', 'bloqueados']) {
      final docs = await usuarioRef.collection(sub).get();
      for (final doc in docs.docs) {
        await doc.reference.delete();
      }
    }
    await usuarioRef.delete();

    // 5. Por último, la cuenta de autenticación.
    await user.delete();
  }
}