import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/lectura.dart';
import 'obra_service.dart';

/// Una pregunta ya armada y lista para mostrar: si [opciones] es null se
/// responde escribiendo (dificultad Infernal); si no, es de selección
/// múltiple (Fácil/Normal/Difícil).
class PreguntaCuestionario {
  final String obraTitulo;
  final String enunciado;
  final String respuestaCorrecta;
  final List<String>? opciones;

  /// Solo true para la pregunta de "género" en Infernal: en vez de todo o
  /// nada, admite acierto parcial (ver [puntaje]).
  final bool multivaluada;

  String? respuestaUsuario;

  PreguntaCuestionario({
    required this.obraTitulo,
    required this.enunciado,
    required this.respuestaCorrecta,
    this.opciones,
    this.multivaluada = false,
  });

  /// 1 = acierto completo, 0.5 = acierto parcial (solo posible en la
  /// pregunta de género, con al menos 40% de los géneros correctos
  /// mencionados), 0 = no acertó.
  double get puntaje {
    final r = respuestaUsuario;
    if (r == null || r.trim().isEmpty) return 0;
    if (opciones != null) return r == respuestaCorrecta ? 1 : 0;
    if (multivaluada) return _puntajeMultivaluado(r, respuestaCorrecta);
    return _normalizarRespuestaLibre(r) == _normalizarRespuestaLibre(respuestaCorrecta) ? 1 : 0;
  }

  bool get esCorrecta => puntaje >= 1;
}

/// Puntaje para la pregunta de "género" en Infernal: se compara cada género
/// correcto (por separado) contra el texto que escribió el usuario. Con el
/// 100% de los géneros mencionados da el punto completo; con al menos 40%,
/// medio punto; si no, nada.
double _puntajeMultivaluado(String respuesta, String correctaFormateada) {
  final correctos = correctaFormateada
      .split(',')
      .map((e) => _normalizarRespuestaLibre(e))
      .where((e) => e.isNotEmpty)
      .toSet();
  if (correctos.isEmpty) return 0;
  final textoRespuesta = _normalizarRespuestaLibre(respuesta);
  final aciertos = correctos.where((g) => textoRespuesta.contains(g)).length;
  final proporcion = aciertos / correctos.length;
  if (proporcion >= 1) return 1;
  if (proporcion >= 0.4) return 0.5;
  return 0;
}

/// Compara respuestas escritas a mano (dificultad Infernal) sin que
/// mayúsculas, tildes o espacios de más cuenten como error: el contenido
/// tiene que ser correcto, un detalle de tipeo no.
String _normalizarRespuestaLibre(String v) {
  var t = v.trim().toLowerCase();
  const acentos = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
    'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
    'ñ': 'n', 'ü': 'u',
  };
  acentos.forEach((k, val) => t = t.replaceAll(k, val));
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

class ConfigDificultadCuestionario {
  final String id;
  final String nombre;
  final String descripcion;
  final int numPreguntas;
  final int segundosPorPregunta;
  final bool respuestaLibre;

  /// Tokens que se ganan según cuántas preguntas se acertaron (índice =
  /// cantidad de aciertos, 0..numPreguntas).
  final List<int> recompensaPorAciertos;

  const ConfigDificultadCuestionario({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.numPreguntas,
    required this.segundosPorPregunta,
    required this.respuestaLibre,
    required this.recompensaPorAciertos,
  });
}

const List<ConfigDificultadCuestionario> dificultadesCuestionario = [
  ConfigDificultadCuestionario(
    id: 'facil',
    nombre: 'Fácil',
    descripcion:
        '3 obras que leas o hayas terminado (normales o +18). Te preguntamos en qué '
        'capítulo ibas. 7 segundos por pregunta.',
    numPreguntas: 3,
    segundosPorPregunta: 7,
    respuestaLibre: false,
    recompensaPorAciertos: [0, 5, 15, 20],
  ),
  ConfigDificultadCuestionario(
    id: 'normal',
    nombre: 'Normal',
    descripcion:
        '3 obras. Te preguntamos el tipo de obra o quién es el protagonista. '
        '7 segundos por pregunta.',
    numPreguntas: 3,
    segundosPorPregunta: 7,
    respuestaLibre: false,
    recompensaPorAciertos: [0, 5, 15, 20],
  ),
  ConfigDificultadCuestionario(
    id: 'dificil',
    nombre: 'Difícil',
    descripcion:
        '5 obras distintas. Te preguntamos cualquier dato ya validado de cada una. '
        '7 segundos por pregunta.',
    numPreguntas: 5,
    segundosPorPregunta: 7,
    respuestaLibre: false,
    recompensaPorAciertos: [0, 10, 20, 30, 40, 50],
  ),
  ConfigDificultadCuestionario(
    id: 'infernal',
    nombre: 'Infernal',
    descripcion:
        '5 obras. Sin opciones: escribes tú la respuesta (incluye género y año de '
        'publicación; con al menos 40% del género das medio punto). 10 segundos por '
        'pregunta. El doble de tokens que Difícil.',
    numPreguntas: 5,
    segundosPorPregunta: 10,
    respuestaLibre: true,
    recompensaPorAciertos: [0, 20, 40, 60, 80, 100],
  ),
];

