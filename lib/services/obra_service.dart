import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tokens_service.dart';
import '../models/lectura.dart' show estadosLectura;

/// Cuántas imágenes genéricas hay en `assets/portadas/` (animal_01.webp ...
/// animal_NN.webp). Si agregas o quitas imágenes de esa carpeta, actualiza
/// este número — es lo único que hay que tocar para que el reparto se ajuste.
const int cantidadPortadasGenericas = 60;

/// Devuelve la ruta del asset de portada genérica (una foto de animal, sin
/// relación con la obra) que le toca a este título. Es determinista: el
/// mismo título siempre cae en la misma imagen, calculado a partir de un
/// hash del título normalizado — no de un contador ni de algo que dependa
/// del orden en que se registraron las obras. Con pocas obras varias van a
/// compartir imagen; eso es esperado, no un error (igual que los avatares
/// por defecto de otras apps).
String rutaPortadaGenerica(String tituloOriginal) {
  final normalizado = normalizarTitulo(tituloOriginal);
  final hash = md5.convert(utf8.encode(normalizado)).bytes;
  // Con los primeros 4 bytes del hash alcanza de sobra para repartir entre
  // las ~60 imágenes sin sesgo perceptible.
  final valor = (hash[0] << 24) | (hash[1] << 16) | (hash[2] << 8) | hash[3];
  final indice = (valor.abs() % cantidadPortadasGenericas) + 1;
  return 'assets/portadas/animal_${indice.toString().padLeft(2, '0')}.webp';
}

