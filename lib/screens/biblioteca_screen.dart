import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lectura.dart';
import 'add_edit_lectura_screen.dart';
import '../services/notification_service.dart';

class BibliotecaScreen extends StatelessWidget {
  const BibliotecaScreen({super.key});

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
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('Aún no agregas ninguna lectura.\nToca el botón + para empezar.',
                  textAlign: TextAlign.center),
            );
          }
          final lecturas = docs.map((d) => Lectura.fromDoc(d)).toList();
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
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'abrir', child: Text('Abrir link')),
                      PopupMenuItem(value: 'editar', child: Text('Editar')),
                      PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                    ],
                  ),
                  onTap: () => _abrirLink(context, l.link),
                ),
              );
            },
          );
        },
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