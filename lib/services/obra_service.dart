import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tokens_service.dart';

const Map<String, String> camposObra = {
  'genero': 'Género',
  'protagonista': 'Protagonista',
  'autor': 'Autor/Creador',
  'antagonista': 'Antagonista principal',
  'estado': 'Estado (En curso / Finalizado)',
  'anioInicio': 'Año de inicio',
  'rasgoProtagonista': 'Rasgo o poder distintivo del protagonista',
};

/// Tokens que se otorgan por confirmar este campo por primera vez en la plataforma
/// (cuando nadie más lo había validado todavía para esta obra).
const Map<String, int> precioCampoObra = {
  'genero': 2,
  'protagonista': 3,
  'autor': 2,
  'antagonista': 3,
  'estado': 1,
  'anioInicio': 1,
  'rasgoProtagonista': 3,
};

/// Porcentaje de esos tokens que se otorga cuando el campo ya estaba validado
/// y el usuario solo lo vuelve a rellenar (confirmándolo o no).
const double porcentajeCampoRepetido = 0.2;

int _tokensParaCampo(String campo, {required bool esNuevo}) {
  final base = precioCampoObra[campo] ?? 1;
  if (esNuevo) return base;
  final reducido = (base * porcentajeCampoRepetido).round();
  return reducido < 1 ? 1 : reducido;
}

String normalizarTitulo(String titulo) {
  var t = titulo.trim().toLowerCase();
  const acentos = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
    'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
    'ñ': 'n', 'ü': 'u',
  };
  acentos.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  t = t.replaceAll(RegExp(r'^_+|_+$'), '');
  return t.isEmpty ? 'obra_desconocida' : t;
}

String _normalizarValor(String v) => v.trim().toLowerCase();

class ObraService {
  CollectionReference<Map<String, dynamic>> get _obras =>
      FirebaseFirestore.instance.collection('obras');

  CollectionReference<Map<String, dynamic>> _misPropuestas(String uid) =>
      FirebaseFirestore.instance.collection('usuarios').doc(uid).collection('misPropuestas');

