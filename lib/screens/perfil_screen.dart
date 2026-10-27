import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'boveda_screen.dart';
import 'cuestionario_screen.dart';
import 'apariencia_screen.dart';
import 'admin_propuestas_screen.dart';
import 'admin_resumenes_screen.dart';
import 'admin_plataformas_screen.dart';
import 'admin_fusionar_obras_screen.dart';
import '../models/lectura.dart' show estadosLectura;
import '../services/obra_service.dart';
import '../services/cofres_service.dart';
import '../services/logros_service.dart';
import '../services/cuenta_service.dart';
import 'elegir_apodo_screen.dart';

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

  /// Backfill de un solo uso: recorre todas las lecturas de todos los
  /// usuarios y registra en el catálogo `obras` cualquier título que todavía
  /// no esté ahí (sobre todo lecturas +18 guardadas antes de que esto se
  /// hiciera automático), para que aparezcan en Descubrir y en la Bóveda.
  /// Pide confirmación porque recorre toda la base de datos.
  Future<void> _ejecutarBackfillObras(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar obras faltantes'),
        content: const Text(
          'Esto revisa todas las lecturas guardadas por todos los usuarios y '
          'crea en el catálogo las que todavía no existan ahí (incluidas las '
          '+18). Puede tardar unos segundos. ¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (confirmar != true) return;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrando obras faltantes…')),
      );
    }
    try {
      final creadas = await ObraService().backfillObrasDesdeLecturas();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Listo: $creadas obra(s) nueva(s) registrada(s).')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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

  /// Borra la cuenta para siempre: pide confirmar, luego reautentica con la
  /// contraseña (Firebase lo exige para poder borrar la cuenta) y recién ahí
  /// llama a [CuentaService.eliminarCuenta]. Si algo falla a mitad de camino
  /// (sin conexión, etc.) no queda nada a medio borrar: Firestore se borra
  /// primero y la cuenta de Auth al final.
  Future<void> _eliminarCuenta(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Eliminar tu cuenta?'),
        content: const Text(
          'Esto borra tu perfil, tus lecturas, tus resúmenes y todo lo demás '
          'para siempre. No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade100,
              foregroundColor: Colors.red.shade900,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;

    final passCtrl = TextEditingController();
    String? errorDialog;
    bool borrando = false;
    final reautenticado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Confirma tu contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Por seguridad, escribe tu contraseña para eliminar la cuenta.'),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                onSubmitted: (_) {},
              ),
              if (errorDialog != null) ...[
                const SizedBox(height: 8),
                Text(errorDialog!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: borrando ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: borrando
                  ? null
                  : () async {
                      final email = FirebaseAuth.instance.currentUser?.email;
                      if (email == null || passCtrl.text.isEmpty) return;
                      setStateDialog(() {
                        errorDialog = null;
                        borrando = true;
                      });
                      try {
                        final cred = EmailAuthProvider.credential(
                          email: email,
                          password: passCtrl.text,
                        );
                        await FirebaseAuth.instance.currentUser!
                            .reauthenticateWithCredential(cred);
                        if (context.mounted) Navigator.pop(context, true);
                      } on FirebaseAuthException catch (e) {
                        setStateDialog(() {
                          errorDialog = e.message ?? 'Contraseña incorrecta';
                          borrando = false;
                        });
                      }
                    },
              child: borrando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (reautenticado != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Eliminando cuenta…')),
    );
    try {
      await CuentaService().eliminarCuenta();
      // No hace falta navegar: borrar la cuenta de Auth cierra la sesión y
      // el listener de authStateChanges manda de vuelta al login.
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar la cuenta: $e')),
        );
      }
    }
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
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Icon(
                                iconosFoto[fotoSeleccionada] ?? Icons.person,
                                size: 30,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                                      color: Theme.of(context).colorScheme.primary,
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
                            MaterialPageRoute(
                              builder: (_) => ElegirApodoScreen(esCambio: true, apodoActual: apodo),
                            ),
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
                          Icon(Icons.local_fire_department,
                              color: Theme.of(context).colorScheme.primary, size: 32),
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
            subtitle: const Text('Elige tu dificultad y gana hasta 100 tokens'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CuestionarioScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Apariencia'),
            subtitle: const Text('Modo claro/oscuro y color de la app'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AparienciaScreen()),
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
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Plataformas'),
              subtitle: const Text('Qué plataformas usa la gente y cuántos usuarios tiene cada una'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminPlataformasScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.merge_type),
              title: const Text('Fusionar obras duplicadas'),
              subtitle: const Text('Corregir un título mal escrito sin perder resúmenes/votos'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminFusionarObrasScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync_outlined),
              title: const Text('Registrar obras faltantes'),
              subtitle: const Text(
                'Un solo uso: indexa lecturas (incluidas +18) guardadas antes '
                'de que esto se hiciera automático',
              ),
              onTap: () => _ejecutarBackfillObras(context),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: () => FirebaseAuth.instance.signOut(),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: Text('Eliminar cuenta', style: TextStyle(color: Colors.red.shade700)),
            subtitle: const Text('Borra tu perfil y tus datos para siempre'),
            onTap: () => _eliminarCuenta(context),
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
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(iconosFoto[f] ?? Icons.person,
                        color: Theme.of(context).colorScheme.onPrimaryContainer),
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