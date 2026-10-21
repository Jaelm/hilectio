import 'package:cloud_firestore/cloud_firestore.dart';
import 'obra_service.dart' show normalizarTitulo, convertirLinkDriveADirecto;

class EstadisticaPlataforma {
  final String clave;
  final String etiqueta;
  final String? imagenUrl;
  final int usuarios;
  final int lecturas;

  EstadisticaPlataforma({
    required this.clave,
    required this.etiqueta,
    required this.imagenUrl,
    required this.usuarios,
    required this.lecturas,
  });
}

class LecturaDePlataforma {
  final String obraId;
  final String titulo;
  LecturaDePlataforma(this.obraId, this.titulo);
}

class PlataformasService {
  CollectionReference<Map<String, dynamic>> get _plataformas =>
      FirebaseFirestore.instance.collection('plataformas');

  /// Calcula, entre las lecturas no +18 de todos los usuarios, cuántos
  /// usuarios distintos usa cada plataforma y cuántas lecturas "únicas"
  /// tiene (esta pestaña es pública, así que las +18 quedan siempre fuera,
  /// sin excepción ni para el admin). El filtro `esAdulto == false` es
  /// obligatorio en la consulta: las reglas de Firestore de
  /// `collectionGroup('lecturas')` dependen de ese campo, y sin el filtro
  /// Firestore rechaza la consulta completa con "permission denied" para
  /// cualquier cuenta que no sea la del admin.
  ///
  /// "Únicas" = por combinación usuario+obra, no por documento suelto: si
  /// alguien agregó la misma obra dos veces por error (quedó duplicada), eso
  /// no debe inflar el conteo de lecturas de esa plataforma.
  Future<List<EstadisticaPlataforma>> calcularRanking() async {
    final snap = await FirebaseFirestore.instance
        .collectionGroup('lecturas')
        .where('esAdulto', isEqualTo: false)
        .get();

    final usuariosPorClave = <String, Set<String>>{};
    final combinacionesVistas = <String>{};
    final lecturasPorClave = <String, int>{};
    final etiquetaPorClave = <String, String>{};

    for (final doc in snap.docs) {
      final data = doc.data();
      final crudo = (data['plataforma'] as String? ?? '').trim();
      if (crudo.isEmpty) continue;
      final clave = crudo.toLowerCase();
      etiquetaPorClave.putIfAbsent(clave, () => crudo);

      final uid = doc.reference.parent.parent?.id ?? '';
      if (uid.isNotEmpty) {
        usuariosPorClave.putIfAbsent(clave, () => {}).add(uid);
      }

      final obraId = normalizarTitulo(data['titulo'] as String? ?? '');
      final combinacion = '$uid|$obraId|$clave';
      if (combinacionesVistas.add(combinacion)) {
        lecturasPorClave[clave] = (lecturasPorClave[clave] ?? 0) + 1;
      }
    }

    final iconosSnap = await _plataformas.get();
    final iconosPorClave = <String, String?>{
      for (final d in iconosSnap.docs) d.id: d.data()['imagenUrl'] as String?,
    };

    final lista = etiquetaPorClave.keys.map((clave) {
      return EstadisticaPlataforma(
        clave: clave,
        etiqueta: etiquetaPorClave[clave]!,
        imagenUrl: iconosPorClave[clave],
        usuarios: usuariosPorClave[clave]?.length ?? 0,
        lecturas: lecturasPorClave[clave] ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.usuarios.compareTo(a.usuarios));

    return lista;
  }

  /// Obras distintas registradas en esta plataforma (sin mostrar quién las
  /// registró, solo el título). Igual que en [calcularRanking], las +18
  /// quedan siempre fuera y el filtro es obligatorio para que la consulta
  /// no sea rechazada por las reglas de Firestore.
  Future<List<LecturaDePlataforma>> obtenerLecturasDePlataforma(String clave) async {
    final snap = await FirebaseFirestore.instance
        .collectionGroup('lecturas')
        .where('esAdulto', isEqualTo: false)
        .get();
    final vistos = <String, String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final crudo = (data['plataforma'] as String? ?? '').trim();
      if (crudo.isEmpty || crudo.toLowerCase() != clave) continue;
      final titulo = (data['titulo'] as String? ?? '').trim();
      if (titulo.isEmpty) continue;
      vistos.putIfAbsent(normalizarTitulo(titulo), () => titulo);
    }
    final lista = vistos.entries.map((e) => LecturaDePlataforma(e.key, e.value)).toList()
      ..sort((a, b) => a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase()));
    return lista;
  }

  /// Guarda/actualiza el ícono de una plataforma (solo admin, ver reglas de
  /// Firestore). Acepta un link de Drive tal cual lo da "Compartir".
  Future<void> actualizarIconoPlataforma({
    required String clave,
    required String etiqueta,
    required String urlImagen,
  }) async {
    final urlFinal = convertirLinkDriveADirecto(urlImagen);
    await _plataformas.doc(clave).set(
      {'nombre': etiqueta, 'imagenUrl': urlFinal},
      SetOptions(merge: true),
    );
  }
}