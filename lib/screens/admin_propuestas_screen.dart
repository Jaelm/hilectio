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
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendientes = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final docs = await ObraService().listarPendientes();
    setState(() {
      _pendientes = docs;
      _cargando = false;
    });
  }

  Future<void> _aprobar(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final obraId = doc.reference.parent.parent!.id;
    await ObraService().aprobarPropuesta(
      obraId: obraId,
      propuestaId: doc.id,
      campo: data['campo'],
      valor: data['valor'],
    );
    _cargar();
  }

  Future<void> _rechazar(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final obraId = doc.reference.parent.parent!.id;
    await ObraService().rechazarPropuesta(obraId: obraId, propuestaId: doc.id);
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
                        title: Text(obraId),
                        subtitle: Text('$nombreCampo: "${data['valor']}"'),
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