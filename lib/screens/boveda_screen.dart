import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lectura.dart';
import 'add_edit_lectura_screen.dart';
import 'obra_detalle_screen.dart';
import 'resumenes_screen.dart';
import '../services/notification_service.dart';
import '../services/logros_service.dart';
import '../services/obra_service.dart';

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
  bool _reseteandoPin = false;
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
      if (_pinHashGuardado == null || _reseteandoPin) {
        return _CrearPinView(
          esReinicio: _reseteandoPin,
          onCreado: (hash) {
            setState(() {
              _pinHashGuardado = hash;
              _desbloqueado = true;
              _reseteandoPin = false;
            });
          },
        );
      }
      return _IngresarPinView(
        pinHashGuardado: _pinHashGuardado!,
        onCorrecto: () => setState(() => _desbloqueado = true),
        onOlvidePin: () => setState(() => _reseteandoPin = true),
      );
    }
    return const _ListaBoveda();
  }
}

class _CrearPinView extends StatefulWidget {
  final void Function(String hash) onCreado;
  final bool esReinicio;
  const _CrearPinView({required this.onCreado, this.esReinicio = false});

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
      appBar: AppBar(
        title: Text(widget.esReinicio ? 'Nuevo PIN de la bóveda' : 'Crear PIN de la bóveda'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.esReinicio
                  ? 'Pon un PIN nuevo de 4 dígitos para tu bóveda +18.'
                  : 'Crea un PIN de 4 dígitos para proteger tu bóveda +18.',
            ),
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
              child: _guardando
                  ? const CircularProgressIndicator()
                  : Text(widget.esReinicio ? 'Guardar PIN nuevo' : 'Crear PIN'),
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
  final VoidCallback onOlvidePin;
  const _IngresarPinView({
    required this.pinHashGuardado,
    required this.onCorrecto,
    required this.onOlvidePin,
  });

  @override
  State<_IngresarPinView> createState() => _IngresarPinViewState();
}

class _IngresarPinViewState extends State<_IngresarPinView> {
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _verificandoContrasena = false;

  void _verificar() {
    final hash = _hashPin(_pinCtrl.text.trim());
    if (hash == widget.pinHashGuardado) {
      widget.onCorrecto();
    } else {
      setState(() => _error = 'PIN incorrecto');
    }
  }

