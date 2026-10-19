import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/lectura.dart';
import '../services/notification_service.dart';

class AddEditLecturaScreen extends StatefulWidget {
  final Lectura? lectura; // null = crear nueva, no-null = editar

  const AddEditLecturaScreen({super.key, this.lectura});

  @override
  State<AddEditLecturaScreen> createState() => _AddEditLecturaScreenState();
}

class _AddEditLecturaScreenState extends State<AddEditLecturaScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _tituloCtrl;
  late TextEditingController _plataformaCtrl;
  late TextEditingController _capituloCtrl;
  late TextEditingController _linkCtrl;
  late TextEditingController _frecuenciaCtrl;
  String _tipo = 'Manhwa';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final l = widget.lectura;
    _tituloCtrl = TextEditingController(text: l?.titulo ?? '');
    _plataformaCtrl = TextEditingController(text: l?.plataforma ?? '');
    _capituloCtrl = TextEditingController(text: l?.capituloActual ?? '');
    _linkCtrl = TextEditingController(text: l?.link ?? '');
    _frecuenciaCtrl = TextEditingController(text: (l?.frecuenciaDias ?? 7).toString());
    if (l != null) _tipo = l.tipo;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final coleccion = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas');

    final datos = {
      'titulo': _tituloCtrl.text.trim(),
      'tipo': _tipo,
      'plataforma': _plataformaCtrl.text.trim(),
      'capituloActual': _capituloCtrl.text.trim(),
      'link': _linkCtrl.text.trim(),
      'frecuenciaDias': int.tryParse(_frecuenciaCtrl.text.trim()) ?? 7,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    try {
      String id;
      if (widget.lectura == null) {
        final doc = await coleccion.add(datos);
        id = doc.id;
      } else {
        id = widget.lectura!.id;
        await coleccion.doc(id).update(datos);
      }

      await NotificationService().programarRecordatorio(
        lecturaId: id,
        titulo: _tituloCtrl.text.trim(),
        fechaBase: DateTime.now(),
        frecuenciaDias: int.tryParse(_frecuenciaCtrl.text.trim()) ?? 7,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lectura == null ? 'Nueva lectura' : 'Editar lectura'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _tituloCtrl,
                  decoration: const InputDecoration(labelText: 'Título'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un título' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'Manhwa', child: Text('Manhwa')),
                    DropdownMenuItem(value: 'Manga', child: Text('Manga')),
                    DropdownMenuItem(value: 'Manhua', child: Text('Manhua')),
                    DropdownMenuItem(value: 'Libro', child: Text('Libro')),
                    DropdownMenuItem(value: 'Otro', child: Text('Otro')),
                  ],
                  onChanged: (v) => setState(() => _tipo = v ?? 'Manhwa'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _plataformaCtrl,
                  decoration: const InputDecoration(labelText: 'Plataforma (ej. MangaDex)'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _capituloCtrl,
                  decoration: const InputDecoration(labelText: 'Capítulo donde te quedaste'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _linkCtrl,
                  decoration: const InputDecoration(labelText: 'Link del último capítulo'),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _frecuenciaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cada cuántos días se actualiza',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _guardar,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}