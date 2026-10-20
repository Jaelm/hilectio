import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/obra_service.dart';
import '../services/cofres_service.dart' show iconosFoto;
import 'resumenes_screen.dart';
import 'perfil_publico_screen.dart';

/// Pestaña "Descubrir": busca obras ya registradas en la plataforma (para
/// llegar directo a sus resúmenes) y usuarios por apodo (para llegar a su
/// perfil público).
class DescubrirScreen extends StatefulWidget {
  const DescubrirScreen({super.key});

  @override
  State<DescubrirScreen> createState() => _DescubrirScreenState();
}

class _DescubrirScreenState extends State<DescubrirScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void dispose() {
    _tabs.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
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
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ObrasTab(busqueda: _busqueda),
                _UsuariosTab(busqueda: _busqueda),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ObrasTab extends StatelessWidget {
  final String busqueda;
  const _ObrasTab({required this.busqueda});

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
        final filtradas = docs.where((d) {
          final titulo = (d.data()['tituloOriginal'] as String? ?? '').toLowerCase();
          return busqueda.isEmpty || titulo.contains(busqueda);
        }).toList();
        if (filtradas.isEmpty) {
          return const Center(child: Text('No se encontraron obras.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filtradas.length,
          itemBuilder: (context, i) {
            final data = filtradas[i].data();
            final titulo = data['tituloOriginal'] as String? ?? filtradas[i].id;
            final campos = Map<String, dynamic>.from(data['campos'] ?? {});
            final generoCampo = campos['genero'];
            final generoTexto = generoCampo is Map
                ? formatearValorCampo(generoCampo['valor'])
                : null;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(titulo),
                subtitle: (generoTexto != null && generoTexto.isNotEmpty)
                    ? Text(generoTexto)
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ResumenesScreen(tituloObra: titulo)),
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