import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/obra_service.dart';

/// Pantalla de admin: lista las obras del catálogo público que todavía no
/// tienen portada (imagenUrl), para ir subiéndolas poco a poco sin tener que
/// acordarse cuáles faltan.
class AdminPortadasScreen extends StatelessWidget {
  const AdminPortadasScreen({super.key});

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
                    'Link de "Compartir" de Drive (archivo en "Cualquiera con '
                    'el link puede ver") o el link directo de otro sitio.',
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Portada guardada')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portadas pendientes')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('obras')
            .orderBy('tituloOriginal')
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          final sinPortada = docs.where((d) {
            final imagenUrl = d.data()['imagenUrl'] as String?;
            return imagenUrl == null || imagenUrl.trim().isEmpty;
          }).toList();

          if (sinPortada.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '¡Todas las obras tienen portada! 🎉',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sinPortada.length,
            itemBuilder: (context, i) {
              final data = sinPortada[i].data();
              final titulo = data['tituloOriginal'] as String? ?? sinPortada[i].id;
              final tipo = data['tipo'] as String?;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.image_not_supported_outlined),
                  title: Text(titulo),
                  subtitle: tipo != null ? Text(tipo) : null,
                  trailing: FilledButton.tonal(
                    onPressed: () => _editarPortada(context, titulo: titulo),
                    child: const Text('Agregar'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}