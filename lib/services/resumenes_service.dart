import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tokens_service.dart';
import 'logros_service.dart';
import 'obra_service.dart' show normalizarTitulo;

const int tokensPorVoto = 1;
const int penalizacionViolacion = 10;

/// Lista básica de palabras que disparan revisión automática (amenazas y
/// groserías comunes). No es un filtro perfecto ni pretende serlo: solo hace
/// una primera pasada y oculta el resumen hasta que el admin lo revise a
/// mano. Se puede ampliar según haga falta.
const List<String> _palabrasProhibidas = [
  'idiota',
  'estupido',
  'estúpido',
  'imbecil',
  'imbécil',
  'maldito',
  'puta',
  'puto',
  'mierda',
  'pendejo',
  'cabron',
  'cabrón',
  'te voy a matar',
  'te mato',
  'muerete',
  'muérete',
];

bool contienePalabraProhibida(String texto) {
  final t = texto.toLowerCase();
  return _palabrasProhibidas.any((p) => t.contains(p));
}

/// Normaliza el número/nombre de capítulo para usarlo como parte del ID del
/// documento (evita que "5", " 5 " y "5 " cuenten como capítulos distintos).
String _normalizarCapitulo(String capitulo) {
  final normalizado = capitulo
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áéíóúñ]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return normalizado.replaceAll(RegExp(r'^_|_$'), '');
}

class ResumenesService {
  CollectionReference<Map<String, dynamic>> _resumenes(String obraId) => FirebaseFirestore
      .instance
      .collection('obras')
      .doc(obraId)
      .collection('resumenes');

  /// Crea un resumen. Si el filtro automático detecta lenguaje prohibido,
  /// queda oculto ('pendiente_revision') hasta que el admin lo revise;
  /// si no, se publica directo.
  ///
  /// Solo se permite UN resumen por usuario por capítulo: el ID del
  /// documento se arma como "{uid}_{capítulo normalizado}", así que un
  /// segundo intento para el mismo capítulo lanza una excepción en vez de
  /// crear un duplicado.
  ///
  /// Devuelve un mapa con `sospechoso` (si quedó en revisión) y
  /// `logrosDesbloqueados` (títulos secretos recién ganados, si aplica).
  Future<Map<String, dynamic>> crearResumen({
    required String tituloObra,
    required String capitulo,
    required String texto,
    required bool contieneSpoiler,
  }) async {
    final obraId = normalizarTitulo(tituloObra);
    final user = FirebaseAuth.instance.currentUser!;
    final capNormalizado = _normalizarCapitulo(capitulo);
    if (capNormalizado.isEmpty) {
      throw Exception('Indica el número de capítulo.');
    }

    final resumenRef = _resumenes(obraId).doc('${user.uid}_$capNormalizado');
    final existente = await resumenRef.get();
    if (existente.exists) {
      throw Exception('Ya escribiste un resumen para ese capítulo.');
    }

    final sospechoso = contienePalabraProhibida(texto);

    await resumenRef.set({
      'uid': user.uid,
      'tituloObra': tituloObra.trim(),
      'capitulo': capitulo.trim(),
      'texto': texto.trim(),
      'contieneSpoiler': contieneSpoiler,
      'votosPositivos': 0,
      'estado': sospechoso ? 'pendiente_revision' : 'activo',
      'reportado': sospechoso,
      'creadoEn': FieldValue.serverTimestamp(),
    });

    final logros = await LogrosService().alCrearResumen(user.uid, '$obraId|$capNormalizado');

    return {'sospechoso': sospechoso, 'logrosDesbloqueados': logros};
  }

  /// Resúmenes publicados de una obra, mejor valorados primero.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> resumenesDeObra(String tituloObra) {
    final obraId = normalizarTitulo(tituloObra);
    return _resumenes(obraId)
        .where('estado', isEqualTo: 'activo')
        .orderBy('votosPositivos', descending: true)
        .snapshots()
        .map((s) => s.docs);
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> listarPendientesRevision() async {
    final snap = await FirebaseFirestore.instance
        .collectionGroup('resumenes')
        .where('estado', isEqualTo: 'pendiente_revision')
        .get();
    return snap.docs;
  }

  /// Si el usuario actual ya votó este resumen.
  Future<bool> yaVote({required String obraId, required String resumenId}) async {
    final user = FirebaseAuth.instance.currentUser!;
    final snap =
        await _resumenes(obraId).doc(resumenId).collection('votos').doc(user.uid).get();
    return snap.exists;
  }

  /// Flujo en vivo de si el usuario actual ya votó este resumen (para que
  /// el botón de "me gusta" se actualice solo).
  Stream<bool> yaVoteStream({required String obraId, required String resumenId}) {
    final user = FirebaseAuth.instance.currentUser!;
    return _resumenes(obraId)
        .doc(resumenId)
        .collection('votos')
        .doc(user.uid)
        .snapshots()
        .map((s) => s.exists);
  }

  /// Da o quita el voto positivo del usuario actual a un resumen (no se
  /// puede votar el propio). Cada voto nuevo da 1 token al autor; quitar el
  /// voto se lo resta de vuelta (evita que el autor se beneficie inflando y
  /// desinflando votos).
  Future<void> alternarVoto({required String obraId, required String resumenId}) async {
    final user = FirebaseAuth.instance.currentUser!;
    final resumenRef = _resumenes(obraId).doc(resumenId);
    final votoRef = resumenRef.collection('votos').doc(user.uid);

    final resumenSnap = await resumenRef.get();
    final autorUid = resumenSnap.data()?['uid'] as String?;
    if (autorUid == null || autorUid == user.uid) return;

    final votoSnap = await votoRef.get();
    if (votoSnap.exists) {
      await votoRef.delete();
      await resumenRef.update({'votosPositivos': FieldValue.increment(-1)});
      await TokensService().quitarTokensAUsuario(uid: autorUid, cantidad: tokensPorVoto);
    } else {
      await votoRef.set({'votadoEn': FieldValue.serverTimestamp()});
      await resumenRef.update({'votosPositivos': FieldValue.increment(1)});
      await TokensService().otorgarTokensAUsuario(uid: autorUid, cantidad: tokensPorVoto);
    }
  }

  Future<void> aprobarResumen({required String obraId, required String resumenId}) async {
    await _resumenes(obraId).doc(resumenId).update({
      'estado': 'activo',
      'reportado': false,
    });
  }

  /// Rechaza el resumen (lo oculta) y aplica la penalización de tokens al autor.
  Future<void> rechazarResumen({required String obraId, required String resumenId}) async {
    final resumenRef = _resumenes(obraId).doc(resumenId);
    final snap = await resumenRef.get();
    final uid = snap.data()?['uid'] as String?;

    await resumenRef.update({'estado': 'rechazado', 'reportado': false});
    if (uid != null) {
      await TokensService().quitarTokensAUsuario(uid: uid, cantidad: penalizacionViolacion);
    }
  }
}