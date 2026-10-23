import 'package:flutter/material.dart';
import '../services/apodo_service.dart';

/// Pantalla para elegir (o cambiar) el apodo con el que el usuario se
/// identifica ante los demás, en vez de su correo. Se usa tanto como paso
/// obligatorio la primera vez (ver AuthGate en main.dart) como desde el
/// botón "Cambiar apodo" en Perfil.
class ElegirApodoScreen extends StatefulWidget {
  const ElegirApodoScreen({super.key});

  @override
  State<ElegirApodoScreen> createState() => _ElegirApodoScreenState();
}

class _ElegirApodoScreenState extends State<ElegirApodoScreen> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _guardando = false;

  Future<void> _guardar() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ApodoService().elegirApodo(_ctrl.text);
      // No hace falta navegar manualmente: si esta pantalla se abrió desde el
      // AuthGate, el stream del documento de usuario avanza solo a HomeShell
      // apenas detecta el apodo guardado. Si se abrió desde Perfil, la
      // cerramos nosotros mismos.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.badge_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text(
                '¡Elige tu apodo!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Así te verán los demás en los resúmenes y en tu perfil, en vez de tu correo. '
                'Puedes cambiarlo más adelante desde Perfil.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                maxLength: 20,
                autofocus: true,
                onSubmitted: (_) => _guardar(),
                decoration: InputDecoration(
                  labelText: 'Apodo',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}