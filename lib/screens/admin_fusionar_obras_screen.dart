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
  List<String> _titulos = [];
  String _viejo = '';
  String _nuevo = '';
  bool _fusionando = false;

  @override
  void initState() {
    super.initState();
    _cargarTitulos();
  }

  Future<void> _cargarTitulos() async {
    final snap = await FirebaseFirestore.instance.collection('obras').get();
    if (!mounted) return;
    setState(() {
      _titulos = snap.docs
          .map((d) => d.data()['tituloOriginal'] as String? ?? d.id)
          .toList()
        ..sort();
      _cargandoTitulos = false;
    });
  }

  Iterable<String> _opciones(TextEditingValue valor) {
    if (valor.text.isEmpty) return const Iterable<String>.empty();
    final texto = valor.text.toLowerCase();
    return _titulos.where((t) => t.toLowerCase().contains(texto));
  }

  Future<void> _fusionar() async {
    final viejo = _viejo.trim();
    final nuevo = _nuevo.trim();
    if (viejo.isEmpty || nuevo.isEmpty) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Fusionar obras?'),
        content: Text(
          'Todos los resúmenes, votos y propuestas de "$viejo" se van a mover '
          'a "$nuevo", y se corrige el título guardado en la biblioteca de '
          'cada usuario que tenga "$viejo". Esto no se puede deshacer.',
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
      await ObraService().fusionarObras(tituloViejo: viejo, tituloNuevo: nuevo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Obras fusionadas correctamente')),
        );
        setState(() {
          _viejo = '';
          _nuevo = '';
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
          onChanged: onChanged,
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
                onChanged: (v) => _viejo = v,
              ),
              const SizedBox(height: 14),
              _campoConSugerencias(
                etiqueta: 'Título correcto (al que se migra todo)',
                onChanged: (v) => _nuevo = v,
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