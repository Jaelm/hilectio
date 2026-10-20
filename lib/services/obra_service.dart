import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tokens_service.dart';

/// Etiquetas genéricas de respaldo (se usan donde no aplica el tipo de obra,
/// como en la pantalla de admin). Para el formulario de llenado se usa
/// [etiquetaCampo], que adapta el texto según el tipo (manhwa/manga/novela/...).
const Map<String, String> camposObra = {
  'genero': 'Género(s)',
  'protagonista': 'Protagonista',
  'autor': 'Autor/Creador',
  'antagonista': 'Antagonista principal',
  'estado': 'Estado (En curso / Finalizado)',
  'fechaPublicacion': 'Fecha de publicación',
  'capituloTotal': 'Último capítulo/tomo publicado',
};

/// Campos cuyo valor es una fecha (día/mes/año) elegida con un selector,
/// guardada internamente como texto ISO "yyyy-MM-dd".
const Set<String> camposDeFecha = {'fechaPublicacion'};

/// Campos que aceptan más de un valor (el usuario los separa por comas).
const Set<String> camposMultivaluados = {'genero'};

/// Campos de opción cerrada (se eligen de una lista fija en vez de texto
/// libre), para que después se puedan usar como filtro confiable en
/// Descubrir sin depender de cómo cada usuario escribió el valor.
const Map<String, List<String>> opcionesCampo = {
  'estado': ['En curso', 'Finalizado'],
};

/// Tipos de lectura disponibles (los mismos que en el formulario de
/// agregar/editar lectura), usados también para guardar el tipo a nivel de
/// obra compartida y poder filtrar por él en Descubrir.
const List<String> tiposLectura = ['Manhwa', 'Manga', 'Manhua', 'Novela', 'Libro', 'Otro'];

/// Tokens que se otorgan por confirmar este campo por primera vez en la plataforma
/// (cuando nadie más lo había validado todavía para esta obra).
const Map<String, int> precioCampoObra = {
  'genero': 2,
  'protagonista': 3,
  'autor': 2,
  'antagonista': 3,
  'estado': 1,
  'fechaPublicacion': 1,
  'capituloTotal': 1,
};

/// Porcentaje de esos tokens que se otorga cuando el campo ya estaba validado
/// y el usuario solo lo vuelve a rellenar coincidiendo con lo ya registrado.
const double porcentajeCampoRepetido = 0.2;

int _tokensParaCampo(String campo, {required bool esNuevo}) {
  final base = precioCampoObra[campo] ?? 1;
  if (esNuevo) return base;
  final reducido = (base * porcentajeCampoRepetido).round();
  return reducido < 1 ? 1 : reducido;
}

String _sufijoTipo(String tipo) {
  switch (tipo) {
    case 'Manhwa':
      return 'del manhwa';
    case 'Manga':
      return 'del manga';
    case 'Manhua':
      return 'del manhua';
    case 'Novela':
      return 'de la novela';
    case 'Libro':
      return 'del libro';
    default:
      return 'de la obra';
  }
}

/// Etiqueta de un campo de la obra, adaptada al tipo de lectura
/// (ej. "Autor/Creador de la novela" vs "Autor/Creador del manhwa").
String etiquetaCampo(String campo, String tipo) {
  final sufijo = _sufijoTipo(tipo);
  switch (campo) {
    case 'genero':
      return 'Género(s) $sufijo';
    case 'protagonista':
      return 'Protagonista $sufijo';
    case 'autor':
      return 'Autor/Creador $sufijo';
    case 'antagonista':
      return 'Antagonista principal $sufijo';
    case 'estado':
      return 'Estado (En curso / Finalizado)';
    case 'fechaPublicacion':
      return 'Fecha de publicación $sufijo';
    case 'capituloTotal':
      return 'Último capítulo/tomo publicado $sufijo';
    default:
      return camposObra[campo] ?? campo;
  }
}

