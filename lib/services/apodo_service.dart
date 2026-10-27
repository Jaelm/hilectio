import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Normaliza el apodo para usarlo como clave de unicidad (minúsculas, sin
/// espacios de más). Esta clave es el ID del documento en la colección
/// 'apodos', que funciona como "reserva" para que dos usuarios no puedan
/// tener el mismo apodo (incluyendo variaciones de mayúsculas/minúsculas).
String normalizarApodo(String apodo) => apodo.trim().toLowerCase();

/// Costo en tokens de cambiar el apodo (la primera vez que se elige, justo
/// después de registrarse, siempre es gratis).
const int costoCambioApodo = 30;

class ApodoService {
  CollectionReference<Map<String, dynamic>> get _apodos =>
      FirebaseFirestore.instance.collection('apodos');

  /// Reserva [apodo] para el usuario actual y lo guarda en su documento de
  /// usuario. Si el usuario ya tenía un apodo anterior, libera esa reserva
  /// vieja en la misma transacción. Lanza una [Exception] (con mensaje listo
  /// para mostrar) si el apodo no es válido o ya está en uso por otra cuenta.
  Future<void> elegirApodo(String apodo) async {
    final texto = apodo.trim();
    if (texto.length < 3 || texto.length > 20) {
      throw Exception('El apodo debe tener entre 3 y 20 caracteres.');
    }
    if (!RegExp(r'^[a-zA-Z0-9áéíóúÁÉÍÓÚñÑ_]+$').hasMatch(texto)) {
      throw Exception('El apodo solo puede tener letras, números y guión bajo (sin espacios).');
    }

    final user = FirebaseAuth.instance.currentUser!;
    final clave = normalizarApodo(texto);
    final usuarioRef = FirebaseFirestore.instance.collection('usuarios').doc(user.uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final claveRef = _apodos.doc(clave);
      final claveSnap = await tx.get(claveRef);
      if (claveSnap.exists && claveSnap.data()?['uid'] != user.uid) {
        throw Exception('Ese apodo ya está en uso. Prueba con otro.');
      }

      final usuarioSnap = await tx.get(usuarioRef);
      final apodoAnterior = usuarioSnap.data()?['apodoClave'] as String?;
      final tokensActuales = (usuarioSnap.data()?['tokens'] as num?)?.toInt() ?? 0;

      final esPrimerApodo = apodoAnterior == null;
      // Un cambio "de verdad" (no la primera vez, y realmente a un apodo
      // distinto del que ya tenía) es lo único que cobra tokens.
      final esCambioQueCobra = !esPrimerApodo && apodoAnterior != clave;

      if (esCambioQueCobra && tokensActuales < costoCambioApodo) {
        throw Exception(
          'Necesitas $costoCambioApodo tokens para cambiar de apodo (tienes $tokensActuales).',
        );
      }

      if (apodoAnterior != null && apodoAnterior != clave) {
        tx.delete(_apodos.doc(apodoAnterior));
      }

      tx.set(claveRef, {'uid': user.uid});

      final datosUsuario = <String, dynamic>{
        'apodo': texto,
        'apodoClave': clave,
      };
      // Regalo de bienvenida: solo la primera vez que alguien elige su
      // apodo (justo después de registrarse) y solo si todavía no tiene
      // tokens asignados, para no volver a dárselo si solo está cambiando
      // de apodo más adelante.
      if (esPrimerApodo && usuarioSnap.data()?['tokens'] == null) {
        datosUsuario['tokens'] = 100;
      } else if (esCambioQueCobra) {
        datosUsuario['tokens'] = tokensActuales - costoCambioApodo;
      }
      tx.set(usuarioRef, datosUsuario, SetOptions(merge: true));
    });
  }
}