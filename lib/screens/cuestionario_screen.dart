import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/lectura.dart';
import '../services/cuestionario_service.dart';

class CuestionarioScreen extends StatefulWidget {
  const CuestionarioScreen({super.key});

  @override
  State<CuestionarioScreen> createState() => _CuestionarioScreenState();
}

class _Pregunta {
  final String titulo;
  final int capituloCorrecto;
  final List<int> opciones;
  int? seleccion;
  _Pregunta({required this.titulo, required this.capituloCorrecto, required this.opciones});
}

class _CuestionarioScreenState extends State<CuestionarioScreen> {
  bool _cargando = true;
  bool _disponible = true;
  List<_Pregunta> _preguntas = [];
  bool _enviado = false;
  int _aciertos = 0;
  int _tokensGanados = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final disponible = await CuestionarioService().puedeHacerCuestionario();
    if (!disponible) {
      setState(() {
        _disponible = false;
        _cargando = false;
      });
      return;
    }

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .get();

    final lecturas = snap.docs
        .map((d) => Lectura.fromDoc(d))
        .where((l) => int.tryParse(l.capituloActual) != null)
        .toList();

    if (lecturas.length < 3) {
      setState(() {
        _disponible = false;
        _cargando = false;
      });
      return;
    }

    lecturas.shuffle();
    final elegidas = lecturas.take(3).toList();
    final rand = Random();

    final preguntas = elegidas.map((l) {
      final correcto = int.parse(l.capituloActual);
      final opciones = <int>{correcto};
      while (opciones.length < 4) {
        final delta = rand.nextInt(7) - 3;
        final opcion = correcto + delta;
        if (opcion >= 0) opciones.add(opcion);
      }
      final lista = opciones.toList()..shuffle();
      return _Pregunta(titulo: l.titulo, capituloCorrecto: correcto, opciones: lista);
    }).toList();

    setState(() {
      _preguntas = preguntas;
      _cargando = false;
    });
  }

  Future<void> _enviar() async {
    final aciertos = _preguntas.where((p) => p.seleccion == p.capituloCorrecto).length;
    final aprobo = aciertos >= CuestionarioService.minAciertos;
    final tokens = await CuestionarioService().reclamarRecompensa(aprobo);
    setState(() {
      _enviado = true;
      _aciertos = aciertos;
      _tokensGanados = tokens;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_disponible) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cuestionario semanal')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Ya hiciste el cuestionario esta semana, o necesitas al menos 3 lecturas guardadas con capítulo numérico. Vuelve en unos días.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_enviado) {
      return Scaffold(
        appBar: AppBar(title: const Text('Resultado')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Acertaste $_aciertos de ${_preguntas.length}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(_tokensGanados > 0
                    ? '¡Ganaste $_tokensGanados tokens!'
                    : 'No llegaste al mínimo para ganar tokens esta vez.'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Cuestionario semanal')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '¿En qué capítulo ibas? Responde las 3 preguntas para ganar 20 tokens.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ..._preguntas.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: p.opciones.map((op) {
                          final seleccionado = p.seleccion == op;
                          return ChoiceChip(
                            label: Text('Cap. $op'),
                            selected: seleccionado,
                            onSelected: (_) => setState(() => p.seleccion = op),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _preguntas.every((p) => p.seleccion != null) ? _enviar : null,
            child: const Text('Enviar respuestas'),
          ),
        ],
      ),
    );
  }
}