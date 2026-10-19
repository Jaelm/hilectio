import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/cofres_service.dart';

class CofresScreen extends StatefulWidget {
  const CofresScreen({super.key});

  @override
  State<CofresScreen> createState() => _CofresScreenState();
}

class _CofresScreenState extends State<CofresScreen> {
  Pool _pool = Pool.titulos;
  bool _abriendo = false;

  static const _info = {
    TipoCofre.normal: {
      'nombre': 'Cofre normal',
      'desc': '70% normal · 25% raro · 5% legendario',
      'color': Color(0xFFE7D9C3),
      'fg': Color(0xFF8A6D3B),
    },
    TipoCofre.raro: {
      'nombre': 'Cofre raro',
      'desc': '40% normal · 45% raro · 15% legendario',
      'color': Color(0xFFE3DCF2),
      'fg': Color(0xFF6B4FA0),
    },
    TipoCofre.legendario: {
      'nombre': 'Cofre legendario',
      'desc': '20% normal · 40% raro · 40% legendario',
      'color': Color(0xFFF6E8B8),
      'fg': Color(0xFFA5820F),
    },
  };

  Future<void> _abrir(TipoCofre cofre) async {
    setState(() => _abriendo = true);
    final resultado = await CofresService().abrirCofre(cofre: cofre, pool: _pool);
    if (mounted) setState(() => _abriendo = false);

    if (!mounted) return;

    if (resultado['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(resultado['error'])),
      );
      return;
    }

    final item = resultado['item'];
    final rareza = resultado['rareza'];
    final yaTenia = resultado['yaTenia'] == true;
    final devolucion = resultado['devolucion'];

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(yaTenia ? 'Repetido' : '¡Nuevo!'),
        content: Text(yaTenia
            ? 'Te salió "$item" ($rareza), pero ya lo tenías. Se te devolvió $devolucion tokens.'
            : 'Obtuviste "$item" ($rareza)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Genial')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDocStream =
        FirebaseFirestore.instance.collection('usuarios').doc(uid).snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cofres'),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: userDocStream,
            builder: (context, snapshot) {
              final tokens = (snapshot.data?.data() as Map<String, dynamic>?)?['tokens'] ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Row(
                    children: [
                      const Icon(Icons.toll, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text('$tokens', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<Pool>(
            segments: const [
              ButtonSegment(value: Pool.titulos, label: Text('Títulos')),
              ButtonSegment(value: Pool.fotos, label: Text('Fotos de perfil')),
            ],
            selected: {_pool},
            onSelectionChanged: (s) => setState(() => _pool = s.first),
          ),
          const SizedBox(height: 16),
          ...TipoCofre.values.map((cofre) {
            final info = _info[cofre]!;
            final costo = CofresService.costos[cofre]!;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: info['color'] as Color,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.inventory_2, color: info['fg'] as Color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(info['nombre'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(info['desc'] as String,
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _abriendo ? null : () => _abrir(cofre),
                      child: Text('Abrir — $costo tokens'),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFFFF3EA),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Si al abrir un cofre te sale un título o imagen de perfil que ya tienes, se te devuelve el 50% de los tokens que pagaste.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}