/// Convierte una fecha ISO "yyyy-MM-dd" a "dd/mm/yyyy" para mostrarla.
/// Si no tiene ese formato, devuelve el texto tal cual.
String formatearFechaISOaDisplay(String iso) {
  final partes = iso.split('-');
  if (partes.length != 3) return iso;
  final anio = partes[0];
  final mes = partes[1];
  final dia = partes[2];
  if (anio.length != 4 || mes.length != 2 || dia.length != 2) return iso;
  return '$dia/$mes/$anio';
}

/// Convierte una [DateTime] a texto ISO "yyyy-MM-dd" para guardarla.
String formatearFechaADisplayISO(DateTime fecha) {
  final anio = fecha.year.toString().padLeft(4, '0');
  final mes = fecha.month.toString().padLeft(2, '0');
  final dia = fecha.day.toString().padLeft(2, '0');
  return '$anio-$mes-$dia';
}

/// Muestra el valor de un campo (que puede ser texto, una lista como género,
/// o una fecha ISO guardada en [camposDeFecha]).
String formatearValorCampo(dynamic valor, {String? campo}) {
  if (valor is List) return valor.map((e) => e.toString()).join(', ');
  final texto = valor?.toString() ?? '';
  if (campo != null && camposDeFecha.contains(campo)) {
    return formatearFechaISOaDisplay(texto);
  }
  return texto;
}

dynamic _parsearValorCampo(String campo, String textoCrudo) {
  if (camposMultivaluados.contains(campo)) {
    return textoCrudo
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }
  return textoCrudo.trim();
}

