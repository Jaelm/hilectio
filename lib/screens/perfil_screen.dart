import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'boveda_screen.dart';
import 'cuestionario_screen.dart';
import 'admin_propuestas_screen.dart';
import 'admin_resumenes_screen.dart';
import '../services/obra_service.dart';
import '../services/cofres_service.dart';

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
          StreamBuilder<DocumentSnapshot>(
            stream: userDocStream,
            builder: (context, snapshot) {
              final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
              final fotoSeleccionada = data['fotoSeleccionada'] as String?;
              final tituloSeleccionado = data['tituloSeleccionado'] as String?;
              final fotosObtenidas = List<String>.from(data['fotosObtenidas'] ?? []);
              final titulosObtenidos = List<String>.from(data['titulosObtenidos'] ?? []);
              final miembroDesde = user.metadata.creationTime;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => _elegirFoto(context, uid, fotosObtenidas),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.deepOrange.shade50,
                              child: Icon(
                                iconosFoto[fotoSeleccionada] ?? Icons.person,
                                size: 30,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(correo, style: const TextStyle(fontWeight: FontWeight.bold)),
                                if (tituloSeleccionado != null)
                                  Text(
                                    tituloSeleccionado,
                                    style: TextStyle(
                                      color: Colors.deepOrange.shade400,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (miembroDesde != null)
                                  Text(
                                    'Miembro desde ${_formatoFecha(miembroDesde)}',
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _elegirFoto(context, uid, fotosObtenidas),
                              icon: const Icon(Icons.face_retouching_natural, size: 18),
                              label: const Text('Foto'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _elegirTitulo(context, uid, titulosObtenidos),
                              icon: const Icon(Icons.military_tech_outlined, size: 18),
                              label: const Text('Título'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            stream: ObraService().misPropuestasSinVer(uid),
            builder: (context, snap) {
              final docs = snap.data ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();
              return Card(
                color: Colors.blue.shade50,
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notifications_active, color: Colors.blue),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Novedades en tus propuestas de datos',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ObraService().marcarPropuestasComoVistas(
                              uid,
                              docs.map((d) => d.id).toList(),
                            ),
                            child: const Text('Marcar todo visto'),
                          ),
                        ],
                      ),
                      const Divider(height: 4),
                      ...docs.map((d) {
                        final data = d.data();
                        final aprobada = data['estado'] == 'aprobada';
                        final nombreCampo = camposObra[data['campo']] ?? data['campo'];
                        final titulo = data['tituloObra'] ?? data['obraId'] ?? '';
                        final tokens = (data['tokens'] as num?)?.toInt() ?? 0;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            aprobada ? Icons.check_circle : Icons.cancel,
                            color: aprobada ? Colors.green : Colors.red,
                          ),
                          title: Text('$titulo · $nombreCampo'),
                          subtitle: Text(
                            '"${formatearValorCampo(data['valor'], campo: data['campo'])}"'
                            '${aprobada && tokens > 0 ? ' · +$tokens tokens' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                ObraService().marcarPropuestasComoVistas(uid, [d.id]),
                          ),
                        );
                      }),
                    ],
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
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Resúmenes reportados'),
              subtitle: const Text('Revisar resúmenes marcados por el filtro automático'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminResumenesScreen()),
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

Future<void> _elegirFoto(BuildContext context, String uid, List<String> fotos) async {
  if (fotos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Todavía no tienes fotos de perfil. Consíguelas abriendo cofres.')),
    );
    return;
  }
  final elegida = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          children: fotos.map((f) {
            return InkWell(
              onTap: () => Navigator.pop(context, f),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.deepOrange.shade50,
                    child: Icon(iconosFoto[f] ?? Icons.person, color: Colors.deepOrange),
                  ),
                  const SizedBox(height: 4),
                  Text(f, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    ),
  );
  if (elegida != null) {
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
      {'fotoSeleccionada': elegida},
      SetOptions(merge: true),
    );
  }
}

Future<void> _elegirTitulo(BuildContext context, String uid, List<String> titulos) async {
  if (titulos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Todavía no tienes títulos. Consíguelos abriendo cofres.')),
    );
    return;
  }
  final elegido = await showModalBottomSheet<String>(
    context: context,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: titulos.map((t) {
          return ListTile(
            leading: const Icon(Icons.military_tech_outlined),
            title: Text(t),
            onTap: () => Navigator.pop(context, t),
          );
        }).toList(),
      ),
    ),
  );
  if (elegido != null) {
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
      {'tituloSeleccionado': elegido},
      SetOptions(merge: true),
    );
  }
}

String _formatoFecha(DateTime d) {
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${d.day} ${meses[d.month - 1]} ${d.year}';
}