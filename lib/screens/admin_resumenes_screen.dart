import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/resumenes_service.dart';

const String _correoAdmin = 'jhormanskic98@gmail.com';

class AdminResumenesScreen extends StatefulWidget {
  const AdminResumenesScreen({super.key});

  @override
  State<AdminResumenesScreen> createState() => _AdminResumenesScreenState();
}

class _AdminResumenesScreenState extends State<AdminResumenesScreen> {
  final _servicio = ResumenesService();
  bool _cargando = true;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendientes = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final docs = await _servicio.listarPendientesRevision();
      setState(() {
        _pendientes = docs;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _aprobar(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final obraId = doc.reference.parent.parent!.id;
    await _servicio.aprobarResumen(obraId: obraId, resumenId: doc.id);
    _cargar();
  }

  Future<void> _rechazar(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final obraId = doc.reference.parent.parent!.id;
    await _servicio.rechazarResumen(obraId: obraId, resumenId: doc.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rechazado. Se penalizó al autor con -$penalizacionViolacion tokens.')),
      );
    }
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final correo = FirebaseAuth.instance.currentUser?.email;
    if (correo != _correoAdmin) {
      return const Scaffold(
        body: Center(child: Text('No tienes acceso a esta sección.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resúmenes reportados'),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 40),
                        const SizedBox(height: 12),
                        const Text(
                          'No se pudieron cargar los resúmenes reportados.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : _pendientes.isEmpty
              ? const Center(child: Text('No hay resúmenes pendientes de revisión.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pendientes.length,
                  itemBuilder: (context, i) {
                    final doc = _pendientes[i];
                    final data = doc.data();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${data['tituloObra'] ?? doc.reference.parent.parent!.id} · Cap. ${data['capitulo'] ?? ''}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(data['texto'] ?? ''),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _aprobar(doc),
                                  icon: const Icon(Icons.check, color: Colors.green),
                                  label: const Text('Aprobar'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () => _rechazar(doc),
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  label: const Text('Rechazar (-$penalizacionViolacion)'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}