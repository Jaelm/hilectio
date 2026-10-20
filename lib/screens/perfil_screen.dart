import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'boveda_screen.dart';
import 'cuestionario_screen.dart';
import 'admin_propuestas_screen.dart';
import 'admin_resumenes_screen.dart';
import '../models/lectura.dart' show estadosLectura;
import '../services/obra_service.dart';
import '../services/cofres_service.dart';
import '../services/logros_service.dart';
import 'elegir_apodo_screen.dart';

// TODO: reemplaza esto por tu link real de Ko-fi, Buy Me a Coffee, o el que
// uses para donaciones.
const String _urlDonaciones = 'https://ko-fi.com/bloomcebo';

const Map<String, Color> _coloresEstado = {
  'leyendo': Colors.deepOrange,
  'pendiente': Colors.amber,
  'abandonado': Colors.grey,
  'terminado': Colors.green,
};

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  static const _correoAdmin = 'jhormanskic98@gmail.com';

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid != null) {
      if (user?.email == _correoAdmin) {
        _otorgarTodoAlAdmin(uid);
      }
      LogrosService().registrarInteraccion(uid);
      LogrosService().evaluarCompleto(uid).then((logros) {
        if (logros.isNotEmpty && mounted) {
          mostrarLogrosDesbloqueados(context, logros);
        }
      });
    }
  }

  /// Le da al admin todos los títulos (comunes, raros, legendarios y los
  /// ocultos de logros) y todas las fotos de perfil, sin tener que abrir
  /// cofres ni cumplir los logros. Solo agrega lo que le falte, así que no
  /// pisa el título/foto que ya tenga seleccionado.
  Future<void> _otorgarTodoAlAdmin(String uid) async {
    final todosLosTitulos = <String>{
      ...CofresService.catalogos[Pool.titulos]!.values.expand((l) => l),
      ...logrosOcultos.values,
    }.toList();
    final todasLasFotos = CofresService.catalogos[Pool.fotos]!.values
        .expand((l) => l)
        .toSet()
        .toList();

    final ref = FirebaseFirestore.instance.collection('usuarios').doc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final titulosActuales = List<String>.from(data['titulosObtenidos'] ?? []);
    final fotosActuales = List<String>.from(data['fotosObtenidas'] ?? []);

    final faltanTitulos = todosLosTitulos.where((t) => !titulosActuales.contains(t)).toList();
    final faltanFotos = todasLasFotos.where((f) => !fotosActuales.contains(f)).toList();

    if (faltanTitulos.isEmpty && faltanFotos.isEmpty) return;

    await ref.set({
      if (faltanTitulos.isNotEmpty)
        'titulosObtenidos': FieldValue.arrayUnion(faltanTitulos),
      if (faltanFotos.isNotEmpty)
        'fotosObtenidas': FieldValue.arrayUnion(faltanFotos),
    }, SetOptions(merge: true));
  }

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
              final apodo = data['apodo'] as String? ?? correo;
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
                                Text(apodo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ElegirApodoScreen()),
                          ),
                          icon: const Icon(Icons.badge_outlined, size: 18),
                          label: const Text('Cambiar apodo'),
                        ),
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
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('usuarios')
                .doc(uid)
                .collection('lecturas')
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();

              final conteos = <String, int>{for (final e in estadosLectura.keys) e: 0};
              for (final d in docs) {
                final estado = d.data()['estado'] as String?;
                if (estado != null && conteos.containsKey(estado)) {
                  conteos[estado] = conteos[estado]! + 1;
                }
              }
              final total = docs.length;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tus lecturas',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 130,
                            width: 130,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                PieChart(
                                  PieChartData(
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 34,
                                    sections: [
                                      for (final entry in conteos.entries)
                                        if (entry.value > 0)
                                          PieChartSectionData(
                                            value: entry.value.toDouble(),
                                            color: _coloresEstado[entry.key],
                                            title: '',
                                            radius: 28,
                                          ),
                                    ],
                                  ),
                                ),
                                Text('$total',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 18)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final entry in conteos.entries)
                                  if (entry.value > 0)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: _coloresEstado[entry.key],
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${estadosLectura[entry.key]}: ${entry.value}',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                              ],
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
            leading: const Icon(Icons.favorite_outline, color: Colors.pink),
            title: const Text('Apoya el proyecto'),
            subtitle: const Text('Hilectio nunca vende tokens — si quieres, puedes donar'),
            onTap: () async {
              final uri = Uri.tryParse(_urlDonaciones);
              if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se pudo abrir el link de donaciones')),
                  );
                }
              }
            },
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
    final logros = await LogrosService().alCambiarPerfil(uid);
    if (logros.isNotEmpty && context.mounted) {
      mostrarLogrosDesbloqueados(context, logros);
    }
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
    final logros = await LogrosService().alCambiarPerfil(uid);
    if (logros.isNotEmpty && context.mounted) {
      mostrarLogrosDesbloqueados(context, logros);
    }
  }
}

String _formatoFecha(DateTime d) {
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${d.day} ${meses[d.month - 1]} ${d.year}';
}