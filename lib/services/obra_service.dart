import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Map<String, String> camposObra = {
  'genero': 'Género',
  'protagonista': 'Protagonista',
  'autor': 'Autor/Creador',
  'antagonista': 'Antagonista principal',
  'estado': 'Estado (En curso / Finalizado)',
  'anioInicio': 'Año de inicio',
  'rasgoProtagonista': 'Rasgo o poder distintivo del protagonista',
};

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

      if (yaValidado) {
        final valorValidado = campoActual?['valor'] as String? ?? '';
        final coincide = _normalizarValor(valorValidado) == _normalizarValor(valor);
        await obraRef.collection('propuestas').add({
          'campo': campo,
          'valor': valor,
          'uid': user.uid,
          'estado': coincide ? 'aprobada' : 'rechazada',
          'creadoEn': FieldValue.serverTimestamp(),
        });
        if (coincide) {
          autoValidadas++;
        } else {
          noCoinciden++;
        }
      } else {
        await obraRef.collection('propuestas').add({
          'campo': campo,
          'valor': valor,
          'uid': user.uid,
          'estado': 'pendiente',
          'creadoEn': FieldValue.serverTimestamp(),
        });
        pendientes++;
      }
    }

    return {
      'pendientes': pendientes,
      'autoValidadas': autoValidadas,
      'noCoinciden': noCoinciden,
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

    await obraRef.set({
      'campos': {
        campo: {'valor': valor, 'validado': true},
      },
    }, SetOptions(merge: true));

    await obraRef.collection('propuestas').doc(propuestaId).update({'estado': 'aprobada'});

    final otras = await obraRef
        .collection('propuestas')
        .where('campo', isEqualTo: campo)
        .where('estado', isEqualTo: 'pendiente')
        .get();

    for (final doc in otras.docs) {
      final otroValor = doc.data()['valor'] as String? ?? '';
      final coincide = _normalizarValor(otroValor) == _normalizarValor(valor);
      await doc.reference.update({'estado': coincide ? 'aprobada' : 'rechazada'});
    }
  }

  Future<void> rechazarPropuesta({
    required String obraId,
    required String propuestaId,
  }) async {
    await _obras.doc(obraId).collection('propuestas').doc(propuestaId).update({'estado': 'rechazada'});
  }
}