import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'obra_service.dart' show idObra;

/// Catálogo de los 20 títulos/logros ocultos de Hilectio. La clave es el id
/// interno (se guarda en `logrosDesbloqueados` del usuario); el valor es el
/// título exacto que se añade a `titulosObtenidos` al desbloquearlo (y que
/// luego se puede equipar desde Perfil, igual que los títulos de cofres).
const Map<String, String> logrosOcultos = {
  'sobreviviente_hiatus': 'Sobreviviente del Hiatus',
  'regresor_clase_s': 'Regresor de Clase S',
  'cazador_madrugadas': 'Cazador de Madrugadas',
  'modo_supervivencia': 'Modo Supervivencia',
  'rey_farmeo': 'Rey del Farmeo',
  'drop_suerte': 'Drop de la Suerte',
  'navegante_mil_capitulos': 'Navegante de los Mil Capítulos',
  'atrapado_niebla': 'Atrapado en la Niebla',
  'modo_permadeath': 'Modo Permadeath',
  'despertar_cazador': 'Despertar del Cazador',
  'transmision_rango_s': 'Transmisión de Rango S',
  'reencarnado_game_over': 'Reencarnado tras el Game Over',
  'villana_otome': 'Villana del Otome',
  'acumulador_ki': 'Acumulador de Ki',
  'sindrome_octavo_grado': 'Síndrome del Octavo Grado (Chūnibyō)',
  'rey_demonio_parcial': 'El Rey Demonio a Tiempo Parcial',
  'cultivador_mil_anios': 'Cultivador de Mil Años',
  'coleccionista_drops': 'Coleccionista de Drops',
  'senor_bestiario': 'Señor del Bestiario',
  'gremio_sombras': 'El Gremio de las Sombras',
};

/// Descripciones de cada logro, por si luego se hace una pantalla para
/// mostrar el progreso (no afecta la lógica de desbloqueo).
const Map<String, String> logrosDescripcion = {
  'sobreviviente_hiatus': 'Mantén una obra en "Leyendo" sin actualizarla por más de 6 meses.',
  'regresor_clase_s': 'Termina una obra y vuelve a empezarla desde el capítulo 1.',
  'cazador_madrugadas': 'Interactúa con la app entre las 2:00 a.m. y las 4:00 a.m.',
  'modo_supervivencia': 'Avanza 50 capítulos o más de una misma obra en un solo día.',
  'rey_farmeo': 'Saca 5 ítems duplicados seguidos al abrir cofres.',
  'drop_suerte': 'Saca un ítem legendario en el primer cofre que abras en tu cuenta.',
  'navegante_mil_capitulos': 'Supera los 1000 capítulos leídos en una sola obra.',
  'atrapado_niebla': 'Acumula más de 10 obras de terror psicológico, thriller o supervivencia.',
  'modo_permadeath': 'Termina una obra de más de 50 capítulos con una racha activa.',
  'despertar_cazador': 'Alcanza tu primera racha de 30 días consecutivos.',
  'transmision_rango_s': 'Comparte un estado de lectura o un resumen 10 veces.',
  'reencarnado_game_over': 'Vuelve a la app tras más de un mes de inactividad.',
  'villana_otome': 'Completa más de 15 lecturas de romance/reencarnación.',
  'acumulador_ki': 'Ahorra 10,000 tokens sin haber abierto nunca un cofre.',
  'sindrome_octavo_grado': 'Cambia tu título o tu foto más de 5 veces en un mismo día.',
  'rey_demonio_parcial': 'Gana tokens solo en sábados y domingos durante un mes.',
  'cultivador_mil_anios': 'Mantén la racha diaria activa durante 365 días seguidos.',
  'coleccionista_drops': 'Abre 50 cofres comunes.',
  'senor_bestiario': 'Deja resúmenes en más de 20 capítulos distintos.',
  'gremio_sombras': 'Acumula 1000 capítulos leídos sin equiparte marco ni título.',
};

const List<String> _generosNiebla = [
  'terror', 'psicologico', 'psicológico', 'thriller', 'supervivencia', 'survival',
];
const List<String> _generosOtome = [
  'romance', 'reencarnacion', 'reencarnación', 'otome',
];

/// Muestra en pantalla (como snackbars) los títulos secretos que se acaban
/// de desbloquear. Llamar justo después de cualquier método de
/// [LogrosService] que pueda devolver una lista no vacía.
void mostrarLogrosDesbloqueados(BuildContext context, List<String> titulos) {
  for (final titulo in titulos) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.deepPurple,
        content: Text('🏆 Logro secreto desbloqueado: "$titulo" (ya puedes equiparlo en Perfil)'),
      ),
    );
  }
}

