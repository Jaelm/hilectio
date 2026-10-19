import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'boveda_screen.dart';
import 'cuestionario_screen.dart';
import 'admin_propuestas_screen.dart';
import '../services/obra_service.dart';

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  static const _correoAdmin = 'jhormanskic98@gmail.com';

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final correo = user?.email ?? '';
    final uid = user!.uid;
    final userDocStream =
        FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots();
    final esAdmin = correo == _correoAdmin;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(correo),
          ),
          StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            stream: ObraService().misPropuestasSinVer(uid),
            builder: (context, snap) {
              final docs = snap.data ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();
              final aprobadas = docs.where((d) => d.data()['estado'] == 'aprobada').length;
              final rechazadas = docs.where((d) => d.data()['estado'] == 'rechazada').length;
              final partes = <String>[];
              if (aprobadas > 0) partes.add('$aprobadas aprobada(s)');
              if (rechazadas > 0) partes.add('$rechazadas rechazada(s)');
              return Card(
                color: Colors.blue.shade50,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.notifications_active, color: Colors.blue),
                  title: const Text('Novedades en tus propuestas de datos'),
                  subtitle: Text(partes.join(', ')),
                  trailing: TextButton(
                    onPressed: () => ObraService().marcarPropuestasComoVistas(
                      uid,
                      docs.map((d) => d.id).toList(),
                    ),
                    child: const Text('Visto'),
                  ),
                ),
              );
            },
          ),
          const Divider(),
          StreamBuilder<DocumentSnapshot>(
            stream: userDocStream,
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
              final tokens = data['tokens'] ?? 0;
              final racha = data['rachaActual'] ?? 0;
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.local_fire_department,
                              color: Colors.deepOrange, size: 32),
                          const SizedBox(height: 4),
                          Text('$racha días',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Text('Racha', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.toll, color: Colors.amber, size: 32),
                          const SizedBox(height: 4),
                          Text('$tokens',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Text('Tokens', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.quiz_outlined),
            title: const Text('Cuestionario semanal'),
            subtitle: const Text('Responde y gana 20 tokens'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CuestionarioScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Bóveda +18'),
            subtitle: const Text('Lecturas ocultas protegidas con PIN'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BovedaScreen()),
            ),
          ),
          if (esAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Propuestas pendientes'),
              subtitle: const Text('Revisar datos de obras enviados por usuarios'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPropuestasScreen()),
              ),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
    );
  }
}