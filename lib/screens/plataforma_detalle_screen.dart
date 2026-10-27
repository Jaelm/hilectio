import 'package:flutter/material.dart';
import '../services/plataformas_service.dart';
import 'resumenes_screen.dart';

/// Lista de obras registradas en una plataforma (sin mostrar qué usuario
/// registró cada una). Tocar una obra lleva a sus resúmenes, igual que en
/// Descubrir → Obras.
class PlataformaDetalleScreen extends StatefulWidget {
  final String clave;
  final String etiqueta;
  const PlataformaDetalleScreen({super.key, required this.clave, required this.etiqueta});

  @override
  State<PlataformaDetalleScreen> createState() => _PlataformaDetalleScreenState();
}

class _PlataformaDetalleScreenState extends State<PlataformaDetalleScreen> {
  bool _cargando = true;
  String? _error;
  List<LecturaDePlataforma> _lecturas = [];

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
      final lista = await PlataformasService().obtenerLecturasDePlataforma(widget.clave);
      if (!mounted) return;
      setState(() {
        _lecturas = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Lecturas en ${widget.etiqueta}')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SelectableText(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : _lecturas.isEmpty
                  ? const Center(child: Text('No hay obras registradas en esta plataforma.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _lecturas.length,
                        itemBuilder: (context, i) {
                          final l = _lecturas[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.menu_book_outlined),
                              title: Text(l.titulo),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResumenesScreen(tituloObra: l.titulo, tipoObra: l.tipo),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}