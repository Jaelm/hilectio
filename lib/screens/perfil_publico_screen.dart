import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/lectura.dart';
import '../services/cofres_service.dart' show iconosFoto;
import '../services/bloqueo_service.dart';

/// Perfil de OTRO usuario (de solo lectura). Muestra su apodo, foto, título
/// y racha, más la lista de sus lecturas que NO son +18 (las de la bóveda
/// nunca se exponen aquí). Requiere que las reglas de Firestore permitan
/// leer `usuarios/{uid}/lecturas` cuando `esAdulto == false`, aunque quien
/// pregunta no sea el dueño del documento.
class PerfilPublicoScreen extends StatefulWidget {
  final String uid;

  const PerfilPublicoScreen({super.key, required this.uid});

  @override
  State<PerfilPublicoScreen> createState() => _PerfilPublicoScreenState();
}

class _PerfilPublicoScreenState extends State<PerfilPublicoScreen> {
  final _bloqueoService = BloqueoService();
  bool _cargandoBloqueo = true;
  bool _meBloqueo = false;

  @override
  void initState() {
    super.initState();
    _verificarBloqueo();
  }

  Future<void> _verificarBloqueo() async {
    final bloqueado = await _bloqueoService.meBloqueo(widget.uid);
    if (mounted) {
      setState(() {
        _meBloqueo = bloqueado;
        _cargandoBloqueo = false;
      });
    }
  }

  Future<void> _alternarBloqueo(bool yaLoBloquee) async {
    if (yaLoBloquee) {
      await _bloqueoService.desbloquear(widget.uid);
    } else {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Bloquear usuario?'),
          content: const Text(
            'Dejarás de ver sus resúmenes y ya no podrá ver tu perfil. Puedes '
            'desbloquearlo cuando quieras.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bloquear')),
          ],
        ),
      );
      if (confirmar != true) return;
      await _bloqueoService.bloquear(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final esPropio = uid == FirebaseAuth.instance.currentUser?.uid;

    if (_cargandoBloqueo) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_meBloqueo) {
      return Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este perfil no está disponible.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(esPropio ? 'Tu perfil' : 'Perfil'),
        actions: esPropio
            ? null
            : [
                StreamBuilder<bool>(
                  stream: _bloqueoService.yoLoBloqueeStream(uid),
                  builder: (context, bloqueoSnap) {
                    final yaLoBloquee = bloqueoSnap.data ?? false;
                    return IconButton(
                      onPressed: () => _alternarBloqueo(yaLoBloquee),
                      icon: Icon(yaLoBloquee ? Icons.block : Icons.block_outlined),
                      tooltip: yaLoBloquee ? 'Desbloquear' : 'Bloquear usuario',
                    );
                  },
                ),
              ],
      ),
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
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          iconosFoto[foto] ?? Icons.person,
                          size: 30,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
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
                                  color: Theme.of(context).colorScheme.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Icon(Icons.local_fire_department, color: Theme.of(context).colorScheme.primary),
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