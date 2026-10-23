import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lectura.dart';
import 'add_edit_lectura_screen.dart';
import 'resumenes_screen.dart';
import '../services/notification_service.dart';
import '../services/logros_service.dart';
import '../services/obra_service.dart';

class BibliotecaScreen extends StatefulWidget {
  const BibliotecaScreen({super.key});

  @override
  State<BibliotecaScreen> createState() => _BibliotecaScreenState();
}

class _BibliotecaScreenState extends State<BibliotecaScreen> {
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

  Future<void> _eliminar(String uid, String id, String titulo) async {
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas')
        .doc(id)
        .delete();
    await NotificationService().cancelar(id);
    await ObraService().eliminarResumenLector(titulo);
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
      estado: nuevoEstado,
      plataforma: l.plataforma,
      capituloActual: l.capituloActual,
      link: l.link,
    );
  }

  /// Atajo rápido para cuando te quedaste en otro capítulo o el link dejó de
  /// servir (algunos sitios como Olympus cambian el link del mismo capítulo
  /// todos los días): evita tener que abrir el formulario completo de
  /// "Editar" solo para actualizar esto.
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
      future: FirebaseFirestore.instance.collection('obras').doc(normalizarTitulo(l.titulo)).get(),
      builder: (context, obraSnap) {
        final obraData = (obraSnap.data?.data()) ?? <String, dynamic>{};
        final imagenUrl = obraData['imagenUrl'] as String?;
        // El "total" se calcula solo: es el capítulo más avanzado que
        // cualquier usuario haya guardado para esta obra (ver
        // ObraService.actualizarCapituloMaximo), no un dato llenado a mano.
        final capituloMaximo = (obraData['capituloMaximo'] as num?)?.toInt();
        final total = capituloMaximo?.toString();
        final etiquetaProgreso =
            (total != null && total.isNotEmpty) ? '${l.capituloActual} / $total' : 'Cap. ${l.capituloActual}';

        return GestureDetector(
          onTap: () => _abrirLink(context, l.link),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: (imagenUrl != null && imagenUrl.isNotEmpty)
                          ? Image.network(
                              imagenUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) =>
                                  progress == null ? child : _placeholderPortada(context),
                              errorBuilder: (_, __, ___) => _placeholderPortada(context),
                            )
                          : _placeholderPortada(context),
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
                            if (v == 'eliminar') _eliminar(uid, l.id, l.titulo);
                            if (v == 'compartir') _compartirEstado(context, l);
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
              // Alto fijo (en vez de dejar que el texto decida cuánto medir):
              // así el área de la portada mide siempre lo mismo sin importar
              // si el título ocupa 1 o 2 líneas.
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
        .orderBy('actualizadoEn', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Biblioteca')),
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
                    .where((l) => !l.esAdulto && l.estado == _filtro)
                    .toList();
                if (lecturas.isEmpty) {
                  return Center(
                    child: Text(
                      'No tienes lecturas marcadas como "${estadosLectura[_filtro]}".',
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditLecturaScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}