ConfigDificultadCuestionario configDificultad(String id) =>
    dificultadesCuestionario.firstWhere((d) => d.id == id);

/// Campos (además del tipo) que puede usar Difícil, en opción múltiple: ahí
/// una lista de géneros o una fecha como una opción de texto no da problema.
const List<String> _camposOpcionMultiple = [
  'genero',
  'protagonista',
  'autor',
  'estudioArte',
  'estado',
  'fechaPublicacion',
];

/// Campos que puede usar Infernal (respuesta escrita a mano). Género se
/// evalúa aparte con acierto parcial (ver [_puntajeMultivaluado]) y fecha de
/// publicación solo pregunta por el año (ver [_armarAvanzado]), para que
/// ambos sean razonables de escribir a mano.
const List<String> _camposRespuestaLibre = [
  'protagonista',
  'autor',
  'estudioArte',
  'estado',
  'genero',
  'fechaPublicacion',
];

class _CandidataObra {
  final String titulo;
  final String? tipo;
  // Solo los campos ya validados por la comunidad, campo -> valor formateado
  // para mostrar.
  final Map<String, String> campos;
  _CandidataObra({required this.titulo, required this.tipo, required this.campos});
}

class CuestionarioService {
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

  /// Guarda la fecha (cuenta como "ya hecho esta semana" sin importar la
  /// dificultad elegida, solo se puede hacer un cuestionario semanal) y
  /// entrega los tokens según el puntaje. [puntaje] puede traer medios
  /// puntos (solo pasa con la pregunta de género en Infernal): como esa
  /// escala de tokens es lineal (cada acierto vale lo mismo), medio punto
  /// da la mitad de un acierto completo; en las demás dificultades el
  /// puntaje siempre es un número entero.
  Future<int> reclamarRecompensa(String dificultad, double puntaje) async {
    final cfg = configDificultad(dificultad);
    int tokens;
    if (puntaje == puntaje.roundToDouble()) {
      final indice = puntaje.round().clamp(0, cfg.numPreguntas);
      tokens = cfg.recompensaPorAciertos[indice];
    } else {
      // Solo ocurre con medios puntos: interpola entre los dos escalones
      // vecinos (la tabla de esta dificultad ya es pareja entre escalones).
      final base = puntaje.floor().clamp(0, cfg.numPreguntas);
      final siguiente = (base + 1).clamp(0, cfg.numPreguntas);
      final paso = cfg.recompensaPorAciertos[siguiente] - cfg.recompensaPorAciertos[base];
      tokens = cfg.recompensaPorAciertos[base] + (paso * (puntaje - base)).round();
    }
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(_userDoc);
      final tokensActuales = (snap.data()?['tokens'] as num?)?.toInt() ?? 0;
      tx.set(_userDoc, {
        if (tokens > 0) 'tokens': tokensActuales + tokens,
        'cuestionarioUltimaFecha': Timestamp.now(),
      }, SetOptions(merge: true));
      return tokens;
    });
  }

  Future<List<Lectura>> _lecturasElegibles() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .get();
    // Solo lo que estés leyendo o ya hayas terminado (no pendientes ni
    // abandonadas, de esas no es realista acordarse). Una sola por título,
    // por si hay duplicados.
    final porObra = <String, Lectura>{};
    for (final d in snap.docs) {
      final l = Lectura.fromDoc(d);
      if (l.estado != 'leyendo' && l.estado != 'terminado') continue;
      porObra.putIfAbsent(normalizarTitulo(l.titulo), () => l);
    }
    final lista = porObra.values.toList()..shuffle();
    return lista;
  }

  /// Arma las preguntas de la dificultad pedida. Devuelve null si todavía no
  /// hay suficientes obras (o datos validados) para armarla: el usuario
  /// tendría que elegir otra dificultad o seguir leyendo/validando datos.
  Future<List<PreguntaCuestionario>?> armarPreguntas(String dificultad) {
    switch (dificultad) {
      case 'facil':
        return _armarFacil();
      case 'normal':
        return _armarNormal();
      case 'dificil':
        return _armarAvanzado(numObras: 5, opcionMultiple: true, campos: _camposOpcionMultiple);
      case 'infernal':
        return _armarAvanzado(numObras: 5, opcionMultiple: false, campos: _camposRespuestaLibre);
      default:
        throw ArgumentError('Dificultad desconocida: $dificultad');
    }
  }

  Future<List<PreguntaCuestionario>?> _armarFacil() async {
    final elegibles = await _lecturasElegibles();
    final conCapitulo = elegibles.where((l) => int.tryParse(l.capituloActual) != null).toList();
    if (conCapitulo.length < 3) return null;
    final elegidas = conCapitulo.take(3).toList();
    final rand = Random();
    return elegidas.map((l) {
      final correcto = int.parse(l.capituloActual);
      final opciones = <int>{correcto};
      while (opciones.length < 4) {
        final delta = rand.nextInt(7) - 3;
        final op = correcto + delta;
        if (op >= 0) opciones.add(op);
      }
      final textos = (opciones.toList()..shuffle()).map((o) => 'Cap. $o').toList();
      return PreguntaCuestionario(
        obraTitulo: l.titulo,
        enunciado: '¿En qué capítulo ibas de "${l.titulo}"?',
        respuestaCorrecta: 'Cap. $correcto',
        opciones: textos,
      );
    }).toList();
  }

  Future<List<PreguntaCuestionario>?> _armarNormal() async {
    final elegibles = await _lecturasElegibles();
    if (elegibles.length < 3) return null;
    final candidatas = await _cargarCandidatas(
      elegibles,
      camposNecesarios: const {'protagonista'},
      maxNecesarias: 3,
    );
    if (candidatas.length < 3) return null;
    final usadas = candidatas.take(3).toList();

    final poolProtagonistas = await _poolDeOtrasObras(
      'protagonista',
      excluir: usadas.map((c) => c.titulo).toSet(),
    );

    final rand = Random();
    final preguntas = <PreguntaCuestionario>[];
    for (final c in usadas) {
      final protagonista = c.campos['protagonista'];
      final puedeProtagonista = protagonista != null && poolProtagonistas.length >= 2;
      if (puedeProtagonista && rand.nextBool()) {
        preguntas.add(PreguntaCuestionario(
          obraTitulo: c.titulo,
          enunciado: '¿Quién es el protagonista de "${c.titulo}"?',
          respuestaCorrecta: protagonista,
          opciones: _armarOpciones(protagonista, poolProtagonistas),
        ));
      } else {
        final tipo = c.tipo ?? tiposLectura.first;
        preguntas.add(PreguntaCuestionario(
          obraTitulo: c.titulo,
          enunciado: '¿De qué tipo es "${c.titulo}"?',
          respuestaCorrecta: tipo,
          opciones: _armarOpciones(tipo, tiposLectura),
        ));
      }
    }
    return preguntas;
  }

  Future<List<PreguntaCuestionario>?> _armarAvanzado({
    required int numObras,
    required bool opcionMultiple,
    required List<String> campos,
  }) async {
    final elegibles = await _lecturasElegibles();
    if (elegibles.length < numObras) return null;
    final candidatas = await _cargarCandidatas(
      elegibles,
      camposNecesarios: campos.toSet(),
      maxNecesarias: numObras,
    );
    if (candidatas.length < numObras) return null;
    final usadas = candidatas.take(numObras).toList();

    final pools = <String, List<String>>{};
    if (opcionMultiple) {
      final titulosUsados = usadas.map((c) => c.titulo).toSet();
      for (final campo in [...campos, 'tipo']) {
        pools[campo] = await _poolDeOtrasObras(campo, excluir: titulosUsados);
      }
    }

    final rand = Random();
    return usadas.map((c) {
      final disponibles = ['tipo', ...campos.where((campo) => c.campos.containsKey(campo))];
      final campoElegido = disponibles[rand.nextInt(disponibles.length)];
      final valor = campoElegido == 'tipo' ? (c.tipo ?? tiposLectura.first) : c.campos[campoElegido]!;

      // En Infernal, "fecha de publicación" solo pide el año (una fecha
      // completa escrita a mano tiene demasiados formatos válidos).
      if (!opcionMultiple && campoElegido == 'fechaPublicacion') {
        final partes = valor.split('/');
        final anio = partes.length == 3 ? partes.last : valor;
        return PreguntaCuestionario(
          obraTitulo: c.titulo,
          enunciado: '¿En qué año se publicó "${c.titulo}"?',
          respuestaCorrecta: anio,
        );
      }

      return PreguntaCuestionario(
        obraTitulo: c.titulo,
        enunciado: _enunciadoPara(campoElegido, c.titulo),
        respuestaCorrecta: valor,
        opciones: opcionMultiple ? _armarOpciones(valor, pools[campoElegido] ?? []) : null,
        multivaluada: !opcionMultiple && campoElegido == 'genero',
      );
    }).toList();
  }

  List<String> _armarOpciones(String correcta, List<String> distractoresPosibles) {
    final distractores = (List<String>.from(distractoresPosibles)..remove(correcta)..shuffle())
        .take(3)
        .toList();
    return (<String>{correcta, ...distractores}.toList()..shuffle());
  }

  String _enunciadoPara(String campo, String titulo) {
    switch (campo) {
      case 'tipo':
        return '¿De qué tipo es "$titulo"?';
      case 'genero':
        return '¿Cuál es el género de "$titulo"?';
      case 'protagonista':
        return '¿Quién es el protagonista de "$titulo"?';
      case 'autor':
        return '¿Quién es el autor/creador de "$titulo"?';
      case 'estudioArte':
        return '¿Cuál es el estudio de arte de "$titulo"?';
      case 'estado':
        return '¿"$titulo" está en curso o finalizada?';
      case 'fechaPublicacion':
        return '¿Cuándo se publicó "$titulo"?';
      default:
        return '¿Cuál es el dato "$campo" de "$titulo"?';
    }
  }

  /// Carga de Firestore los datos de obra (tipo + los campos ya validados
  /// por la comunidad) para cada lectura elegible, quedándose solo con las
  /// que tienen tipo o al menos uno de [camposNecesarios]. Corta apenas
  /// junta [maxNecesarias] para no leer de más (las lecturas ya vienen
  /// mezcladas al azar).
  Future<List<_CandidataObra>> _cargarCandidatas(
    List<Lectura> elegibles, {
    required Set<String> camposNecesarios,
    required int maxNecesarias,
  }) async {
    final candidatas = <_CandidataObra>[];
    for (final l in elegibles) {
      if (candidatas.length >= maxNecesarias) break;
      final obraId = normalizarTitulo(l.titulo);
      final snap = await FirebaseFirestore.instance.collection('obras').doc(obraId).get();
      final data = snap.data();
      if (data == null) continue;
      final tipo = data['tipo'] as String?;
      final camposData = Map<String, dynamic>.from(data['campos'] ?? {});
      final validados = <String, String>{};
      for (final campo in camposNecesarios) {
        final c = camposData[campo];
        if (c is Map && c['validado'] == true) {
          final texto = formatearValorCampo(c['valor'], campo: campo);
          if (texto.isNotEmpty) validados[campo] = texto;
        }
      }
      if (tipo == null && validados.isEmpty) continue;
      candidatas.add(_CandidataObra(titulo: l.titulo, tipo: tipo, campos: validados));
    }
    return candidatas;
  }

  /// Un muestreo de otras obras del catálogo para sacar valores "falsos"
  /// (distractores) de un campo ya validado, sin usar las obras que ya
  /// forman parte de este cuestionario.
  Future<List<String>> _poolDeOtrasObras(String campo, {required Set<String> excluir}) async {
    final excluirIds = excluir.map(normalizarTitulo).toSet();
    final snap = await FirebaseFirestore.instance
        .collection('obras')
        .orderBy('tituloOriginal')
        .limit(60)
        .get();
    final valores = <String>{};
    for (final doc in snap.docs) {
      if (excluirIds.contains(doc.id)) continue;
      final data = doc.data();
      if (campo == 'tipo') {
        final tipo = data['tipo'] as String?;
        if (tipo != null) valores.add(tipo);
        continue;
      }
      final campos = Map<String, dynamic>.from(data['campos'] ?? {});
      final c = campos[campo];
      if (c is Map && c['validado'] == true) {
        final texto = formatearValorCampo(c['valor'], campo: campo);
        if (texto.isNotEmpty) valores.add(texto);
      }
    }
    return valores.toList();
  }
}