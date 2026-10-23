import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/plataformas_service.dart';
import 'plataforma_detalle_screen.dart';

const String _correoAdmin = 'jhormanskic98@gmail.com';

/// Lista del ranking de plataformas (cuántos usuarios/lecturas tiene cada
/// una). La usan tanto la pantalla de admin en Perfil como la pestaña
/// "Plataformas" de Descubrir, que cualquier usuario puede ver. Solo el
/// admin ve el botón para cambiar el ícono de cada plataforma.
class RankingPlataformasView extends StatefulWidget {
  const RankingPlataformasView({super.key});

  @override
  State<RankingPlataformasView> createState() => _RankingPlataformasViewState();
}

class _RankingPlataformasViewState extends State<RankingPlataformasView> {
  bool _cargando = true;
  String? _error;
  List<EstadisticaPlataforma> _stats = [];

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
      final lista = await PlataformasService().calcularRanking();
      if (!mounted) return;
      setState(() {
        _stats = lista;
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

  Future<void> _editarIcono(EstadisticaPlataforma s) async {
    final ctrl = TextEditingController(text: s.imagenUrl ?? '');
    final nuevoUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ícono de "${s.etiqueta}"'),
        content: TextField(
          controller: ctrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Link de la imagen',
            helperText:
                'Link de "Compartir" de Drive (archivo en "Cualquiera con el '
                'link puede ver") o el link directo de otro sitio.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nuevoUrl == null || nuevoUrl.isEmpty) return;
    try {
      await PlataformasService().actualizarIconoPlataforma(
        clave: s.clave,
        etiqueta: s.etiqueta,
        urlImagen: nuevoUrl,
      );
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = FirebaseAuth.instance.currentUser?.email == _correoAdmin;

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
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
      );
    }
    if (_stats.isEmpty) {
      return const Center(child: Text('Todavía no hay lecturas con plataforma registrada.'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _stats.length,
        itemBuilder: (context, i) {
          final s = _stats[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: ClipOval(
                  child: (s.imagenUrl != null && s.imagenUrl!.isNotEmpty)
                      ? Image.network(
                          s.imagenUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.public,
                              color: Theme.of(context).colorScheme.onPrimaryContainer),
                        )
                      : Icon(Icons.public, color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
              ),
              title: Text(s.etiqueta),
              subtitle: Text('${s.usuarios} usuario(s) · ${s.lecturas} lectura(s) registrada(s)'),
              trailing: esAdmin
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.image_outlined),
                          tooltip: 'Cambiar ícono',
                          onPressed: () => _editarIcono(s),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlataformaDetalleScreen(clave: s.clave, etiqueta: s.etiqueta),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}