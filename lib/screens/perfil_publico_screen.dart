import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/lectura.dart';
import '../services/cofres_service.dart' show iconosFoto;

/// Perfil de OTRO usuario (de solo lectura). Muestra su apodo, foto, título
/// y racha, más la lista de sus lecturas que NO son +18 (las de la bóveda
/// nunca se exponen aquí). Requiere que las reglas de Firestore permitan
/// leer `usuarios/{uid}/lecturas` cuando `esAdulto == false`, aunque quien
/// pregunta no sea el dueño del documento.
class PerfilPublicoScreen extends StatelessWidget {
  final String uid;

  const PerfilPublicoScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final esPropio = uid == FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: Text(esPropio ? 'Tu perfil' : 'Perfil')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data?.data() ?? {};
          final apodo = data['apodo'] as String? ?? 'Usuario';
          final foto = data['fotoSeleccionada'] as String?;
          final titulo = data['tituloSeleccionado'] as String?;
          final racha = data['rachaActual'] ?? 0;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.deepOrange.shade50,
                        child: Icon(
                          iconosFoto[foto] ?? Icons.person,
                          size: 30,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(apodo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            if (titulo != null)
                              Text(
                                titulo,
                                style: TextStyle(
                                  color: Colors.deepOrange.shade400,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.deepOrange),
                          Text('$racha'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Lecturas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('usuarios')
                    .doc(uid)
                    .collection('lecturas')
                    .where('esAdulto', isEqualTo: false)
                    .snapshots(),
                builder: (context, lecturaSnap) {
                  if (lecturaSnap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (lecturaSnap.hasError) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No se pudieron cargar las lecturas de este usuario '
                        '(faltan permisos de Firestore).',
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  }
                  final docs = lecturaSnap.data?.docs ?? [];
                  final lecturas = docs.map((d) => Lectura.fromDoc(d)).toList();
                  if (lecturas.isEmpty) {
                    return const Text('Sin lecturas públicas todavía.');
                  }
                  return Column(
                    children: lecturas.map((l) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(l.titulo),
                          subtitle: Text(
                            '${l.tipo} · Cap. ${l.capituloActual} · ${estadosLectura[l.estado] ?? l.estado}',
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}