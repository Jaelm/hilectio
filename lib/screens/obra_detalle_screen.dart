import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/lectura.dart';
import '../services/obra_service.dart';
import 'add_edit_lectura_screen.dart';
import 'resumenes_screen.dart';

/// Vista de detalle de una obra en Descubrir: portada grande, datos
/// secundarios ya validados, quiénes la están leyendo (con su plataforma y
/// capítulo), un diagrama de cómo la tienen marcada (leyendo/pendiente/
/// abandonado/terminado) y un botón de "me gusta".
class ObraDetalleScreen extends StatefulWidget {
  final String titulo;
  final String tipo;
  const ObraDetalleScreen({super.key, required this.titulo, required this.tipo});

  @override
  State<ObraDetalleScreen> createState() => _ObraDetalleScreenState();
}

class _ObraDetalleScreenState extends State<ObraDetalleScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _obraData = {};
  List<LectorDeObra> _lectores = [];
  bool _meGusta = false;
  int _likes = 0;
  bool _cambiandoLike = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final obraId = idObra(widget.titulo, widget.tipo);
      final obraSnap =
          await FirebaseFirestore.instance.collection('obras').doc(obraId).get();
      final lectores = await ObraService().obtenerLectoresDeObra(widget.titulo, widget.tipo);
      final meGusta = await ObraService().yaLeDiLike(widget.titulo, widget.tipo);
      if (!mounted) return;
      final data = obraSnap.data() ?? {};
      setState(() {
        _obraData = data;
        _lectores = lectores;
        _likes = (data['likes'] as num?)?.toInt() ?? 0;
        _meGusta = meGusta;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  Future<void> _alternarLike() async {
    setState(() => _cambiandoLike = true);
    try {
      final quedoDado = await ObraService().alternarLike(widget.titulo, widget.tipo);
      if (!mounted) return;
      setState(() {
        _meGusta = quedoDado;
        _likes += quedoDado ? 1 : -1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo registrar el "me gusta": $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cambiandoLike = false);
    }
  }

  /// Deja agregar esta obra a tu biblioteca directamente desde Descubrir,
  /// sin tener que escribir el título ni los datos secundarios de nuevo (ya
  /// se precargan desde el catálogo). Primero revisa si ya la tienes
  /// registrada para no crear una lectura duplicada.
  Future<void> _agregarABiblioteca(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final titulo = (_obraData['tituloOriginal'] as String?) ?? widget.titulo;
    final tipo = (_obraData['tipo'] as String?) ?? widget.tipo;

    final propias = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .get();
    QueryDocumentSnapshot<Map<String, dynamic>>? existente;
    for (final d in propias.docs) {
      final dData = d.data();
      final t = (dData['titulo'] as String? ?? '').trim();
      final tTipo = dData['tipo'] as String?;
      if (t.isNotEmpty && idObra(t, tTipo) == idObra(titulo, tipo)) {
        existente = d;
        break;
      }
    }

    if (existente != null) {
      if (!context.mounted) return;
      final editar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ya la tienes registrada'),
          content: const Text(
            'Esta obra ya está en tu biblioteca. ¿Quieres editar tu progreso en vez de agregarla de nuevo?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Editar')),
          ],
        ),
      );
      if (editar == true && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddEditLecturaScreen(lectura: Lectura.fromDoc(existente!))),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final estado = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('¿En qué etiqueta la quieres añadir?', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...estadosLectura.entries.map(
              (e) => ListTile(title: Text(e.value), onTap: () => Navigator.pop(context, e.key)),
            ),
          ],
        ),
      ),
    );
    if (estado == null || !context.mounted) return;

    // Entre los lectores actuales, agrupa por plataforma y se queda, por
    // cada una, con el del capítulo más bajo (el "menos adelantado"): así
    // quien se une ahora parte de un link real donde alguien va más atrás,
    // en vez de saltar directo al capítulo más reciente de la comunidad.
    final porPlataforma = <String, LectorDeObra>{};
    for (final lector in _lectores) {
      if (lector.plataforma.isEmpty || lector.link.isEmpty) continue;
      final capitulo = int.tryParse(lector.capituloActual);
      final guardado = porPlataforma[lector.plataforma];
      final capituloGuardado = guardado == null ? null : int.tryParse(guardado.capituloActual);
      final esMenor = guardado == null ||
          (capitulo != null && (capituloGuardado == null || capitulo < capituloGuardado));
      if (esMenor) porPlataforma[lector.plataforma] = lector;
    }

    LectorDeObra? elegido;
    if (porPlataforma.length == 1) {
      elegido = porPlataforma.values.first;
    } else if (porPlataforma.length > 1) {
      if (!context.mounted) return;
      final plataformaElegida = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '¿En qué plataforma la quieres leer?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ...porPlataforma.entries.map(
                (e) => ListTile(
                  title: Text(e.key),
                  subtitle: Text('Alguien va por el capítulo ${e.value.capituloActual}'),
                  onTap: () => Navigator.pop(context, e.key),
                ),
              ),
            ],
          ),
        ),
      );
      if (plataformaElegida == null || !context.mounted) return;
      elegido = porPlataforma[plataformaElegida];
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditLecturaScreen(
          tituloInicial: titulo,
          tipoInicial: tipo,
          estadoInicial: estado,
          plataformaInicial: elegido?.plataforma,
          linkInicial: elegido?.link,
          capituloInicial: elegido?.capituloActual,
        ),
      ),
    );
  }

  /// Imagen genérica de portada (una foto de animal, sin relación con la
  /// obra) asignada según el título. Si por algo el asset no carga, cae al
  /// ícono de respaldo en vez de romper la pantalla.
  Widget _portadaObra(String titulo) => Image.asset(
        rutaPortadaGenerica(titulo),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderPortada(),
      );

  Widget _placeholderPortada() => Container(
        color: Theme.of(context).colorScheme.primaryContainer,
        alignment: Alignment.center,
        child: Icon(Icons.menu_book_outlined,
            color: Theme.of(context).colorScheme.onPrimaryContainer, size: 56),
      );

  Widget _seccion(String titulo, Widget contenido) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            contenido,
          ],
        ),
      );

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'leyendo':
        return Colors.deepOrange;
      case 'pendiente':
        return Colors.amber.shade700;
      case 'abandonado':
        return Colors.blueGrey;
      case 'terminado':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titulo = (_obraData['tituloOriginal'] as String?) ?? widget.titulo;
    final campos = Map<String, dynamic>.from(_obraData['campos'] ?? {});
    final capituloMaximo = (_obraData['capituloMaximo'] as num?)?.toInt();

    // Solo se muestran los campos secundarios que ya están validados; los
    // que aún están en propuestas pendientes no aparecen aquí. La etiqueta
    // es la genérica (sin "del manhwa/manga/...") porque aquí ya se sabe de
    // qué obra se trata; repetirlo en cada fila solo hacía más largo y
    // difícil de leer cada línea.
    String? valorValidado(String campo) {
      final c = campos[campo];
      if (c is! Map || c['validado'] != true) return null;
      final texto = formatearValorCampo(c['valor'], campo: campo);
      return texto.isEmpty ? null : texto;
    }

    final datosSecundarios = <MapEntry<String, String>>[
      for (final campo in camposObra.keys)
        if (valorValidado(campo) != null) MapEntry(camposObra[campo]!, valorValidado(campo)!),
    ];

    final conteosPorEstado = <String, int>{for (final k in estadosLectura.keys) k: 0};
    final conteosPorPlataforma = <String, int>{};
    for (final l in _lectores) {
      conteosPorEstado[l.estado] = (conteosPorEstado[l.estado] ?? 0) + 1;
      final plataforma = l.plataforma.trim();
      if (plataforma.isNotEmpty) {
        conteosPorPlataforma[plataforma] = (conteosPorPlataforma[plataforma] ?? 0) + 1;
      }
    }
    final plataformasOrdenadas = conteosPorPlataforma.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final haySecciones = conteosPorEstado.values.any((v) => v > 0);

    return Scaffold(
      appBar: AppBar(title: Text(titulo, overflow: TextOverflow.ellipsis)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo cargar: $_error', textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 190,
                            height: 265,
                            child: _portadaObra(titulo),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        titulo,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (capituloMaximo != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Capítulo más avanzado: $capituloMaximo',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Center(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _cambiandoLike ? null : _alternarLike,
                              icon: Icon(
                                _meGusta ? Icons.favorite : Icons.favorite_border,
                                color: _meGusta ? Colors.red : null,
                              ),
                              label: Text(_likes == 1 ? '1 me gusta' : '$_likes me gusta'),
                            ),
                            FilledButton.icon(
                              onPressed: () => _agregarABiblioteca(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Añadir a mi biblioteca'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (datosSecundarios.isNotEmpty)
                        _seccion(
                          'Datos de la obra',
                          Column(
                            children: datosSecundarios
                                .map((e) => Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.key,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(e.value, style: const TextStyle(fontSize: 15)),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      if (haySecciones)
                        _seccion(
                          'Cómo la tienen los lectores',
                          SizedBox(
                            height: 190,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 32,
                                sections: [
                                  for (final e in conteosPorEstado.entries)
                                    if (e.value > 0)
                                      PieChartSectionData(
                                        value: e.value.toDouble(),
                                        title: '${estadosLectura[e.key]}\n${e.value}',
                                        titleStyle: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        color: _colorEstado(e.key),
                                        radius: 68,
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_lectores.isNotEmpty) ...[
                        _seccion(
                          'Lectores',
                          Row(
                            children: [
                              Icon(Icons.groups_outlined, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 10),
                              Text(
                                _lectores.length == 1
                                    ? '1 persona la está leyendo'
                                    : '${_lectores.length} personas la están leyendo',
                                style: const TextStyle(fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                        if (plataformasOrdenadas.isNotEmpty)
                          _seccion(
                            'Plataformas usadas',
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: plataformasOrdenadas
                                  .map((e) => Chip(
                                        avatar: const Icon(Icons.public, size: 16),
                                        label: Text(e.value > 1 ? '${e.key} · ${e.value}' : e.key),
                                      ))
                                  .toList(),
                            ),
                          ),
                      ] else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Text(
                            'Todavía nadie más tiene esta obra registrada.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResumenesScreen(tituloObra: titulo, tipoObra: widget.tipo),
                            ),
                          ),
                          icon: const Icon(Icons.forum_outlined),
                          label: const Text('Ver resúmenes de la comunidad'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}