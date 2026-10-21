import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/obra_service.dart';
import '../services/cofres_service.dart' show iconosFoto;
import 'obra_detalle_screen.dart';
import 'perfil_publico_screen.dart';
import 'ranking_plataformas_view.dart';

const String _correoAdmin = 'jhormanskic98@gmail.com';

/// Pestaña "Descubrir": busca obras ya registradas en la plataforma (para
/// llegar directo a sus resúmenes) y usuarios por apodo (para llegar a su
/// perfil público).
class DescubrirScreen extends StatefulWidget {
  const DescubrirScreen({super.key});

  @override
  State<DescubrirScreen> createState() => _DescubrirScreenState();
}

class _FiltrosObras {
  String? tipo;
  String? estado;
  String autor;
  String anio;
  String genero;

  _FiltrosObras({
    this.tipo,
    this.estado,
    this.autor = '',
    this.anio = '',
    this.genero = '',
  });

  _FiltrosObras copiar() => _FiltrosObras(
        tipo: tipo,
        estado: estado,
        autor: autor,
        anio: anio,
        genero: genero,
      );

  bool get hayFiltrosActivos =>
      tipo != null ||
      estado != null ||
      autor.trim().isNotEmpty ||
      anio.trim().isNotEmpty ||
      genero.trim().isNotEmpty;

  int get cantidadActivos => [
        tipo != null,
        estado != null,
        autor.trim().isNotEmpty,
        anio.trim().isNotEmpty,
        genero.trim().isNotEmpty,
      ].where((e) => e).length;
}

class _DescubrirScreenState extends State<DescubrirScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  _FiltrosObras _filtros = _FiltrosObras();

  @override
  void initState() {
    super.initState();
    // Para que el botón de filtro solo se muestre en la pestaña "Obras".
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirFiltros() async {
    final resultado = await showModalBottomSheet<_FiltrosObras>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HojaFiltros(filtrosIniciales: _filtros.copiar()),
    );
    if (resultado != null) {
      setState(() => _filtros = resultado);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Descubrir'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Obras'),
            Tab(text: 'Usuarios'),
            Tab(text: 'Plataformas'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_tabs.index != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _busquedaCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
                    ),
                  ),
                  if (_tabs.index == 0) ...[
                    const SizedBox(width: 8),
                    Badge(
                      isLabelVisible: _filtros.hayFiltrosActivos,
                      label: Text('${_filtros.cantidadActivos}'),
                      child: IconButton.filledTonal(
                        onPressed: _abrirFiltros,
                        icon: const Icon(Icons.filter_list),
                        tooltip: 'Filtrar obras',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ObrasTab(busqueda: _busqueda, filtros: _filtros),
                _UsuariosTab(busqueda: _busqueda),
                const RankingPlataformasView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HojaFiltros extends StatefulWidget {
  final _FiltrosObras filtrosIniciales;
  const _HojaFiltros({required this.filtrosIniciales});

  @override
  State<_HojaFiltros> createState() => _HojaFiltrosState();
}

class _HojaFiltrosState extends State<_HojaFiltros> {
  late _FiltrosObras _f = widget.filtrosIniciales.copiar();
  late final _autorCtrl = TextEditingController(text: _f.autor);
  late final _anioCtrl = TextEditingController(text: _f.anio);
  late final _generoCtrl = TextEditingController(text: _f.genero);

  @override
  void dispose() {
    _autorCtrl.dispose();
    _anioCtrl.dispose();
    _generoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Filtrar obras', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _f = _FiltrosObras();
                    _autorCtrl.text = '';
                    _anioCtrl.text = '';
                    _generoCtrl.text = '';
                  }),
                  child: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _f.tipo,
              decoration: const InputDecoration(labelText: 'Tipo de lectura'),
              hint: const Text('Todos'),
              items: tiposLectura
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _f.tipo = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _f.estado,
              decoration: const InputDecoration(labelText: 'Estado de la obra'),
              hint: const Text('Todos'),
              items: opcionesCampo['estado']!
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _f.estado = v),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _autorCtrl,
              decoration: const InputDecoration(labelText: 'Autor/Creador'),
              onChanged: (v) => _f.autor = v,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _generoCtrl,
              decoration: const InputDecoration(
                labelText: 'Género',
                helperText: 'Ej. Acción, Fantasía',
              ),
              onChanged: (v) => _f.genero = v,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _anioCtrl,
              decoration: const InputDecoration(labelText: 'Año de publicación'),
              keyboardType: TextInputType.number,
              onChanged: (v) => _f.anio = v,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(context, _f),
              child: const Text('Aplicar filtros'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _editarPortada(
  BuildContext context, {
  required String titulo,
  String? urlActual,
}) async {
  final ctrl = TextEditingController(text: urlActual ?? '');
  final nuevoUrl = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Portada de "$titulo"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Link de la imagen',
              helperText:
                  'Puede ser el link de "Compartir" de Drive (asegúrate de que '
                  'el archivo esté en "Cualquiera con el link puede ver") o el '
                  'link directo de cualquier otro sitio.',
            ),
          ),
        ],
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
    await ObraService().actualizarPortada(tituloLectura: titulo, urlImagen: nuevoUrl);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la portada: $e')),
      );
    }
  }
}