  /// No se puede "mandar" el PIN olvidado (solo se guarda su hash, nunca en
  /// texto plano), así que para reiniciarlo se confirma identidad con la
  /// contraseña de la cuenta y ahí mismo se deja poner un PIN nuevo: sin
  /// depender de un correo ni de infraestructura extra.
  Future<void> _olvidePin() async {
    final passCtrl = TextEditingController();
    String? errorDialog;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('¿Olvidaste tu PIN?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Confirma la contraseña de tu cuenta para poner un PIN nuevo.'),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña de tu cuenta'),
              ),
              if (errorDialog != null) ...[
                const SizedBox(height: 8),
                Text(errorDialog!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final email = FirebaseAuth.instance.currentUser?.email;
                if (email == null || passCtrl.text.isEmpty) return;
                setStateDialog(() => errorDialog = null);
                try {
                  final cred = EmailAuthProvider.credential(email: email, password: passCtrl.text);
                  await FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(cred);
                  if (context.mounted) Navigator.pop(context, true);
                } on FirebaseAuthException catch (e) {
                  setStateDialog(() => errorDialog = e.message ?? 'Contraseña incorrecta');
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    if (confirmado == true) widget.onOlvidePin();
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
            TextButton(
              onPressed: _verificandoContrasena ? null : _olvidePin,
              child: const Text('¿Olvidaste tu PIN?'),
            ),
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

  Future<void> _cambiarEstado(String uid, String id, String nuevoEstado, Lectura l) async {
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .doc(id)
        .update({'estado': nuevoEstado});
    await ObraService().actualizarResumenLector(
      tituloLectura: l.titulo,
      tipo: l.tipo,
      estado: nuevoEstado,
      plataforma: l.plataforma,
      capituloActual: l.capituloActual,
      link: l.link,
    );
  }

  Future<void> _compartirEstado(BuildContext context, Lectura l) async {
    // ignore: deprecated_member_use
    await Share.share(
      'Estoy ${estadosLectura[l.estado]?.toLowerCase() ?? 'leyendo'} '
      '"${l.titulo}" (cap. ${l.capituloActual}) en Hilectio 📖',
    );
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final logros = await LogrosService().registrarCompartido(uid);
    if (logros.isNotEmpty && context.mounted) {
      mostrarLogrosDesbloqueados(context, logros);
    }
  }

  /// Atajo rápido para cuando te quedaste en otro capítulo o el link dejó de
  /// servir (igual que en Biblioteca): evita tener que abrir el formulario
  /// completo de "Editar" solo para actualizar esto.
  Future<void> _actualizarProgreso(BuildContext context, String uid, Lectura l) async {
    final linkCtrl = TextEditingController(text: l.link);
    final capCtrl = TextEditingController(text: l.capituloActual);
    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizar progreso'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: capCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Capítulo donde te quedaste'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: linkCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link del capítulo'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              {'link': linkCtrl.text.trim(), 'capitulo': capCtrl.text.trim()},
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (resultado == null) return;
    final nuevoLink = resultado['link'] ?? '';
    final nuevoCap = resultado['capitulo'] ?? '';

    final cambioLink = nuevoLink.isNotEmpty && nuevoLink != l.link;
    final cambioCap = nuevoCap.isNotEmpty && nuevoCap != l.capituloActual;
    if (!cambioLink && !cambioCap) return;

    final datos = <String, dynamic>{'actualizadoEn': FieldValue.serverTimestamp()};
    if (cambioLink) datos['link'] = nuevoLink;
    if (cambioCap) datos['capituloActual'] = nuevoCap;

    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .doc(l.id)
        .update(datos);

    if (cambioCap) {
      await ObraService().actualizarCapituloMaximo(
        tituloLectura: l.titulo,
        tipo: l.tipo,
        capituloTexto: nuevoCap,
        link: cambioLink ? nuevoLink : l.link,
      );
    }
    // Se refresca el resumen del lector aunque solo haya cambiado el link
    // (sin cambiar de capítulo): es la fuente de donde sale el link que se
    // le sugiere a otros al añadir esta obra desde Descubrir, así que debe
    // quedar al día incluso si el capítulo no se tocó.
    if (cambioCap || cambioLink) {
      await ObraService().actualizarResumenLector(
        tituloLectura: l.titulo,
        tipo: l.tipo,
        estado: l.estado,
        plataforma: l.plataforma,
        capituloActual: cambioCap ? nuevoCap : l.capituloActual,
        link: cambioLink ? nuevoLink : l.link,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Progreso actualizado')),
      );
    }
  }

  /// Imagen genérica de portada (una foto de animal, sin relación con la
  /// obra) asignada según el título. Si por algo el asset no carga, cae al
  /// ícono de respaldo en vez de romper la pantalla.
  Widget _portadaObra(BuildContext context, String titulo) => Image.asset(
        rutaPortadaGenerica(titulo),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderPortada(context),
      );

  Widget _placeholderPortada(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.menu_book_outlined,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          size: 32,
        ),
      );

  Widget _tarjetaLectura(BuildContext context, String uid, Lectura l) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('obras').doc(idObra(l.titulo, l.tipo)).get(),
      builder: (context, obraSnap) {
        final obraData = (obraSnap.data?.data()) ?? <String, dynamic>{};
        final capituloMaximo = (obraData['capituloMaximo'] as num?)?.toInt();
        final total = capituloMaximo?.toString();
        final etiquetaProgreso =
            (total != null && total.isNotEmpty) ? '${l.capituloActual} / $total' : 'Cap. ${l.capituloActual}';

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ObraDetalleScreen(titulo: l.titulo, tipo: l.tipo)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _portadaObra(context, l.titulo),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Material(
                        color: Colors.black38,
                        shape: const CircleBorder(),
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                          onSelected: (v) {
                            if (v == 'abrir') _abrirLink(context, l.link);
                            if (v == 'actualizar_link') _actualizarProgreso(context, uid, l);
                            if (v == 'editar') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => AddEditLecturaScreen(lectura: l)),
                              );
                            }
                            if (v == 'eliminar') {
                              FirebaseFirestore.instance
                                  .collection('usuarios')
                                  .doc(uid)
                                  .collection('lecturas')
                                  .doc(l.id)
                                  .delete();
                              NotificationService().cancelar(l.id);
                              ObraService().eliminarResumenLector(l.titulo, l.tipo);
                            }
                            if (v == 'compartir') _compartirEstado(context, l);
                            if (v == 'resumenes') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResumenesScreen(
                                    tituloObra: l.titulo,
                                    tipoObra: l.tipo,
                                    capituloSugerido: l.capituloActual,
                                  ),
                                ),
                              );
                            }
                            if (estadosLectura.containsKey(v) && v != l.estado) {
                              _cambiarEstado(uid, l.id, v, l);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'abrir', child: Text('Abrir link')),
                            const PopupMenuItem(value: 'actualizar_link', child: Text('Actualizar progreso')),
                            const PopupMenuItem(value: 'editar', child: Text('Editar')),
                            const PopupMenuItem(value: 'resumenes', child: Text('Resúmenes')),
                            const PopupMenuItem(value: 'compartir', child: Text('Compartir estado')),
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
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          etiquetaProgreso,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 32,
                child: Text(
                  l.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 18,
                    childAspectRatio: 0.52,
                  ),
                  itemCount: lecturas.length,
                  itemBuilder: (context, i) => _tarjetaLectura(context, uid, lecturas[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}