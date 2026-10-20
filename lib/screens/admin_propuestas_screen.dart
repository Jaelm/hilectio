import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/obra_service.dart';

const String _correoAdmin = 'jhormanskic98@gmail.com';

class AdminPropuestasScreen extends StatefulWidget {
  const AdminPropuestasScreen({super.key});

  @override
  State<AdminPropuestasScreen> createState() => _AdminPropuestasScreenState();
}

class _AdminPropuestasScreenState extends State<AdminPropuestasScreen> {
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
      final docs = await ObraService().listarPendientes();
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
    final data = doc.data();
    final obraId = doc.reference.parent.parent!.id;
    try {
      await ObraService().aprobarPropuesta(
        obraId: obraId,
        propuestaId: doc.id,
        campo: data['campo'],
        valor: data['valor'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo aprobar: $e')),
        );
      }
    }
    _cargar();
  }

  Future<void> _rechazar(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final obraId = doc.reference.parent.parent!.id;
    try {
      await ObraService().rechazarPropuesta(obraId: obraId, propuestaId: doc.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo rechazar: $e')),
        );
      }
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
        title: const Text('Propuestas pendientes'),
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
                          'No se pudieron cargar las propuestas pendientes.',
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
              ? const Center(child: Text('No hay propuestas pendientes.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pendientes.length,
                  itemBuilder: (context, i) {
                    final doc = _pendientes[i];
                    final data = doc.data();
                    final obraId = doc.reference.parent.parent!.id;
                    final nombreCampo = camposObra[data['campo']] ?? data['campo'];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(data['tituloObra'] ?? obraId),
                        subtitle: Text(
                          '$nombreCampo: "${formatearValorCampo(data['valor'], campo: data['campo'])}"',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () => _aprobar(doc),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _rechazar(doc),
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