/// Etiquetas genéricas de respaldo (se usan donde no aplica el tipo de obra,
/// como en la pantalla de admin). Para el formulario de llenado se usa
/// [etiquetaCampo], que adapta el texto según el tipo (manhwa/manga/novela/...).
const Map<String, String> camposObra = {
  'genero': 'Género(s)',
  'protagonista': 'Protagonista',
  'autor': 'Autor/Creador',
  'estudioArte': 'Estudio de arte',
  'demografia': 'Demografía',
  'estado': 'Estado (En curso / Pausado / Finalizado)',
  'fechaPublicacion': 'Fecha de publicación',
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
  'estado': ['En curso', 'Pausado', 'Finalizado'],
  'demografia': ['Seinen', 'Shonen', 'Josei', 'Shojo'],
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
  'estudioArte': 2,
  'demografia': 2,
  'estado': 1,
  'fechaPublicacion': 1,
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
    case 'estudioArte':
      return 'Estudio de arte $sufijo';
    case 'demografia':
      return 'Demografía $sufijo';
    case 'estado':
      return 'Estado (En curso / Pausado / Finalizado)';
    case 'fechaPublicacion':
      return 'Fecha de publicación $sufijo';
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

/// Identificador único de una obra en el catálogo compartido (`obras/{id}`).
/// Combina título normalizado + tipo porque dos lecturas con el mismo título
/// pero de tipo distinto (ej. el manhwa "X" y la novela "X") son obras
/// distintas, no la misma — aunque cuenten la misma historia, tienen
/// capítulos, lectores y datos propios independientes.
///
/// Si [tipo] viene vacío o no reconocido, se usa 'otro' como respaldo en vez
/// de fallar, para no romper datos viejos que se guardaron sin tipo.
String idObra(String titulo, String? tipo) {
  final tipoNormalizado = (tipo == null || tipo.trim().isEmpty) ? 'otro' : normalizarTitulo(tipo);
  return '${normalizarTitulo(titulo)}__$tipoNormalizado';
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

/// Un usuario que tiene esta obra registrada (+18 incluidas), con el
/// progreso y la plataforma que él mismo guardó. No incluye apodo/foto a
/// propósito: la pantalla de detalle de obra solo muestra totales (cuántos
/// la leen, qué plataformas se usan), nunca quién específicamente.
class LectorDeObra {
  final String uid;
  final String plataforma;
  final String capituloActual;
  final String estado;
  final String link;

  LectorDeObra({
    required this.uid,
    required this.plataforma,
    required this.capituloActual,
    required this.estado,
    required this.link,
  });
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
  ///
  /// [esAdulto] marca la obra como +18 en el catálogo (se muestra con un
  /// ícono en Descubrir en vez de ocultarse). Es "pegajoso" hacia `true`: si
  /// alguien ya la marcó +18, una lectura no-adulta de otro usuario para el
  /// mismo título no la vuelve a poner como segura, para no destapar por
  /// accidente una obra sensible.
  Future<void> registrarObra(String tituloLectura, {String? tipo, bool esAdulto = false}) async {
    final obraId = idObra(tituloLectura, tipo);
    await _obras.doc(obraId).set(
      {
        'tituloOriginal': tituloLectura.trim(),
        if (tipo != null) 'tipo': tipo,
        if (esAdulto) 'esAdulto': true,
      },
      SetOptions(merge: true),
    );
  }

  /// Actualiza, si corresponde, el "capítulo más avanzado" conocido de esta
  /// obra. A diferencia de los demás campos, este NO se propone/valida a
  /// mano: se calcula solo, tomando el capítulo más alto que cualquier
  /// usuario haya guardado como su propio progreso de lectura. Así el
  /// progreso que se muestra en Biblioteca ("3 / 29") siempre refleja hasta
  /// dónde ha llegado el lector más adelantado de la plataforma, sin
  /// depender de que alguien lo llene y mantenga actualizado a mano.
  Future<void> actualizarCapituloMaximo({
    required String tituloLectura,
    required String tipo,
    required String capituloTexto,
    String? link,
  }) async {
    final capitulo = int.tryParse(capituloTexto.trim());
    if (capitulo == null) return;
    final obraRef = _obras.doc(idObra(tituloLectura, tipo));
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(obraRef);
      final actual = (snap.data()?['capituloMaximo'] as num?)?.toInt() ?? 0;
      if (capitulo > actual) {
        final datos = <String, dynamic>{'capituloMaximo': capitulo};
        // Se guarda junto al capítulo más alto el link desde donde se
        // reportó, para que quien añada la obra después pueda ir directo
        // a seguir leyendo desde ahí en vez de buscarlo de cero.
        final linkLimpio = link?.trim();
        if (linkLimpio != null && linkLimpio.isNotEmpty) {
          datos['linkMaximo'] = linkLimpio;
        }
        tx.set(obraRef, datos, SetOptions(merge: true));
      }
    });
  }

  /// Backfill de un solo uso (solo admin, por las reglas de Firestore):
  /// recorre TODAS las lecturas de TODOS los usuarios y registra en `obras`
  /// cualquier título que todavía no esté ahí -sobre todo las +18 que se
  /// guardaron antes de que el registro automático las incluyera-, y de paso
  /// corrige el tipo, el "esAdulto" y el capítulo máximo de las que ya
  /// existían pero quedaron con datos incompletos. Devuelve cuántas obras
  /// nuevas se crearon.
  Future<int> backfillObrasDesdeLecturas() async {
    final snap = await FirebaseFirestore.instance.collectionGroup('lecturas').get();

    // Agrupa por obra (título normalizado) el tipo, si alguna lectura es
    // +18, y el capítulo más alto que cualquiera haya reportado.
    final porObra = <String, Map<String, dynamic>>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final titulo = (data['titulo'] as String? ?? '').trim();
      if (titulo.isEmpty) continue;
      final obraId = idObra(titulo, data['tipo'] as String?);
      final info = porObra.putIfAbsent(
        obraId,
        () => {
          'titulo': titulo,
          'tipo': data['tipo'],
          'esAdulto': false,
          'capituloMaximo': 0,
          'linkMaximo': null,
        },
      );
      if (data['esAdulto'] == true) info['esAdulto'] = true;
      final capitulo = int.tryParse((data['capituloActual'] as String? ?? '').trim());
      if (capitulo != null && capitulo > (info['capituloMaximo'] as int)) {
        info['capituloMaximo'] = capitulo;
        final link = (data['link'] as String? ?? '').trim();
        if (link.isNotEmpty) info['linkMaximo'] = link;
      }
    }

    int creadas = 0;
    for (final entry in porObra.entries) {
      final obraRef = _obras.doc(entry.key);
      final obraSnapAntes = await obraRef.get();
      final info = entry.value;

      await registrarObra(
        info['titulo'] as String,
        tipo: info['tipo'] as String?,
        esAdulto: info['esAdulto'] as bool,
      );

      final maximoVisto = info['capituloMaximo'] as int;
      final maximoActual = (obraSnapAntes.data()?['capituloMaximo'] as num?)?.toInt() ?? 0;
      if (maximoVisto > maximoActual) {
        final datos = <String, dynamic>{'capituloMaximo': maximoVisto};
        final linkVisto = info['linkMaximo'] as String?;
        if (linkVisto != null) datos['linkMaximo'] = linkVisto;
        await obraRef.set(datos, SetOptions(merge: true));
      }

      if (!obraSnapAntes.exists) creadas++;
    }

    // Backfill de "obras/{obraId}/lectores/{uid}": sin esto, los lectores
    // que ya tenían la obra guardada ANTES de que existiera este resumen por
    // usuario no aparecerían en el conteo de la pantalla de detalle hasta
    // que volvieran a guardar su lectura.
    for (final doc in snap.docs) {
      final data = doc.data();
      final titulo = (data['titulo'] as String? ?? '').trim();
      if (titulo.isEmpty) continue;
      final uid = doc.reference.parent.parent?.id;
      if (uid == null) continue;
      final obraId = idObra(titulo, data['tipo'] as String?);
      await _obras.doc(obraId).collection('lectores').doc(uid).set({
        'estado': estadosLectura.containsKey(data['estado']) ? data['estado'] : 'leyendo',
        'plataforma': (data['plataforma'] as String? ?? '').trim(),
        'capituloActual': (data['capituloActual'] as String? ?? '').trim(),
        'link': (data['link'] as String? ?? '').trim(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return creadas;
  }

  /// Guarda/actualiza "mi" entrada en `obras/{obraId}/lectores/{uid}` cada
  /// vez que guardo una lectura (sea +18 o no). Es la fuente de la que se
  /// arma el conteo de lectores y plataformas en la pantalla de detalle de
  /// obra: cada usuario escribe únicamente SU propio documento (igual patrón
  /// que "likes"), así que no hace falta leer las lecturas de nadie más para
  /// armar el total -eso es lo que antes rompía con +18, porque las reglas
  /// de Firestore protegen esas lecturas de ser leídas por otros usuarios.
  Future<void> actualizarResumenLector({
    required String tituloLectura,
    required String tipo,
    required String estado,
    required String plataforma,
    required String capituloActual,
    required String link,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final obraId = idObra(tituloLectura, tipo);
    await _obras.doc(obraId).collection('lectores').doc(user.uid).set({
      'estado': estado,
      'plataforma': plataforma.trim(),
      'capituloActual': capituloActual.trim(),
      'link': link.trim(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Borra "mi" entrada de `obras/{obraId}/lectores/{uid}` (cuando elimino
  /// esa lectura de mi Biblioteca/Bóveda).
  Future<void> eliminarResumenLector(String tituloLectura, String tipo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final obraId = idObra(tituloLectura, tipo);
    await _obras.doc(obraId).collection('lectores').doc(user.uid).delete();
  }

  /// Lectores de esta obra (+18 incluidas): uno por cada usuario que tenga
  /// un documento en `obras/{obraId}/lectores`, con la plataforma y el
  /// capítulo que él mismo guardó. A diferencia de antes, no depende de leer
  /// las lecturas privadas de otros usuarios (lo cual las reglas de
  /// Firestore no permiten para +18), así que funciona igual para cualquier
  /// obra.
  Future<List<LectorDeObra>> obtenerLectoresDeObra(String tituloLectura, String tipo) async {
    final obraId = idObra(tituloLectura, tipo);
    final snap = await _obras.doc(obraId).collection('lectores').get();

    return snap.docs.map((doc) {
      final data = doc.data();
      return LectorDeObra(
        uid: doc.id,
        plataforma: (data['plataforma'] as String? ?? '').trim(),
        capituloActual: (data['capituloActual'] as String? ?? '').trim(),
        estado: estadosLectura.containsKey(data['estado']) ? data['estado'] as String : 'leyendo',
        link: (data['link'] as String? ?? '').trim(),
      );
    }).toList();
  }

  /// Si el usuario actual ya le dio "me gusta" a esta obra.
  Future<bool> yaLeDiLike(String tituloLectura, String tipo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final obraId = idObra(tituloLectura, tipo);
    final doc = await _obras.doc(obraId).collection('likes').doc(user.uid).get();
    return doc.exists;
  }

  /// Da o quita el "me gusta" del usuario actual a esta obra. El contador
  /// `likes` del documento de la obra se recalcula dentro de la misma
  /// transacción a partir de su valor guardado +1/-1, nunca contando toda
  /// la subcolección de nuevo (sería caro). Devuelve true si quedó "dado".
  Future<bool> alternarLike(String tituloLectura, String tipo) async {
    final user = FirebaseAuth.instance.currentUser!;
    final obraId = idObra(tituloLectura, tipo);
    final obraRef = _obras.doc(obraId);
    final likeRef = obraRef.collection('likes').doc(user.uid);

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      final obraSnap = await tx.get(obraRef);
      final actual = (obraSnap.data()?['likes'] as num?)?.toInt() ?? 0;

      if (likeSnap.exists) {
        tx.delete(likeRef);
        tx.set(obraRef, {'likes': actual > 0 ? actual - 1 : 0}, SetOptions(merge: true));
        return false;
      } else {
        tx.set(likeRef, {'creadoEn': FieldValue.serverTimestamp()});
        tx.set(obraRef, {'likes': actual + 1}, SetOptions(merge: true));
        return true;
      }
    });
  }

  /// Campos de esta obra ya validados por el admin (campo -> valor).
  /// Úsalo para bloquear en el formulario los campos que ya tienen dato correcto.
  Future<Map<String, dynamic>> obtenerCamposValidados(String tituloLectura, String tipo) async {
    final obraId = idObra(tituloLectura, tipo);
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
    required String tipo,
    required Map<String, String> valores,
  }) async {
    final obraId = idObra(tituloLectura, tipo);
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

  /// Fusiona dos obras que en realidad son la misma pero quedaron
  /// registradas con títulos distintos (ej. "Stream del Arquero Genio" vs
  /// "Streaming del Arquero Genio"): mueve TODO lo de [tituloViejo] hacia
  /// [tituloNuevo] -resúmenes, sus votos, y propuestas pendientes/revisadas
  /// (incluida la copia de cada usuario en "misPropuestas")- y corrige el
  /// campo "titulo" en la lectura de cada usuario que tenía guardado el
  /// título viejo, para que no se vuelva a crear la obra vieja la próxima
  /// vez que alguien edite esa lectura. Al final borra la obra vieja.
  ///
  /// No es una operación atómica (toca muchos documentos repartidos en
  /// varias colecciones); si falla a mitad de camino, se puede volver a
  /// correr sin duplicar lo que ya se alcanzó a mover.
  Future<void> fusionarObras({
    required String tituloViejo,
    required String tipoViejo,
    required String tituloNuevo,
    required String tipoNuevo,
  }) async {
    final idViejo = idObra(tituloViejo, tipoViejo);
    final idNuevo = idObra(tituloNuevo, tipoNuevo);
    if (idViejo == idNuevo) {
      throw Exception('Esos dos títulos ya apuntan a la misma obra.');
    }

    final refViejo = _obras.doc(idViejo);
    final refNuevo = _obras.doc(idNuevo);

    final snapViejo = await refViejo.get();
    if (!snapViejo.exists) {
      throw Exception('No existe ninguna obra registrada con el título anterior.');
    }
    final dataViejo = snapViejo.data() ?? {};
    final snapNuevo = await refNuevo.get();
    final dataNuevo = snapNuevo.data() ?? {};

    // 1) Fusiona los datos de la obra: lo que ya tenga la obra destino se
    // conserva, y se completa con lo que le falte desde la obra vieja.
    final camposViejo = Map<String, dynamic>.from(dataViejo['campos'] ?? {});
    final camposNuevo = Map<String, dynamic>.from(dataNuevo['campos'] ?? {});
    final camposFusionados = {...camposViejo, ...camposNuevo};

    await refNuevo.set({
      'tituloOriginal': tituloNuevo.trim(),
      if (camposFusionados.isNotEmpty) 'campos': camposFusionados,
      if ((dataNuevo['tipo'] ?? dataViejo['tipo']) != null)
        'tipo': dataNuevo['tipo'] ?? dataViejo['tipo'],
    }, SetOptions(merge: true));

    // 2) Migra resúmenes y sus votos, uno por uno.
    final resumenesViejos = await refViejo.collection('resumenes').get();
    for (final doc in resumenesViejos.docs) {
      final nuevoResumenRef = refNuevo.collection('resumenes').doc(doc.id);
      await nuevoResumenRef.set(doc.data());

      final votos = await doc.reference.collection('votos').get();
      for (final voto in votos.docs) {
        await nuevoResumenRef.collection('votos').doc(voto.id).set(voto.data());
        await voto.reference.delete();
      }
      await doc.reference.delete();
    }

    // 3) Migra propuestas y su copia en "misPropuestas" de cada proponente.
    final propuestasViejas = await refViejo.collection('propuestas').get();
    for (final doc in propuestasViejas.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['tituloObra'] = tituloNuevo.trim();
      await refNuevo.collection('propuestas').doc(doc.id).set(data);

      final uidProponente = data['uid'] as String?;
      if (uidProponente != null) {
        final misPropRef = FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uidProponente)
            .collection('misPropuestas')
            .doc(doc.id);
        if ((await misPropRef.get()).exists) {
          await misPropRef.update({'obraId': idNuevo, 'tituloObra': tituloNuevo.trim()});
        }
      }
      await doc.reference.delete();
    }

    // 4) Corrige el título guardado en la lectura de cada usuario que tenía
    // el título viejo (para que se vea bien en su Biblioteca y no "resucite"
    // la obra vieja la próxima vez que la edite/guarde).
    final todasLasLecturas = await FirebaseFirestore.instance.collectionGroup('lecturas').get();
    for (final doc in todasLasLecturas.docs) {
      final data = doc.data();
      final tituloLectura = (data['titulo'] as String? ?? '').trim();
      final tipoLectura = data['tipo'] as String?;
      if (tituloLectura.isNotEmpty && idObra(tituloLectura, tipoLectura) == idViejo) {
        await doc.reference.update({'titulo': tituloNuevo.trim()});
      }
    }

    // 5) La obra vieja ya quedó sin subcolecciones; se borra el documento.
    await refViejo.delete();
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