class LogrosService {
  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('usuarios').doc(uid);

  String _hoy() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Marca como desbloqueados los ids que el usuario todavía no tenía y les
  /// añade el título correspondiente a su inventario (`titulosObtenidos`).
  /// Devuelve los títulos (el texto, no el id) recién desbloqueados.
  Future<List<String>> _desbloquear(String uid, Set<String> idsCumplidos) async {
    if (idsCumplidos.isEmpty) return [];
    final ref = _userDoc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final yaDesbloqueados = Set<String>.from(data['logrosDesbloqueados'] ?? []);
    final nuevos = idsCumplidos.difference(yaDesbloqueados);
    if (nuevos.isEmpty) return [];

    final nuevosTitulos = nuevos.map((id) => logrosOcultos[id]!).toList();
    await ref.set({
      'logrosDesbloqueados': FieldValue.arrayUnion(nuevos.toList()),
      'titulosObtenidos': FieldValue.arrayUnion(nuevosTitulos),
    }, SetOptions(merge: true));
    return nuevosTitulos;
  }

  /// Llamar en cualquier interacción "significativa" con la app (guardar una
  /// lectura, abrir un cofre, escribir un resumen, entrar a Perfil...).
  /// Revisa los logros que dependen de LA HORA en la que ocurre la
  /// interacción y de cuánto tiempo pasó desde la última vez que el usuario
  /// hizo algo.
  Future<List<String>> registrarInteraccion(String uid) async {
    final ahora = DateTime.now();
    final ref = _userDoc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final cumplidos = <String>{};

    if (ahora.hour >= 2 && ahora.hour < 4) {
      cumplidos.add('cazador_madrugadas');
    }

    final Timestamp? ultimaTs = data['ultimaActividad'];
    if (ultimaTs != null && ahora.difference(ultimaTs.toDate()).inDays > 30) {
      cumplidos.add('reencarnado_game_over');
    }

    await ref.set({'ultimaActividad': Timestamp.fromDate(ahora)}, SetOptions(merge: true));
    return _desbloquear(uid, cumplidos);
  }

