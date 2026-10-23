import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../services/resumenes_service.dart';
import '../services/logros_service.dart';
import '../services/obra_service.dart' show normalizarTitulo;
import 'perfil_publico_screen.dart';

class ResumenesScreen extends StatefulWidget {
  final String tituloObra;
  final String capituloSugerido;

  const ResumenesScreen({
    super.key,
    required this.tituloObra,
    this.capituloSugerido = '',
  });

  @override
  State<ResumenesScreen> createState() => _ResumenesScreenState();
}

class _ResumenesScreenState extends State<ResumenesScreen> {
  final _servicio = ResumenesService();

  Future<void> _abrirFormulario() async {
    final capituloCtrl = TextEditingController(text: widget.capituloSugerido);
    final textoCtrl = TextEditingController();
    bool contieneSpoiler = false;
    bool enviando = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Nuevo resumen', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: capituloCtrl,
                      decoration: const InputDecoration(labelText: 'Capítulo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textoCtrl,
                      decoration: const InputDecoration(labelText: 'Resumen'),
                      maxLines: 5,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Contiene spoiler importante'),
                      value: contieneSpoiler,
                      onChanged: (v) => setModalState(() => contieneSpoiler = v ?? false),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nada de groserías, amenazas ni spoilers sin marcar: si el filtro '
                      'automático detecta algo raro, el resumen queda oculto hasta que '
                      'el admin lo revise. Si confirma que viola las reglas, se penaliza '
                      'con -$penalizacionViolacion tokens.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: enviando
                          ? null
                          : () async {
                              if (textoCtrl.text.trim().isEmpty) return;
                              setModalState(() => enviando = true);
                              try {
                                final resultado = await _servicio.crearResumen(
                                  tituloObra: widget.tituloObra,
                                  capitulo: capituloCtrl.text,
                                  texto: textoCtrl.text,
                                  contieneSpoiler: contieneSpoiler,
                                );
                                final sospechoso = resultado['sospechoso'] == true;
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        sospechoso
                                            ? 'Resumen enviado, pero quedó en revisión por el filtro automático.'
                                            : '¡Resumen publicado!',
                                      ),
                                    ),
                                  );
                                  final logros = List<String>.from(
                                    resultado['logrosDesbloqueados'] ?? [],
                                  );
                                  if (logros.isNotEmpty) {
                                    mostrarLogrosDesbloqueados(context, logros);
                                  }
                                }
                              } catch (e) {
                                setModalState(() => enviando = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e.toString().replaceFirst('Exception: ', ''),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                      child: enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Publicar'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final obraId = normalizarTitulo(widget.tituloObra);
    return Scaffold(
      appBar: AppBar(title: Text('Resúmenes: ${widget.tituloObra}')),
      body: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _servicio.resumenesDeObra(widget.tituloObra),
        builder: (context, snap) {
          final docs = snap.data ?? [];
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Todavía no hay resúmenes para esta obra.\nSé el primero en escribir uno.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              return _ResumenCard(
                obraId: obraId,
                tituloObra: widget.tituloObra,
                resumenId: doc.id,
                capitulo: data['capitulo'] ?? '',
                texto: data['texto'] ?? '',
                contieneSpoiler: data['contieneSpoiler'] == true,
                votos: (data['votosPositivos'] as num?)?.toInt() ?? 0,
                esPropio: data['uid'] == FirebaseAuth.instance.currentUser?.uid,
                autorUid: data['uid'] ?? '',
                apodoAutor: data['apodoAutor'] as String? ?? 'Usuario',
                servicio: _servicio,
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirFormulario,
        icon: const Icon(Icons.edit_note),
        label: const Text('Escribir resumen'),
      ),
    );
  }
}

class _ResumenCard extends StatefulWidget {
  final String obraId;
  final String tituloObra;
  final String resumenId;
  final String capitulo;
  final String texto;
  final bool contieneSpoiler;
  final int votos;
  final bool esPropio;
  final String autorUid;
  final String apodoAutor;
  final ResumenesService servicio;

  const _ResumenCard({
    required this.obraId,
    required this.tituloObra,
    required this.resumenId,
    required this.capitulo,
    required this.texto,
    required this.contieneSpoiler,
    required this.votos,
    required this.esPropio,
    required this.autorUid,
    required this.apodoAutor,
    required this.servicio,
  });

  @override
  State<_ResumenCard> createState() => _ResumenCardState();
}

class _ResumenCardState extends State<_ResumenCard> {
  bool _revelado = false;
  bool _votando = false;

  Future<void> _compartir() async {
    final texto = widget.contieneSpoiler && !_revelado
        ? '¡Hay un resumen nuevo de "${widget.tituloObra}" (cap. ${widget.capitulo}) en Hilectio! 📖 (contiene spoiler, cuidado)'
        : 'Resumen de "${widget.tituloObra}" (cap. ${widget.capitulo}) desde Hilectio:\n\n"${widget.texto}"';
    // ignore: deprecated_member_use
    await Share.share(texto);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final logros = await LogrosService().registrarCompartido(uid);
    if (logros.isNotEmpty && mounted) {
      mostrarLogrosDesbloqueados(context, logros);
    }
  }

  @override
  Widget build(BuildContext context) {
    final oculto = widget.contieneSpoiler && !_revelado;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: widget.autorUid.isEmpty
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PerfilPublicoScreen(uid: widget.autorUid),
                        ),
                      ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    widget.apodoAutor,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Chip(
                  label: Text('Cap. ${widget.capitulo}', style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                if (widget.contieneSpoiler) ...[
                  const SizedBox(width: 6),
                  const Chip(
                    label: Text('Spoiler', style: TextStyle(fontSize: 12)),
                    backgroundColor: Color(0xFFFFE0D9),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (oculto)
              GestureDetector(
                onTap: () => setState(() => _revelado = true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('Contiene spoiler — toca para verlo'),
                  ),
                ),
              )
            else
              Text(widget.texto),
            const SizedBox(height: 10),
            if (!widget.esPropio)
              StreamBuilder<bool>(
                stream: widget.servicio.yaVoteStream(
                  obraId: widget.obraId,
                  resumenId: widget.resumenId,
                ),
                builder: (context, votoSnap) {
                  final votado = votoSnap.data ?? false;
                  return Row(
                    children: [
                      IconButton(
                        onPressed: _votando
                            ? null
                            : () async {
                                setState(() => _votando = true);
                                await widget.servicio.alternarVoto(
                                  obraId: widget.obraId,
                                  resumenId: widget.resumenId,
                                );
                                if (mounted) setState(() => _votando = false);
                              },
                        icon: Icon(
                          votado ? Icons.thumb_up : Icons.thumb_up_outlined,
                          color: votado ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                      Text('${widget.votos}'),
                      const Spacer(),
                      IconButton(
                        onPressed: _compartir,
                        icon: const Icon(Icons.share_outlined, size: 20),
                        tooltip: 'Compartir',
                      ),
                    ],
                  );
                },
              )
            else
              Row(
                children: [
                  const Icon(Icons.thumb_up_outlined, size: 20, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('${widget.votos}', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(width: 8),
                  const Text('(tu resumen)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const Spacer(),
                  IconButton(
                    onPressed: _compartir,
                    icon: const Icon(Icons.share_outlined, size: 20),
                    tooltip: 'Compartir',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}