import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/obra_service.dart';

/// Pantalla de admin para corregir una obra que quedó duplicada con dos
/// títulos distintos (ej. "Stream del Arquero Genio" vs "Streaming del
/// Arquero Genio"): fusiona todo bajo el título correcto sin perder
/// resúmenes, votos ni propuestas. Ambos campos sugieren, mientras escribes,
/// los títulos que ya existen en el catálogo (para no tener que escribirlos
/// perfectos a mano y evitar crear un tercer título por error de tipeo).
class AdminFusionarObrasScreen extends StatefulWidget {
  const AdminFusionarObrasScreen({super.key});

  @override
  State<AdminFusionarObrasScreen> createState() => _AdminFusionarObrasScreenState();
}

class _AdminFusionarObrasScreenState extends State<AdminFusionarObrasScreen> {
  bool _cargandoTitulos = true;
  // Cada opción mostrada es "Título (Tipo)"; este mapa guarda, para cada
  // texto mostrado, el título y tipo reales que hay que pasarle a
  // fusionarObras (necesarios desde que el ID de obra es título+tipo).
  List<String> _opcionesTexto = [];
  final Map<String, ({String titulo, String tipo})> _porTexto = {};
  String? _viejoTexto;
  String? _nuevoTexto;
  bool _fusionando = false;

  @override
  void initState() {
    super.initState();
    _cargarTitulos();
  }

  Future<void> _cargarTitulos() async {
    final snap = await FirebaseFirestore.instance.collection('obras').get();
    if (!mounted) return;
    _porTexto.clear();
    for (final d in snap.docs) {
      final data = d.data();
      final titulo = data['tituloOriginal'] as String? ?? d.id;
      final tipo = data['tipo'] as String? ?? 'otro';
      final texto = '$titulo ($tipo)';
      _porTexto[texto] = (titulo: titulo, tipo: tipo);
    }
    setState(() {
      _opcionesTexto = _porTexto.keys.toList()..sort();
      _cargandoTitulos = false;
    });
  }

  Iterable<String> _opciones(TextEditingValue valor) {
    if (valor.text.isEmpty) return const Iterable<String>.empty();
    final texto = valor.text.toLowerCase();
    return _opcionesTexto.where((t) => t.toLowerCase().contains(texto));
  }

  Future<void> _fusionar() async {
    final viejo = _viejoTexto != null ? _porTexto[_viejoTexto] : null;
    final nuevo = _nuevoTexto != null ? _porTexto[_nuevoTexto] : null;
    if (viejo == null || nuevo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Elige ambos títulos de la lista de sugerencias.'),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Fusionar obras?'),
        content: Text(
          'Todos los resúmenes, votos y propuestas de "$_viejoTexto" se van a '
          'mover a "$_nuevoTexto", y se corrige el título guardado en la '
          'biblioteca de cada usuario que tenga esa obra. Esto no se puede '
          'deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Fusionar')),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _fusionando = true);
    try {
      await ObraService().fusionarObras(
        tituloViejo: viejo.titulo,
        tipoViejo: viejo.tipo,
        tituloNuevo: nuevo.titulo,
        tipoNuevo: nuevo.tipo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Obras fusionadas correctamente')),
        );
        setState(() {
          _viejoTexto = null;
          _nuevoTexto = null;
        });
        _cargarTitulos();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _fusionando = false);
    }
  }

  Widget _campoConSugerencias({
    required String etiqueta,
    required ValueChanged<String> onChanged,
  }) {
    return Autocomplete<String>(
      optionsBuilder: _opciones,
      onSelected: onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: etiqueta),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final opcion = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(opcion),
                    onTap: () => onSelected(opcion),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fusionar obras duplicadas')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Úsalo cuando la misma obra quedó registrada con dos títulos '
              'distintos. Se conserva todo -resúmenes, votos, propuestas- '
              'bajo el título correcto, y se corrige en la biblioteca de '
              'cada usuario. Empieza a escribir y elige de la lista.',
            ),
            const SizedBox(height: 20),
            if (_cargandoTitulos)
              const Center(child: CircularProgressIndicator())
            else ...[
              _campoConSugerencias(
                etiqueta: 'Título a eliminar (el que está mal escrito)',
                onChanged: (v) => setState(() => _viejoTexto = v),
              ),
              const SizedBox(height: 14),
              _campoConSugerencias(
                etiqueta: 'Título correcto (al que se migra todo)',
                onChanged: (v) => setState(() => _nuevoTexto = v),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _fusionando ? null : _fusionar,
                child: _fusionando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Fusionar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}