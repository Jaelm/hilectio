import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lectura.dart';
import 'add_edit_lectura_screen.dart';
import 'resumenes_screen.dart';
import '../services/notification_service.dart';

String _hashPin(String pin) {
  return sha256.convert(utf8.encode(pin)).toString();
}

class BovedaScreen extends StatefulWidget {
  const BovedaScreen({super.key});

  @override
  State<BovedaScreen> createState() => _BovedaScreenState();
}

class _BovedaScreenState extends State<BovedaScreen> {
  bool _desbloqueado = false;
  bool _cargando = true;
  String? _pinHashGuardado;

  @override
  void initState() {
    super.initState();
    _cargarPin();
  }

  Future<void> _cargarPin() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    setState(() {
      _pinHashGuardado = doc.data()?['pinBovedaHash'] as String?;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_desbloqueado) {
      return _pinHashGuardado == null
          ? _CrearPinView(onCreado: (hash) {
              setState(() {
                _pinHashGuardado = hash;
                _desbloqueado = true;
              });
            })
          : _IngresarPinView(
              pinHashGuardado: _pinHashGuardado!,
              onCorrecto: () => setState(() => _desbloqueado = true),
            );
    }
    return const _ListaBoveda();
  }
}

class _CrearPinView extends StatefulWidget {
  final void Function(String hash) onCreado;
  const _CrearPinView({required this.onCreado});

  @override
  State<_CrearPinView> createState() => _CrearPinViewState();
}

class _CrearPinViewState extends State<_CrearPinView> {
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  String? _error;
  bool _guardando = false;

  Future<void> _guardar() async {
    final pin = _pinCtrl.text.trim();
    final confirm = _pinConfirmCtrl.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'El PIN debe tener 4 dígitos');
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'Los PIN no coinciden');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final hash = _hashPin(pin);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance.collection('usuarios').doc(uid).set(
      {'pinBovedaHash': hash},
      SetOptions(merge: true),
    );
    if (mounted) widget.onCreado(hash);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear PIN de la bóveda')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Crea un PIN de 4 dígitos para proteger tu bóveda +18.'),
            const SizedBox(height: 20),
            TextField(
              controller: _pinCtrl,
              decoration: const InputDecoration(labelText: 'PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            TextField(
              controller: _pinConfirmCtrl,
              decoration: const InputDecoration(labelText: 'Confirma el PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando ? const CircularProgressIndicator() : const Text('Crear PIN'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IngresarPinView extends StatefulWidget {
  final String pinHashGuardado;
  final VoidCallback onCorrecto;
  const _IngresarPinView({required this.pinHashGuardado, required this.onCorrecto});

  @override
  State<_IngresarPinView> createState() => _IngresarPinViewState();
}

class _IngresarPinViewState extends State<_IngresarPinView> {
  final _pinCtrl = TextEditingController();
  String? _error;

  void _verificar() {
    final hash = _hashPin(_pinCtrl.text.trim());
    if (hash == widget.pinHashGuardado) {
      widget.onCorrecto();
    } else {
      setState(() => _error = 'PIN incorrecto');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bóveda +18')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 16),
            TextField(
              controller: _pinCtrl,
              decoration: const InputDecoration(labelText: 'Ingresa tu PIN'),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _verificar(),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _verificar, child: const Text('Desbloquear')),
          ],
        ),
      ),
    );
  }
}

class _ListaBoveda extends StatefulWidget {
  const _ListaBoveda();

  @override
  State<_ListaBoveda> createState() => _ListaBovedaState();
}

class _ListaBovedaState extends State<_ListaBoveda> {
  String _filtro = 'leyendo';

  Future<void> _abrirLink(BuildContext context, String link) async {
    if (link.trim().isEmpty) return;
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el link')),
        );
      }
    }
  }

  Future<void> _cambiarEstado(String uid, String id, String nuevoEstado) async {
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .doc(id)
        .update({'estado': nuevoEstado});
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final stream = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Bóveda +18')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: estadosLectura.entries.map((e) {
                  final seleccionado = _filtro == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: seleccionado,
                      onSelected: (_) => setState(() => _filtro = e.key),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                final lecturas = docs
                    .map((d) => Lectura.fromDoc(d))
                    .where((l) => l.esAdulto && l.estado == _filtro)
                    .toList();
                if (lecturas.isEmpty) {
                  return Center(
                    child: Text(
                      'No tienes lecturas +18 marcadas como "${estadosLectura[_filtro]}".',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: lecturas.length,
                  itemBuilder: (context, i) {
                    final l = lecturas[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(l.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${l.tipo} · Cap. ${l.capituloActual} · ${l.plataforma}'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'abrir') _abrirLink(context, l.link);
                            if (v == 'editar') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => AddEditLecturaScreen(lectura: l)),
                              );
                            }
                            if (v == 'eliminar') {
                              await FirebaseFirestore.instance
                                  .collection('usuarios')
                                  .doc(uid)
                                  .collection('lecturas')
                                  .doc(l.id)
                                  .delete();
                              await NotificationService().cancelar(l.id);
                            }
                            if (v == 'resumenes') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResumenesScreen(
                                    tituloObra: l.titulo,
                                    capituloSugerido: l.capituloActual,
                                  ),
                                ),
                              );
                            }
                            if (estadosLectura.containsKey(v) && v != l.estado) {
                              _cambiarEstado(uid, l.id, v);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'abrir', child: Text('Abrir link')),
                            const PopupMenuItem(value: 'editar', child: Text('Editar')),
                            const PopupMenuItem(value: 'resumenes', child: Text('Resúmenes')),
                            const PopupMenuDivider(),
                            ...estadosLectura.entries
                                .where((e) => e.key != l.estado)
                                .map((e) => PopupMenuItem(
                                      value: e.key,
                                      child: Text('Marcar como ${e.value}'),
                                    )),
                            const PopupMenuDivider(),
                            const PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
                          ],
                        ),
                        onTap: () => _abrirLink(context, l.link),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}