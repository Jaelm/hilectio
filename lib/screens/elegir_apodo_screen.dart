import 'package:flutter/material.dart';
import '../services/apodo_service.dart';

/// Pantalla para elegir (o cambiar) el apodo con el que el usuario se
/// identifica ante los demás, en vez de su correo. Se usa tanto como paso
/// obligatorio la primera vez (ver AuthGate en main.dart) como desde el
/// botón "Cambiar apodo" en Perfil — en ese segundo caso [esCambio] debe ser
/// true, para avisar del costo en tokens antes de guardar (la primera vez
/// siempre es gratis).
class ElegirApodoScreen extends StatefulWidget {
  final bool esCambio;
  final String? apodoActual;

  const ElegirApodoScreen({super.key, this.esCambio = false, this.apodoActual});

  @override
  State<ElegirApodoScreen> createState() => _ElegirApodoScreenState();
}

class _ElegirApodoScreenState extends State<ElegirApodoScreen> {
  late final TextEditingController _ctrl;
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.esCambio ? (widget.apodoActual ?? '') : '');
  }

  Future<void> _confirmarYGuardar() async {
    if (_ctrl.text.trim().isEmpty) return;

    // Si es un cambio real de apodo (no la primera vez, y realmente distinto
    // al actual) se confirma el costo antes de intentar guardar, para que
    // el usuario no se lleve la sorpresa después.
    final cambiaDeVerdad =
        widget.esCambio && _ctrl.text.trim().toLowerCase() != (widget.apodoActual ?? '').toLowerCase();
    if (cambiaDeVerdad) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Cambiar apodo?'),
          content: Text('Cambiar tu apodo cuesta $costoCambioApodo tokens.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cambiar')),
          ],
        ),
      );
      if (confirmar != true) return;
    }

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
              Text(
                widget.esCambio ? 'Cambia tu apodo' : '¡Elige tu apodo!',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                widget.esCambio
                    ? 'Puedes cambiarlo cuando quieras, pero a partir del primero cada '
                        'cambio cuesta $costoCambioApodo tokens.'
                    : 'Así te verán los demás en los resúmenes y en tu perfil, en vez de tu '
                        'correo. Puedes cambiarlo más adelante desde Perfil.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                maxLength: 20,
                autofocus: true,
                onSubmitted: (_) => _confirmarYGuardar(),
                decoration: InputDecoration(
                  labelText: 'Apodo',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _guardando ? null : _confirmarYGuardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.esCambio ? 'Guardar' : 'Continuar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}