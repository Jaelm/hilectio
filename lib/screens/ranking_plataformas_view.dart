import 'package:flutter/material.dart';
import '../services/plataformas_service.dart';
import 'plataforma_detalle_screen.dart';

/// Lista del ranking de plataformas (cuántos usuarios/lecturas tiene cada
/// una). La usan tanto la pantalla de admin en Perfil como la pestaña
/// "Plataformas" de Descubrir, que cualquier usuario puede ver. El ícono es
/// siempre genérico: no se admiten logos de terceros subidos por el admin,
/// para no usar marcas registradas de las plataformas sin permiso.
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

  @override
  Widget build(BuildContext context) {
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
                child: Icon(Icons.public, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              title: Text(s.etiqueta),
              subtitle: Text('${s.usuarios} usuario(s) · ${s.lecturas} lectura(s) registrada(s)'),
              trailing: const Icon(Icons.chevron_right),
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