class _ObrasTab extends StatelessWidget {
  final String busqueda;
  final _FiltrosObras filtros;
  const _ObrasTab({required this.busqueda, required this.filtros});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('obras')
          .orderBy('tituloOriginal')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        final filtroAutor = filtros.autor.trim().toLowerCase();
        final filtroAnio = filtros.anio.trim();
        final filtroGenero = filtros.genero.trim().toLowerCase();

        final filtradas = docs.where((d) {
          final data = d.data();
          final titulo = (data['tituloOriginal'] as String? ?? '').toLowerCase();
          if (busqueda.isNotEmpty && !titulo.contains(busqueda)) return false;

          if (filtros.tipo != null && data['tipo'] != filtros.tipo) return false;

          final campos = Map<String, dynamic>.from(data['campos'] ?? {});

          if (filtros.estado != null) {
            final estadoValor = campos['estado'] is Map ? campos['estado']['valor'] : null;
            if (estadoValor != filtros.estado) return false;
          }

          if (filtroAutor.isNotEmpty) {
            final autorValor = campos['autor'] is Map ? campos['autor']['valor'] : null;
            final autorTexto = formatearValorCampo(autorValor).toLowerCase();
            if (!autorTexto.contains(filtroAutor)) return false;
          }

          if (filtroGenero.isNotEmpty) {
            final generoValor = campos['genero'] is Map ? campos['genero']['valor'] : null;
            final generoTexto = formatearValorCampo(generoValor).toLowerCase();
            if (!generoTexto.contains(filtroGenero)) return false;
          }

          if (filtroAnio.isNotEmpty) {
            final fechaValor = campos['fechaPublicacion'] is Map
                ? campos['fechaPublicacion']['valor'] as String?
                : null;
            final anioObra = (fechaValor != null && fechaValor.length >= 4)
                ? fechaValor.substring(0, 4)
                : null;
            if (anioObra != filtroAnio) return false;
          }

          return true;
        }).toList();

        if (filtradas.isEmpty) {
          return Center(
            child: Text(
              filtros.hayFiltrosActivos || busqueda.isNotEmpty
                  ? 'No se encontraron obras con esos filtros.'
                  : 'No se encontraron obras.',
              textAlign: TextAlign.center,
            ),
          );
        }
        final esAdmin = FirebaseAuth.instance.currentUser?.email == _correoAdmin;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtradas.length,
          itemBuilder: (context, i) {
            final data = filtradas[i].data();
            final titulo = data['tituloOriginal'] as String? ?? filtradas[i].id;
            final imagenUrl = data['imagenUrl'] as String?;
            final esAdulto = data['esAdulto'] == true;
            final campos = Map<String, dynamic>.from(data['campos'] ?? {});

            String? valorCampo(String campo) {
              final c = campos[campo];
              if (c is! Map) return null;
              final texto = formatearValorCampo(c['valor'], campo: campo);
              return texto.isEmpty ? null : texto;
            }

            // Solo lo esencial en la tarjeta: portada, nombre, creador y
            // estado. El resto de los datos (tipo, género, etc.) se ve al
            // entrar a la obra.
            final partesSubtitulo = <String>[
              if (valorCampo('autor') != null) valorCampo('autor')!,
              if (valorCampo('estado') != null) valorCampo('estado')!,
            ];

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: SizedBox(
                  width: 42,
                  height: 58,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: (imagenUrl != null && imagenUrl.isNotEmpty)
                        ? Image.network(
                            imagenUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.deepOrange.shade50,
                              alignment: Alignment.center,
                              child: const Icon(Icons.menu_book_outlined, color: Colors.deepOrange),
                            ),
                          )
                        : Container(
                            color: Colors.deepOrange.shade50,
                            alignment: Alignment.center,
                            child: const Icon(Icons.menu_book_outlined, color: Colors.deepOrange),
                          ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(child: Text(titulo, overflow: TextOverflow.ellipsis)),
                    if (esAdulto) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Contenido +18',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '18+',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: partesSubtitulo.isNotEmpty ? Text(partesSubtitulo.join(' · ')) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (esAdmin)
                      IconButton(
                        icon: const Icon(Icons.image_outlined, size: 20),
                        tooltip: 'Cambiar portada',
                        onPressed: () => _editarPortada(context, titulo: titulo, urlActual: imagenUrl),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ObraDetalleScreen(titulo: titulo)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UsuariosTab extends StatelessWidget {
  final String busqueda;
  const _UsuariosTab({required this.busqueda});

  @override
  Widget build(BuildContext context) {
    if (busqueda.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Escribe un apodo para buscar usuarios.', textAlign: TextAlign.center),
        ),
      );
    }
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('apodos')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: busqueda)
          .where(FieldPath.documentId, isLessThan: '$busqueda')
          .limit(20)
          .get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No se pudo buscar usuarios (faltan permisos de Firestore en la '
                'colección "apodos").',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No se encontraron usuarios con ese apodo.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final uid = docs[i].data()['uid'] as String? ?? docs[i].id;
            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('usuarios').doc(uid).get(),
              builder: (context, userSnap) {
                final data = userSnap.data?.data() ?? {};
                final apodo = data['apodo'] as String? ?? '...';
                final foto = data['fotoSeleccionada'] as String?;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepOrange.shade50,
                      child: Icon(iconosFoto[foto] ?? Icons.person, color: Colors.deepOrange),
                    ),
                    title: Text(apodo),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PerfilPublicoScreen(uid: uid)),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}