  /// Llamar justo después de que [CofresService.abrirCofre] resuelva el
  /// cofre (con el resultado ya decidido).
  Future<List<String>> alAbrirCofre(
    String uid, {
    required bool esComun,
    required String rarezaResultado,
    required bool fueDuplicado,
  }) async {
    final ref = _userDoc(uid);
    final cumplidos = await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final stats = Map<String, dynamic>.from(data['stats'] ?? {});

      final totalAbiertos = (stats['cofresAbiertos'] as num?)?.toInt() ?? 0;
      final comunesAbiertos = (stats['cofresComunAbiertos'] as num?)?.toInt() ?? 0;
      final rachaDuplicados = (stats['cofresRachaDuplicados'] as num?)?.toInt() ?? 0;
      final primerRareza = stats['primerCofreRareza'] as String?;
      final esElPrimero = primerRareza == null;

      final nuevoComunes = comunesAbiertos + (esComun ? 1 : 0);
      final nuevaRachaDuplicados = fueDuplicado ? rachaDuplicados + 1 : 0;
      final c = <String>{};

      if (esElPrimero && esComun && rarezaResultado == 'legendario') {
        c.add('drop_suerte');
      }
      if (nuevoComunes >= 50) c.add('coleccionista_drops');
      if (nuevaRachaDuplicados >= 5) c.add('rey_farmeo');

      tx.set(ref, {
        'stats': {
          'cofresAbiertos': totalAbiertos + 1,
          'cofresComunAbiertos': nuevoComunes,
          'cofresRachaDuplicados': nuevaRachaDuplicados,
          if (esElPrimero) 'primerCofreRareza': rarezaResultado,
        },
      }, SetOptions(merge: true));

      return c;
    });
    return _desbloquear(uid, cumplidos);
  }

  /// Llamar justo después de crear un resumen, con una clave única de
  /// "obra+capítulo" (ej. `"$obraId|$capituloNormalizado"`).
  Future<List<String>> alCrearResumen(String uid, String claveCapitulo) async {
    final ref = _userDoc(uid);
    final cumplidos = await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final existentes = Set<String>.from(data['stats']?['resumenesCapitulos'] ?? []);
      if (existentes.contains(claveCapitulo)) return <String>{};

      tx.set(ref, {
        'stats': {'resumenesCapitulos': FieldValue.arrayUnion([claveCapitulo])},
      }, SetOptions(merge: true));

      return existentes.length + 1 >= 20 ? {'senor_bestiario'} : <String>{};
    });
    return _desbloquear(uid, cumplidos);
  }

  /// Llamar cuando el usuario cambia su foto o su título equipado en Perfil.
  Future<List<String>> alCambiarPerfil(String uid) async {
    final ref = _userDoc(uid);
    final hoy = _hoy();
    final cumplidos = await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final fechaGuardada = data['stats']?['cambiosPerfilFecha'] as String?;
      final cantidadGuardada = (data['stats']?['cambiosPerfilCantidad'] as num?)?.toInt() ?? 0;
      final nuevaCantidad = fechaGuardada == hoy ? cantidadGuardada + 1 : 1;

      tx.set(ref, {
        'stats': {'cambiosPerfilFecha': hoy, 'cambiosPerfilCantidad': nuevaCantidad},
      }, SetOptions(merge: true));

      return nuevaCantidad > 5 ? {'sindrome_octavo_grado'} : <String>{};
    });
    return _desbloquear(uid, cumplidos);
  }

  /// Llamar cada vez que el usuario comparte un resumen o un estado de
  /// lectura fuera de la app.
  Future<List<String>> registrarCompartido(String uid) async {
    final ref = _userDoc(uid);
    final cumplidos = await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data() ?? {};
      final actuales = (data['stats']?['compartidos'] as num?)?.toInt() ?? 0;
      final nuevos = actuales + 1;
      tx.set(ref, {'stats': {'compartidos': nuevos}}, SetOptions(merge: true));
      return nuevos >= 10 ? {'transmision_rango_s'} : <String>{};
    });
    return _desbloquear(uid, cumplidos);
  }

  /// Llamar cada vez que el usuario gana tokens por su propia actividad
  /// (racha diaria, votos a resúmenes, datos de obra aprobados...). Alimenta
  /// el logro de "ganar tokens solo en fin de semana".
  Future<void> registrarGananciaTokens(String uid) async {
    final ahora = DateTime.now();
    final esFinde = ahora.weekday == DateTime.saturday || ahora.weekday == DateTime.sunday;
    final ref = _userDoc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final stats = Map<String, dynamic>.from(data['stats'] ?? {});

    final actualizacion = <String, dynamic>{};
    if (stats['primeraGananciaRegistrada'] == null) {
      actualizacion['primeraGananciaRegistrada'] = Timestamp.fromDate(ahora);
    }
    if (!esFinde) {
      actualizacion['ultimaGananciaEntreSemana'] = Timestamp.fromDate(ahora);
    }
    if (actualizacion.isNotEmpty) {
      await ref.set({'stats': actualizacion}, SetOptions(merge: true));
    }
  }

  /// Llamar al guardar una lectura (nueva o editada). [anterior] es el
  /// documento previo (null si es una lectura nueva). Devuelve:
  /// - "extra": campos que hay que mezclar en el doc de la lectura (control
  ///   interno para "capítulos avanzados hoy" y "venía de estar terminada").
  /// - "titulos": títulos secretos recién desbloqueados.
  Future<Map<String, dynamic>> alGuardarLectura({
    required String uid,
    required Map<String, dynamic>? anterior,
    required String nuevoCapituloTexto,
    required String nuevoEstado,
  }) async {
    final hoy = _hoy();
    final nuevoCapitulo = int.tryParse(nuevoCapituloTexto) ?? 0;
    final cumplidos = <String>{};
    final extra = <String, dynamic>{};

    final capAnterior = int.tryParse((anterior?['capituloActual'] ?? '0').toString()) ?? 0;
    final fechaInicioDia = anterior?['capInicioDiaFecha'] as String?;
    final capInicioDiaGuardado = (anterior?['capInicioDiaValor'] as num?)?.toInt();

    final capInicioDiaVigente =
        (fechaInicioDia == hoy && capInicioDiaGuardado != null) ? capInicioDiaGuardado : capAnterior;
    extra['capInicioDiaFecha'] = hoy;
    extra['capInicioDiaValor'] = capInicioDiaVigente;
    if (nuevoCapitulo - capInicioDiaVigente >= 50) {
      cumplidos.add('modo_supervivencia');
    }

    final estadoAnterior = anterior?['estado'] as String?;
    final yaHabiaTerminado = anterior?['fueTerminada'] == true || estadoAnterior == 'terminado';

    if (estadoAnterior == 'terminado') {
      extra['fueTerminada'] = true;
    }
    if (yaHabiaTerminado && nuevoEstado == 'leyendo' && nuevoCapitulo <= 1) {
      cumplidos.add('regresor_clase_s');
      extra['fueTerminada'] = false;
    }

    if (nuevoCapitulo >= 1000) cumplidos.add('navegante_mil_capitulos');

    final titulos = await _desbloquear(uid, cumplidos);
    return {'extra': extra, 'titulos': titulos};
  }

  /// Barrido completo sobre la biblioteca del propio usuario (nunca usa
  /// collectionGroup, así que no necesita índices nuevos). Revisa los logros
  /// que dependen de TODA la biblioteca o del estado general de la cuenta.
  /// Llamar al cargar Perfil y después de guardar una lectura.
  Future<List<String>> evaluarCompleto(String uid) async {
    final userRef = _userDoc(uid);
    final userSnap = await userRef.get();
    final u = userSnap.data() ?? {};
    final cumplidos = <String>{};

    final tokens = (u['tokens'] as num?)?.toInt() ?? 0;
    final cofresAbiertos = (u['stats']?['cofresAbiertos'] as num?)?.toInt() ?? 0;
    final rachaDiasTotal = (u['rachaDiasTotal'] as num?)?.toInt() ?? 0;
    final fotoSeleccionada = u['fotoSeleccionada'] as String?;
    final tituloSeleccionado = u['tituloSeleccionado'] as String?;

    if (tokens >= 10000 && cofresAbiertos == 0) cumplidos.add('acumulador_ki');
    if (rachaDiasTotal >= 30) cumplidos.add('despertar_cazador');
    if (rachaDiasTotal >= 365) cumplidos.add('cultivador_mil_anios');

    final primeraGananciaTs = u['stats']?['primeraGananciaRegistrada'] as Timestamp?;
    final ultimaEntreSemanaTs = u['stats']?['ultimaGananciaEntreSemana'] as Timestamp?;
    if (primeraGananciaTs != null) {
      final ahora = DateTime.now();
      final diasDesdePrimera = ahora.difference(primeraGananciaTs.toDate()).inDays;
      final diasSinEntreSemana = ultimaEntreSemanaTs == null
          ? diasDesdePrimera
          : ahora.difference(ultimaEntreSemanaTs.toDate()).inDays;
      if (diasDesdePrimera >= 30 && diasSinEntreSemana >= 30) {
        cumplidos.add('rey_demonio_parcial');
      }
    }

    final lecturasSnap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .get();

    int totalCapitulos = 0;
    int terrorThrillerCount = 0;
    int romanceCount = 0;
    final ahora = DateTime.now();
    final generosCache = <String, Set<String>>{};

    for (final doc in lecturasSnap.docs) {
      final d = doc.data();
      final capitulo = int.tryParse((d['capituloActual'] ?? '0').toString()) ?? 0;
      totalCapitulos += capitulo;

      if (capitulo >= 1000) cumplidos.add('navegante_mil_capitulos');

      final estado = (d['estado'] ?? '').toString();
      if (estado == 'leyendo') {
        final actualizadoEn = (d['actualizadoEn'] as Timestamp?)?.toDate();
        if (actualizadoEn != null && ahora.difference(actualizadoEn).inDays > 180) {
          cumplidos.add('sobreviviente_hiatus');
        }
      }
      if (estado == 'terminado' && capitulo > 50 && rachaDiasTotal >= 7) {
        cumplidos.add('modo_permadeath');
      }

      final titulo = (d['titulo'] ?? '').toString();
      if (titulo.isNotEmpty) {
        final tipoLectura = (d['tipo'] ?? 'otro').toString();
        final obraId = idObra(titulo, tipoLectura);
        Set<String> generos;
        if (generosCache.containsKey(obraId)) {
          generos = generosCache[obraId]!;
        } else {
          final obraSnap = await FirebaseFirestore.instance.collection('obras').doc(obraId).get();
          final campoGenero = obraSnap.data()?['campos']?['genero']?['valor'];
          generos = campoGenero is List
              ? campoGenero.map((e) => e.toString().toLowerCase()).toSet()
              : <String>{};
          generosCache[obraId] = generos;
        }

        if (generos.any((g) => _generosNiebla.any((k) => g.contains(k)))) {
          terrorThrillerCount++;
        }
        if (estado == 'terminado' && generos.any((g) => _generosOtome.any((k) => g.contains(k)))) {
          romanceCount++;
        }
      }
    }

    if (terrorThrillerCount > 10) cumplidos.add('atrapado_niebla');
    if (romanceCount > 15) cumplidos.add('villana_otome');
    if (totalCapitulos >= 1000 &&
        (fotoSeleccionada == null || fotoSeleccionada.isEmpty) &&
        (tituloSeleccionado == null || tituloSeleccionado.isEmpty)) {
      cumplidos.add('gremio_sombras');
    }

    return _desbloquear(uid, cumplidos);
  }
}