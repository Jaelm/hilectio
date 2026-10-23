import 'dart:async';
import 'package:flutter/material.dart';
import '../services/cuestionario_service.dart';

enum _Fase { cargandoDisponibilidad, bloqueado, eligiendoDificultad, armando, sinDatos, jugando, resultado }

class CuestionarioScreen extends StatefulWidget {
  const CuestionarioScreen({super.key});

  @override
  State<CuestionarioScreen> createState() => _CuestionarioScreenState();
}

class _CuestionarioScreenState extends State<CuestionarioScreen> {
  _Fase _fase = _Fase.cargandoDisponibilidad;
  String? _dificultad;
  List<PreguntaCuestionario> _preguntas = [];
  int _indice = 0;
  int _segundosRestantes = 0;
  Timer? _timer;
  final _respuestaCtrl = TextEditingController();

  double _puntajeTotal = 0;
  int _tokensGanados = 0;

  /// "3" si es entero, "3.5" si trae medio punto (solo pasa con la pregunta
  /// de género en Infernal).
  String _formatearPuntaje(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _verificarDisponibilidad();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _respuestaCtrl.dispose();
    super.dispose();
  }

  Future<void> _verificarDisponibilidad() async {
    final disponible = await CuestionarioService().puedeHacerCuestionario();
    if (!mounted) return;
    setState(() => _fase = disponible ? _Fase.eligiendoDificultad : _Fase.bloqueado);
  }

  Future<void> _elegirDificultad(String dificultad) async {
    setState(() {
      _dificultad = dificultad;
      _fase = _Fase.armando;
    });
    final preguntas = await CuestionarioService().armarPreguntas(dificultad);
    if (!mounted) return;
    if (preguntas == null) {
      setState(() => _fase = _Fase.sinDatos);
      return;
    }
    setState(() {
      _preguntas = preguntas;
      _indice = 0;
      _fase = _Fase.jugando;
    });
    _iniciarPregunta();
  }

  void _iniciarPregunta() {
    _timer?.cancel();
    _respuestaCtrl.clear();
    final cfg = configDificultad(_dificultad!);
    setState(() => _segundosRestantes = cfg.segundosPorPregunta);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_segundosRestantes <= 1) {
        t.cancel();
        _avanzar();
      } else {
        setState(() => _segundosRestantes--);
      }
    });
  }

  void _seleccionarOpcion(String opcion) {
    setState(() => _preguntas[_indice].respuestaUsuario = opcion);
    _avanzar();
  }

  void _avanzar() {
    _timer?.cancel();
    if (_dificultad != null && configDificultad(_dificultad!).respuestaLibre) {
      _preguntas[_indice].respuestaUsuario = _respuestaCtrl.text;
    }
    if (_indice + 1 < _preguntas.length) {
      setState(() => _indice++);
      _iniciarPregunta();
    } else {
      _finalizar();
    }
  }

  Future<void> _finalizar() async {
    final puntaje = _preguntas.fold<double>(0, (suma, p) => suma + p.puntaje);
    final tokens = await CuestionarioService().reclamarRecompensa(_dificultad!, puntaje);
    if (!mounted) return;
    setState(() {
      _puntajeTotal = puntaje;
      _tokensGanados = tokens;
      _fase = _Fase.resultado;
    });
  }

  void _volverAElegir() {
    setState(() {
      _dificultad = null;
      _preguntas = [];
      _fase = _Fase.eligiendoDificultad;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_fase) {
      case _Fase.cargandoDisponibilidad:
      case _Fase.armando:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _Fase.bloqueado:
        return _vistaBloqueado();
      case _Fase.eligiendoDificultad:
        return _vistaEligiendoDificultad();
      case _Fase.sinDatos:
        return _vistaSinDatos();
      case _Fase.jugando:
        return _vistaJugando();
      case _Fase.resultado:
        return _vistaResultado();
    }
  }

  Widget _vistaBloqueado() {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuestionario semanal')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ya hiciste el cuestionario de esta semana. Vuelve en unos días para intentar otro.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _vistaEligiendoDificultad() {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuestionario semanal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Elige una dificultad. Solo puedes hacer un cuestionario por semana, así que '
            'elige con cuidado.',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...dificultadesCuestionario.map((cfg) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(14),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(cfg.nombre,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Hasta ${cfg.recompensaPorAciertos.last} tokens',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(cfg.descripcion),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _elegirDificultad(cfg.id),
                ),
              )),
        ],
      ),
    );
  }

  Widget _vistaSinDatos() {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuestionario semanal')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Todavía no tienes suficientes obras (o datos ya validados de ellas) para '
                'esta dificultad. Prueba con otra, o sigue leyendo y validando datos de obras '
                'en Descubrir.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _volverAElegir, child: const Text('Elegir otra dificultad')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _vistaJugando() {
    final pregunta = _preguntas[_indice];
    final cfg = configDificultad(_dificultad!);
    return Scaffold(
      appBar: AppBar(
        title: Text('${cfg.nombre} · Pregunta ${_indice + 1}/${_preguntas.length}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: _segundosRestantes / cfg.segundosPorPregunta,
              minHeight: 8,
              color: _segundosRestantes <= 5 ? Colors.red : null,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$_segundosRestantes s',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _segundosRestantes <= 5 ? Colors.red : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              pregunta.enunciado,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            if (pregunta.opciones != null)
              ...pregunta.opciones!.map((op) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          // Forma fija (no "stadium"): con texto de 2+ líneas,
                          // la forma por defecto se redondea tanto que el
                          // texto se sale de la curva. Con esquinas chicas y
                          // fijas el botón crece parejo con el texto.
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _seleccionarOpcion(op),
                        child: Text(op, textAlign: TextAlign.center),
                      ),
                    ),
                  ))
            else ...[
              TextField(
                controller: _respuestaCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tu respuesta',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _avanzar(),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _avanzar, child: const Text('Responder')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vistaResultado() {
    final cfg = configDificultad(_dificultad!);
    return Scaffold(
      appBar: AppBar(title: const Text('Resultado')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${cfg.nombre}: acertaste ${_formatearPuntaje(_puntajeTotal)} de ${_preguntas.length}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(_tokensGanados > 0
                  ? '¡Ganaste $_tokensGanados tokens!'
                  : 'No ganaste tokens esta vez, pero ya usaste tu intento de la semana.'),
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
}