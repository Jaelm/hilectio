import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lectura.dart';
import 'add_edit_lectura_screen.dart';
import 'resumenes_screen.dart';
import '../services/notification_service.dart';
import '../services/logros_service.dart';

class BibliotecaScreen extends StatefulWidget {
  const BibliotecaScreen({super.key});

  @override
  State<BibliotecaScreen> createState() => _BibliotecaScreenState();
}

class _BibliotecaScreenState extends State<BibliotecaScreen> {
  String _filtro = 'leyendo';

  Future<void> _abrirLink(BuildContext context, String link) async {
    if (link.trim().isEmpty) return;
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el link')),
        );
      }
    }
  }

  Future<void> _eliminar(String uid, String id) async {
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .doc(id)
        .delete();
    await NotificationService().cancelar(id);
  }

  Future<void> _cambiarEstado(String uid, String id, String nuevoEstado) async {
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .doc(id)
        .update({'estado': nuevoEstado});
  }

  Future<void> _compartirEstado(BuildContext context, Lectura l) async {
    await Share.share(
      'Estoy ${estadosLectura[l.estado]?.toLowerCase() ?? 'leyendo'} '
      '"${l.titulo}" (cap. ${l.capituloActual}) en Hilectio 📖',
    );
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final logros = await LogrosService().registrarCompartido(uid);
    if (logros.isNotEmpty && context.mounted) {
      mostrarLogrosDesbloqueados(context, logros);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final stream = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .orderBy('actualizadoEn', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: estadosLectura.entries.map((e) {
                  final seleccionado = _filtro == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: seleccionado,
                      onSelected: (_) => setState(() => _filtro = e.key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                final lecturas = docs
                    .map((d) => Lectura.fromDoc(d))
                    .where((l) => !l.esAdulto && l.estado == _filtro)
                    .toList();
                if (lecturas.isEmpty) {
                  return Center(
                    child: Text(
                      'No tienes lecturas marcadas como "${estadosLectura[_filtro]}".',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lecturas.length,
                  itemBuilder: (context, i) {
                    final l = lecturas[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(l.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${l.tipo} · Cap. ${l.capituloActual} · ${l.plataforma}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'abrir') _abrirLink(context, l.link);
                            if (v == 'editar') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => AddEditLecturaScreen(lectura: l)),
                              );
                            }
                            if (v == 'eliminar') _eliminar(uid, l.id);
                            if (v == 'compartir') _compartirEstado(context, l);
                            if (v == 'resumenes') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResumenesScreen(
                                    tituloObra: l.titulo,
                                    capituloSugerido: l.capituloActual,
                                  ),
                                ),
                              );
                            }
                            if (estadosLectura.containsKey(v) && v != l.estado) {
                              _cambiarEstado(uid, l.id, v);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'abrir', child: Text('Abrir link')),
                            const PopupMenuItem(value: 'editar', child: Text('Editar')),
                            const PopupMenuItem(value: 'resumenes', child: Text('Resúmenes')),
                            const PopupMenuItem(value: 'compartir', child: Text('Compartir estado')),
                            const PopupMenuDivider(),
                            ...estadosLectura.entries
                                .where((e) => e.key != l.estado)
                                .map((e) => PopupMenuItem(
                                      value: e.key,
                                      child: Text('Marcar como ${e.value}'),
                                    )),
                            const PopupMenuDivider(),
                            const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                          ],
                        ),
                        onTap: () => _abrirLink(context, l.link),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditLecturaScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}