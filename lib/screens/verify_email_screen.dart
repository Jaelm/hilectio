import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Pantalla que se muestra mientras el usuario no haya confirmado su correo.
/// Revisa automáticamente cada pocos segundos por si ya verificó desde el
/// link que le llegó al correo, y también deja reenviarlo o chequear a mano.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _enviando = false;
  bool _verificando = false;
  String? _mensaje;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _verificar(silencioso: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reenviar() async {
    setState(() {
      _enviando = true;
      _mensaje = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        setState(() => _mensaje = 'Correo reenviado. Revisa tu bandeja (y la carpeta de spam).');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _mensaje = e.code == 'too-many-requests'
            ? 'Espera un poco antes de pedir otro correo.'
            : (e.message ?? 'No se pudo enviar el correo.'));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _verificar({bool silencioso = false}) async {
    if (!silencioso) setState(() => _verificando = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {
      // Sin conexión u otro error pasajero: se reintenta en el próximo tick.
    }
    if (!mounted) return;
    if (!silencioso) {
      setState(() {
        _verificando = false;
        if (FirebaseAuth.instance.currentUser?.emailVerified != true) {
          _mensaje = 'Todavía no detectamos la verificación. ¿Ya abriste el link del correo?';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final correo = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text(
                'Confirma tu correo',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Te enviamos un enlace de verificación a $correo. Ábrelo y vuelve aquí (esta pantalla se actualiza sola).',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_mensaje != null) ...[
                Text(
                  _mensaje!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _verificando ? null : () => _verificar(),
                child: _verificando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Ya verifiqué mi correo'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _enviando ? null : _reenviar,
                child: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Reenviar correo de verificación'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}