/// Si [url] es un link para compartir de Google Drive (de la forma
/// ".../file/d/ID/view..." o "...?id=ID..."), lo convierte al formato que sí
/// se puede mostrar como imagen dentro de la app. Si no reconoce el patrón,
/// devuelve la url tal cual (para admitir imágenes de otros sitios).
String convertirLinkDriveADirecto(String url) {
  final texto = url.trim();
  final porCarpeta = RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(texto);
  if (porCarpeta != null) {
    return 'https://lh3.googleusercontent.com/d/${porCarpeta.group(1)}';
  }
  final porParametro = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(texto);
  if (porParametro != null) {
    return 'https://lh3.googleusercontent.com/d/${porParametro.group(1)}';
  }
  return texto;
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

Set<String> _normalizarParaComparar(dynamic valor) {
  if (valor is List) {
    return valor.map((e) => _normalizarValor(e.toString())).toSet();
  }
  return {_normalizarValor(valor?.toString() ?? '')};
}

/// Compara dos valores de campo (texto o lista de géneros) sin importar
/// orden, mayúsculas/acentos de más o espacios.
bool _coincideValor(dynamic a, dynamic b) {
  final sa = _normalizarParaComparar(a);
  final sb = _normalizarParaComparar(b);
  return sa.length == sb.length && sa.containsAll(sb);
}

class ObraService {
  CollectionReference<Map<String, dynamic>> get _obras =>
      FirebaseFirestore.instance.collection('obras');

  CollectionReference<Map<String, dynamic>> _misPropuestas(String uid) =>
      FirebaseFirestore.instance.collection('usuarios').doc(uid).collection('misPropuestas');

  /// Registra (o solo "toca") la obra en la colección pública `obras`, aunque
  /// el usuario no haya llenado ningún dato extra (género, protagonista...).
  /// Sin esto, una obra solo aparecía en `obras` -y por lo tanto en
  /// Descubrir- si alguien llenaba esos campos; ahora toda lectura agregada
  /// queda indexada para que se pueda encontrar por título.
  ///
  /// [tipo] (Manhwa/Manga/Manhua/Novela/Libro/Otro) también se guarda a nivel
  /// de obra (no solo en la lectura personal de cada quien) para poder
  /// filtrar por tipo en Descubrir; el último que guarda "gana" (no pasa por
  /// el sistema de propuestas/validación porque es una lista cerrada, no un
  /// dato que valga la pena disputar).
  Future<void> registrarObra(String tituloLectura, {String? tipo}) async {
    final obraId = normalizarTitulo(tituloLectura);
    await _obras.doc(obraId).set(
      {
        'tituloOriginal': tituloLectura.trim(),
        if (tipo != null) 'tipo': tipo,
      },
      SetOptions(merge: true),
    );
  }

  /// Guarda/actualiza la portada de la obra (solo admin, ver reglas de
  /// Firestore). Acepta un link de Drive tal cual lo da el botón "Compartir"
  /// y lo convierte internamente al formato que sí se puede mostrar.
  Future<void> actualizarPortada({
    required String tituloLectura,
    required String urlImagen,
  }) async {
    final obraId = normalizarTitulo(tituloLectura);
    final urlFinal = convertirLinkDriveADirecto(urlImagen);
    await _obras.doc(obraId).set({'imagenUrl': urlFinal}, SetOptions(merge: true));
  }

  /// Campos de esta obra ya validados por el admin (campo -> valor).
  /// Úsalo para bloquear en el formulario los campos que ya tienen dato correcto.
  Future<Map<String, dynamic>> obtenerCamposValidados(String tituloLectura) async {
    final obraId = normalizarTitulo(tituloLectura);
    final snap = await _obras.doc(obraId).get();
    final data = snap.data() ?? {};
    final campos = Map<String, dynamic>.from(data['campos'] ?? {});
    final resultado = <String, dynamic>{};
    campos.forEach((k, v) {
      if (v is Map && v['validado'] == true) {
        resultado[k] = v['valor'];
      }
    });
    return resultado;
  }

  /// Envía los datos que el usuario llenó al guardar una lectura.
  /// Solo se deben pasar campos que el usuario pudo editar (es decir, que no
  /// estaban ya bloqueados por [obtenerCamposValidados]).
  Future<Map<String, int>> enviarDatosObra({
    required String tituloLectura,
    required Map<String, String> valores,
  }) async {
    final obraId = normalizarTitulo(tituloLectura);
    final obraRef = _obras.doc(obraId);
    final user = FirebaseAuth.instance.currentUser!;
    final tituloObra = tituloLectura.trim();

    int pendientes = 0;
    int autoValidadas = 0;
    int noCoinciden = 0;
    int tokensGanados = 0;

    await obraRef.set({'tituloOriginal': tituloObra}, SetOptions(merge: true));

    final obraSnap = await obraRef.get();
    final data = obraSnap.data() ?? {};
    final campos = Map<String, dynamic>.from(data['campos'] ?? {});

    for (final entry in valores.entries) {
      final campo = entry.key;
      final textoCrudo = entry.value.trim();
      if (textoCrudo.isEmpty) continue;

      final valorParseado = _parsearValorCampo(campo, textoCrudo);
      final esVacio =
          valorParseado is List ? valorParseado.isEmpty : (valorParseado as String).isEmpty;
      if (esVacio) continue;

      final campoActual = campos[campo] as Map<String, dynamic>?;
      final yaValidado = campoActual?['validado'] == true;

      // Si ya está validado, el campo debería llegar bloqueado desde la UI
      // (no editable); esto es una red de seguridad por si hay una carrera
      // entre dos usuarios editando casi al mismo tiempo.
      if (yaValidado) {
        final tokensCampo = _tokensParaCampo(campo, esNuevo: false);
        final coincide = _coincideValor(campoActual?['valor'], valorParseado);
        final estado = coincide ? 'aprobada' : 'rechazada';
        final tokensFinal = coincide ? tokensCampo : 0;
        final propuestaRef = obraRef.collection('propuestas').doc();

        await propuestaRef.set({
          'campo': campo,
          'valor': valorParseado,
          'uid': user.uid,
          'estado': estado,
          'tokens': tokensCampo,
          'tituloObra': tituloObra,
          'creadoEn': FieldValue.serverTimestamp(),
        });
        await _misPropuestas(user.uid).doc(propuestaRef.id).set({
          'obraId': obraId,
          'tituloObra': tituloObra,
          'campo': campo,
          'valor': valorParseado,
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
        continue;
      }

      // Campo aún no validado: si este mismo usuario ya tiene una propuesta
      // pendiente para este campo de esta obra, se actualiza en vez de crear
      // otra (evita que acumule varias y se lleve tokens multiplicados el
      // día que el admin apruebe una).
      final tokensCampo = _tokensParaCampo(campo, esNuevo: true);
      final pendienteExistente = await obraRef
          .collection('propuestas')
          .where('campo', isEqualTo: campo)
          .where('uid', isEqualTo: user.uid)
          .where('estado', isEqualTo: 'pendiente')
          .limit(1)
          .get();

      if (pendienteExistente.docs.isNotEmpty) {
        final propuestaRef = pendienteExistente.docs.first.reference;
        await propuestaRef.update({
          'valor': valorParseado,
          'tokens': tokensCampo,
          'tituloObra': tituloObra,
        });
        await _misPropuestas(user.uid).doc(propuestaRef.id).update({
          'valor': valorParseado,
          'tokens': tokensCampo,
          'tituloObra': tituloObra,
          'visto': false,
        });
      } else {
        final propuestaRef = obraRef.collection('propuestas').doc();
        await propuestaRef.set({
          'campo': campo,
          'valor': valorParseado,
          'uid': user.uid,
          'estado': 'pendiente',
          'tokens': tokensCampo,
          'tituloObra': tituloObra,
          'creadoEn': FieldValue.serverTimestamp(),
        });
        await _misPropuestas(user.uid).doc(propuestaRef.id).set({
          'obraId': obraId,
          'tituloObra': tituloObra,
          'campo': campo,
          'valor': valorParseado,
          'estado': 'pendiente',
          'tokens': tokensCampo,
          'visto': false,
          'creadoEn': FieldValue.serverTimestamp(),
        });
      }
      pendientes++;
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
    required dynamic valor,
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

    // Igual que en rechazarPropuesta: la propuesta y la copia del usuario
    // cambian juntas en un batch, para que nunca queden desincronizadas.
    final batchPrincipal = FirebaseFirestore.instance.batch();
    batchPrincipal.update(propuestaRef, {'estado': 'aprobada'});
    if (uid != null) {
      batchPrincipal.update(_misPropuestas(uid).doc(propuestaId), {'estado': 'aprobada'});
    }
    await batchPrincipal.commit();
    if (uid != null && tokens > 0) {
      await TokensService().otorgarTokensAUsuario(uid: uid, cantidad: tokens);
    }

    final otras = await obraRef
        .collection('propuestas')
        .where('campo', isEqualTo: campo)
        .where('estado', isEqualTo: 'pendiente')
        .get();

    if (otras.docs.isNotEmpty) {
      final batchOtras = FirebaseFirestore.instance.batch();
      for (final doc in otras.docs) {
        final otroData = doc.data();
        final otroUid = otroData['uid'] as String?;
        final coincide = _coincideValor(otroData['valor'], valor);
        final nuevoEstado = coincide ? 'aprobada' : 'rechazada';

        batchOtras.update(doc.reference, {'estado': nuevoEstado});
        if (otroUid != null) {
          batchOtras.update(_misPropuestas(otroUid).doc(doc.id), {'estado': nuevoEstado});
        }
      }
      await batchOtras.commit();

      for (final doc in otras.docs) {
        final otroData = doc.data();
        final otroUid = otroData['uid'] as String?;
        final otroTokens = (otroData['tokens'] as num?)?.toInt() ?? 0;
        final coincide = _coincideValor(otroData['valor'], valor);
        if (coincide && otroUid != null && otroTokens > 0) {
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

    // Un solo batch: o cambian los dos documentos (la propuesta y la copia
    // del usuario) o no cambia ninguno. Antes, si el segundo write fallaba
    // (por ejemplo por permisos), la propuesta quedaba "rechazada" pero el
    // aviso del usuario se quedaba pegado en "pendiente" para siempre.
    final batch = FirebaseFirestore.instance.batch();
    batch.update(propuestaRef, {'estado': 'rechazada'});
    if (uid != null) {
      batch.update(_misPropuestas(uid).doc(propuestaId), {'estado': 'rechazada'});
    }
    await batch.commit();
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