  /// Envía los datos que el usuario llenó al guardar una lectura.
  Future<Map<String, int>> enviarDatosObra({
    required String tituloLectura,
    required Map<String, String> valores,
  }) async {
    final obraId = normalizarTitulo(tituloLectura);
    final obraRef = _obras.doc(obraId);
    final user = FirebaseAuth.instance.currentUser!;

    int pendientes = 0;
    int autoValidadas = 0;
    int noCoinciden = 0;
    int tokensGanados = 0;

    await obraRef.set({'tituloOriginal': tituloLectura.trim()}, SetOptions(merge: true));

    final obraSnap = await obraRef.get();
    final data = obraSnap.data() ?? {};
    final campos = Map<String, dynamic>.from(data['campos'] ?? {});

    for (final entry in valores.entries) {
      final campo = entry.key;
      final valor = entry.value.trim();
      if (valor.isEmpty) continue;

      final campoActual = campos[campo] as Map<String, dynamic>?;
      final yaValidado = campoActual?['validado'] == true;
      final tokensCampo = _tokensParaCampo(campo, esNuevo: !yaValidado);
      final propuestaRef = obraRef.collection('propuestas').doc();

      if (yaValidado) {
        final valorValidado = campoActual?['valor'] as String? ?? '';
        final coincide = _normalizarValor(valorValidado) == _normalizarValor(valor);
        final estado = coincide ? 'aprobada' : 'rechazada';
        final tokensFinal = coincide ? tokensCampo : 0;

        await propuestaRef.set({
          'campo': campo,
          'valor': valor,
          'uid': user.uid,
          'estado': estado,
          'tokens': tokensCampo,
          'creadoEn': FieldValue.serverTimestamp(),
        });
        await _misPropuestas(user.uid).doc(propuestaRef.id).set({
          'obraId': obraId,
          'campo': campo,
          'valor': valor,
          'estado': estado,
          'tokens': tokensCampo,
          'visto': false,
          'creadoEn': FieldValue.serverTimestamp(),
        });

        if (coincide) {
          autoValidadas++;
          tokensGanados += tokensFinal;
          if (tokensFinal > 0) {
            await TokensService().otorgarTokensAUsuario(uid: user.uid, cantidad: tokensFinal);
          }
        } else {
          noCoinciden++;
        }
      } else {
        await propuestaRef.set({
          'campo': campo,
          'valor': valor,
          'uid': user.uid,
          'estado': 'pendiente',
          'tokens': tokensCampo,
          'creadoEn': FieldValue.serverTimestamp(),
        });
        await _misPropuestas(user.uid).doc(propuestaRef.id).set({
          'obraId': obraId,
          'campo': campo,
          'valor': valor,
          'estado': 'pendiente',
          'tokens': tokensCampo,
          'visto': false,
          'creadoEn': FieldValue.serverTimestamp(),
        });
        pendientes++;
      }
    }

    return {
      'pendientes': pendientes,
      'autoValidadas': autoValidadas,
      'noCoinciden': noCoinciden,
      'tokensGanados': tokensGanados,
    };
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> listarPendientes() async {
    final snap = await FirebaseFirestore.instance
        .collectionGroup('propuestas')
        .where('estado', isEqualTo: 'pendiente')
        .get();
    return snap.docs;
  }

  Future<void> aprobarPropuesta({
    required String obraId,
    required String propuestaId,
    required String campo,
    required String valor,
  }) async {
    final obraRef = _obras.doc(obraId);
    final propuestaRef = obraRef.collection('propuestas').doc(propuestaId);

    final propuestaSnap = await propuestaRef.get();
    final propuestaData = propuestaSnap.data() ?? {};
    final uid = propuestaData['uid'] as String?;
    final tokens = (propuestaData['tokens'] as num?)?.toInt() ?? 0;

    await obraRef.set({
      'campos': {
        campo: {'valor': valor, 'validado': true},
      },
    }, SetOptions(merge: true));

    await propuestaRef.update({'estado': 'aprobada'});
    if (uid != null) {
      await _misPropuestas(uid).doc(propuestaId).update({'estado': 'aprobada'});
      if (tokens > 0) {
        await TokensService().otorgarTokensAUsuario(uid: uid, cantidad: tokens);
      }
    }

    final otras = await obraRef
        .collection('propuestas')
        .where('campo', isEqualTo: campo)
        .where('estado', isEqualTo: 'pendiente')
        .get();

    for (final doc in otras.docs) {
      final otroData = doc.data();
      final otroValor = otroData['valor'] as String? ?? '';
      final otroUid = otroData['uid'] as String?;
      final otroTokens = (otroData['tokens'] as num?)?.toInt() ?? 0;
      final coincide = _normalizarValor(otroValor) == _normalizarValor(valor);
      final nuevoEstado = coincide ? 'aprobada' : 'rechazada';

      await doc.reference.update({'estado': nuevoEstado});
      if (otroUid != null) {
        await _misPropuestas(otroUid).doc(doc.id).update({'estado': nuevoEstado});
        if (coincide && otroTokens > 0) {
          await TokensService().otorgarTokensAUsuario(uid: otroUid, cantidad: otroTokens);
        }
      }
    }
  }

  Future<void> rechazarPropuesta({
    required String obraId,
    required String propuestaId,
  }) async {
    final propuestaRef = _obras.doc(obraId).collection('propuestas').doc(propuestaId);
    final snap = await propuestaRef.get();
    final uid = snap.data()?['uid'] as String?;

    await propuestaRef.update({'estado': 'rechazada'});
    if (uid != null) {
      await _misPropuestas(uid).doc(propuestaId).update({'estado': 'rechazada'});
    }
  }

  /// Propuestas del usuario cuyo resultado (aprobada/rechazada) aún no ha visto.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> misPropuestasSinVer(String uid) {
    return _misPropuestas(uid)
        .where('visto', isEqualTo: false)
        .where('estado', whereIn: ['aprobada', 'rechazada'])
        .snapshots()
        .map((s) => s.docs);
  }

  Future<void> marcarPropuestasComoVistas(String uid, List<String> propuestaIds) async {
    if (propuestaIds.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in propuestaIds) {
      batch.update(_misPropuestas(uid).doc(id), {'visto': true});
    }
    await batch.commit();
  }
}