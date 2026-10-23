import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/lectura.dart';
import '../services/notification_service.dart';
import '../services/tokens_service.dart';
import '../services/obra_service.dart';
import '../services/logros_service.dart';
import '../services/plataformas_service.dart';

/// Sitios de lectura conocidos por generar un link distinto para el mismo
/// capítulo cada cierto tiempo (ej. cada día), para avisarle al usuario que
/// probablemente tenga que actualizar el link pronto. Agrega aquí otros
/// sitios si aparecen más casos como este.
const Map<String, String> _sitiosDeLinkInestable = {
  'olympusxyz.com':
      'Olympus genera un link nuevo para el mismo capítulo cada día. Es muy '
      'probable que este link deje de funcionar en 24 horas o menos.',
};

/// Si [link] pertenece a un sitio de [_sitiosDeLinkInestable], devuelve su
/// mensaje de aviso; si no, null.
String? _avisoLinkInestable(String link) {
  final texto = link.toLowerCase();
  for (final entry in _sitiosDeLinkInestable.entries) {
    if (texto.contains(entry.key)) return entry.value;
  }
  return null;
}

class AddEditLecturaScreen extends StatefulWidget {
  final Lectura? lectura;

  /// Para precargar el formulario al agregar una obra desde Descubrir (ver
  /// ObraDetalleScreen): título/tipo de la obra ya elegida y el estado que
  /// el usuario escogió en el selector (leyendo/pendiente/...). Se ignoran
  /// si [lectura] no es null (modo edición).
  final String? tituloInicial;
  final String? tipoInicial;
  final String? estadoInicial;

  /// Link del capítulo más alto que ya tiene registrado la comunidad para
  /// esta obra (si existe), para que el usuario nuevo pueda ir directo a
  /// seguir leyendo desde ahí en vez de buscarlo de cero.
  final String? linkInicial;

  const AddEditLecturaScreen({
    super.key,
    this.lectura,
    this.tituloInicial,
    this.tipoInicial,
    this.estadoInicial,
    this.linkInicial,
  });

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
  final Map<String, TextEditingController> _obraCtrls = {
    for (final campo in camposObra.keys) campo: TextEditingController(),
  };
  String _tipo = 'Manhwa';
  String _estadoLectura = 'leyendo';
  bool _esAdulto = false;
  bool _loading = false;
  bool _cargandoCamposObra = false;

  /// `Autocomplete` exige pasar un FocusNode propio cuando se le pasa un
  /// `textEditingController` propio (si no, lanza un assertion error), así
  /// que se crean explícitos en vez de dejar que los genere internamente.
  final FocusNode _tituloFocus = FocusNode();
  final FocusNode _plataformaFocus = FocusNode();

  /// Sugerencias para autocompletar: títulos ya registrados en el catálogo
  /// y plataformas ya usadas (propias + de la comunidad, sin +18 de otros).
  List<String> _titulosConocidos = [];
  List<String> _plataformasConocidas = [];

  /// Campos de la obra que ya están validados (campo -> valor) y por lo
  /// tanto se muestran bloqueados en vez de como un formulario editable.
  Map<String, dynamic> _camposBloqueados = {};

  /// Fecha elegida con el selector para cada campo de tipo fecha
  /// (ej. 'fechaPublicacion' -> DateTime). Es la fuente real que se envía;
  /// el texto del controller solo es para mostrarla formateada.
  final Map<String, DateTime?> _fechasSeleccionadas = {
    for (final campo in camposDeFecha) campo: null,
  };

  @override
  void initState() {
    super.initState();
    final l = widget.lectura;
    _tituloCtrl = TextEditingController(text: l?.titulo ?? widget.tituloInicial ?? '');
    _plataformaCtrl = TextEditingController(text: l?.plataforma ?? '');
    // Al añadir desde Descubrir no se asume que el usuario ya está en el
    // capítulo más alto que conoce la comunidad: se deja en 0 por defecto
    // y es él quien lo actualiza cuando sepa en cuál se quedó.
    _capituloCtrl = TextEditingController(
      text: l?.capituloActual ?? (widget.tituloInicial != null ? '0' : ''),
    );
    _linkCtrl = TextEditingController(text: l?.link ?? widget.linkInicial ?? '');
    _frecuenciaCtrl = TextEditingController(text: (l?.frecuenciaDias ?? 7).toString());
    _tituloFocus.addListener(() {
      if (!_tituloFocus.hasFocus) _cargarCamposBloqueados();
    });
    if (l != null) {
      _tipo = l.tipo;
      _esAdulto = l.esAdulto;
      _estadoLectura = l.estado;
      _cargarCamposBloqueados();
    } else {
      if (widget.tipoInicial != null) _tipo = widget.tipoInicial!;
      if (widget.estadoInicial != null) _estadoLectura = widget.estadoInicial!;
      if ((widget.tituloInicial ?? '').trim().isNotEmpty) _cargarCamposBloqueados();
    }
    _cargarSugerencias();
  }

  @override
  void dispose() {
    _tituloFocus.dispose();
    _plataformaFocus.dispose();
    super.dispose();
  }

  /// Trae los títulos ya registrados en el catálogo y las plataformas ya
  /// usadas (propias, +18 incluidas, más las de la comunidad que no son
  /// +18), para ofrecerlas como autocompletado. Si algo falla, el
  /// formulario sigue funcionando normal, solo sin sugerencias.
  Future<void> _cargarSugerencias() async {
    try {
      final obrasSnap = await FirebaseFirestore.instance.collection('obras').get();
      final titulos = obrasSnap.docs
          .map((d) => d.data()['tituloOriginal'] as String?)
          .whereType<String>()
          .where((t) => t.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      final plataformasMapa = <String, String>{};
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final propiasSnap = await FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .collection('lecturas')
            .get();
        for (final d in propiasSnap.docs) {
          final p = (d.data()['plataforma'] as String? ?? '').trim();
          if (p.isNotEmpty) plataformasMapa.putIfAbsent(p.toLowerCase(), () => p);
        }
      }
      final ranking = await PlataformasService().calcularRanking();
      for (final e in ranking) {
        plataformasMapa.putIfAbsent(e.clave, () => e.etiqueta);
      }

      if (!mounted) return;
      setState(() {
        _titulosConocidos = titulos;
        _plataformasConocidas = plataformasMapa.values.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      });
    } catch (_) {
      // Autocompletar es un extra: si falla, se sigue escribiendo a mano.
    }
  }

  /// Consulta si esta obra ya tiene campos validados y, de ser así, bloquea
  /// esos campos en el formulario (ya no se pueden volver a llenar/premiar).
  Future<void> _cargarCamposBloqueados() async {
    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) return;
    setState(() => _cargandoCamposObra = true);
    try {
      final campos = await ObraService().obtenerCamposValidados(titulo);
      if (!mounted) return;
      setState(() {
        _camposBloqueados = campos;
        for (final entry in campos.entries) {
          final ctrl = _obraCtrls[entry.key];
          if (ctrl != null) {
            ctrl.text = formatearValorCampo(entry.value, campo: entry.key);
          }
        }
      });
    } finally {
      if (mounted) setState(() => _cargandoCamposObra = false);
    }
  }

  Future<void> _elegirFecha(String campo) async {
    final ahora = DateTime.now();
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: _fechasSeleccionadas[campo] ?? DateTime(ahora.year - 5),
      firstDate: DateTime(1950),
      lastDate: ahora,
      helpText: etiquetaCampo(campo, _tipo),
    );
    if (seleccionada != null) {
      setState(() {
        _fechasSeleccionadas[campo] = seleccionada;
        _obraCtrls[campo]!.text = formatearFechaISOaDisplay(formatearFechaADisplayISO(seleccionada));
      });
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final coleccion = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('lecturas');

    final Map<String, dynamic> datos = {
      'titulo': _tituloCtrl.text.trim(),
      'tipo': _tipo,
      'plataforma': _plataformaCtrl.text.trim(),
      'capituloActual': _capituloCtrl.text.trim(),
      'link': _linkCtrl.text.trim(),
      'frecuenciaDias': int.tryParse(_frecuenciaCtrl.text.trim()) ?? 7,
      'esAdulto': _esAdulto,
      'estado': _estadoLectura,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };

    // Doc anterior tal cual estaba en Firestore (null si es una lectura
    // nueva); lo necesita LogrosService para detectar "reinició tras
    // terminar" y "avanzó 50+ capítulos en un día".
    Map<String, dynamic>? datosAnteriores;
    if (widget.lectura != null) {
      final snapAnterior = await coleccion.doc(widget.lectura!.id).get();
      datosAnteriores = snapAnterior.data();
    }
    final resultadoLogroLectura = await LogrosService().alGuardarLectura(
      uid: uid,
      anterior: datosAnteriores,
      nuevoCapituloTexto: _capituloCtrl.text.trim(),
      nuevoEstado: _estadoLectura,
    );
    datos.addAll(Map<String, dynamic>.from(resultadoLogroLectura['extra'] ?? {}));

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

      final estadoRacha = await TokensService().verificarRacha();
      bool salvarRacha = false;

      if (estadoRacha['estado'] == 'rota' && estadoRacha['puedeSalvar'] == true && mounted) {
        salvarRacha = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('¡Se te pasó un día!'),
                content: const Text(
                  'Puedes pagar 40 tokens para salvar tu racha, o dejar que se reinicie a día 1.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Reiniciar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Salvar (40 tokens)'),
                  ),
                ],
              ),
            ) ??
            false;
      }

      final resultado = await TokensService().confirmarActividad(salvarRacha: salvarRacha);

      if (mounted && resultado['cambio'] == true) {
        final recompensa = resultado['recompensa'];
        final racha = resultado['racha'];
        final rachaRota = resultado['rachaRota'] == true;
        final rachaSalvada = resultado['rachaSalvada'] == true;
        String mensaje;
        if (rachaSalvada) {
          mensaje = '¡Racha salvada! 🔥 Racha de $racha días. +$recompensa tokens (-40 por salvarla)';
        } else if (rachaRota) {
          mensaje = 'Se reinició tu racha. +$recompensa tokens (día 1)';
        } else {
          mensaje = '🔥 Racha de $racha días. +$recompensa tokens';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(duration: const Duration(seconds: 2), content: Text(mensaje)),
        );
        await Future.delayed(const Duration(milliseconds: 900));
      }

      // Solo se envían los campos que el usuario pudo editar: los que ya
      // estaban validados quedan bloqueados y no se vuelven a proponer.
      final valoresObra = {
        for (final entry in _obraCtrls.entries)
          if (!_camposBloqueados.containsKey(entry.key))
            entry.key: camposDeFecha.contains(entry.key)
                ? (_fechasSeleccionadas[entry.key] == null
                    ? ''
                    : formatearFechaADisplayISO(_fechasSeleccionadas[entry.key]!))
                : entry.value.text,
      };
      // Registra la obra en el catálogo público (pestaña Descubrir), +18
      // incluidas: esas aparecen igual, pero marcadas con un ícono, mientras
      // que quién la está leyendo sigue siendo privado (reglas de Firestore).
      await ObraService().registrarObra(
        _tituloCtrl.text.trim(),
        tipo: _tipo,
        esAdulto: _esAdulto,
      );
      await ObraService().actualizarCapituloMaximo(
        tituloLectura: _tituloCtrl.text.trim(),
        capituloTexto: _capituloCtrl.text.trim(),
        link: _linkCtrl.text.trim(),
      );

      // Mi propio "estoy leyendo esto" en la obra (ver ObraDetalleScreen):
      // si cambié el título, primero se borra la entrada de la obra vieja
      // para no quedar "leyendo" dos títulos distintos a la vez.
      final tituloAnterior = (datosAnteriores?['titulo'] as String?)?.trim();
      if (tituloAnterior != null &&
          tituloAnterior.isNotEmpty &&
          normalizarTitulo(tituloAnterior) != normalizarTitulo(_tituloCtrl.text.trim())) {
        await ObraService().eliminarResumenLector(tituloAnterior);
      }
      await ObraService().actualizarResumenLector(
        tituloLectura: _tituloCtrl.text.trim(),
        estado: _estadoLectura,
        plataforma: _plataformaCtrl.text.trim(),
        capituloActual: _capituloCtrl.text.trim(),
      );

      if (valoresObra.values.any((v) => v.trim().isNotEmpty)) {
        final resumenObra = await ObraService().enviarDatosObra(
          tituloLectura: _tituloCtrl.text.trim(),
          valores: valoresObra,
        );
        if (mounted) {
          final partes = <String>[];
          if ((resumenObra['autoValidadas'] ?? 0) > 0) {
            partes.add('${resumenObra['autoValidadas']} confirmado(s)');
          }
          if ((resumenObra['pendientes'] ?? 0) > 0) {
            partes.add('${resumenObra['pendientes']} en revisión');
          }
          if ((resumenObra['noCoinciden'] ?? 0) > 0) {
            partes.add('${resumenObra['noCoinciden']} no coincidió(eron)');
          }
          if ((resumenObra['tokensGanados'] ?? 0) > 0) {
            partes.add('+${resumenObra['tokensGanados']} tokens');
          }
          if (partes.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Datos de la obra: ${partes.join(', ')}')),
            );
            await Future.delayed(const Duration(milliseconds: 900));
          }
        }
      }

      await LogrosService().registrarInteraccion(uid);
      final logrosLectura = List<String>.from(resultadoLogroLectura['titulos'] ?? []);
      final logrosCompletos = await LogrosService().evaluarCompleto(uid);
      final todosLosLogros = {...logrosLectura, ...logrosCompletos}.toList();
      if (mounted && todosLosLogros.isNotEmpty) {
        mostrarLogrosDesbloqueados(context, todosLosLogros);
        await Future.delayed(const Duration(milliseconds: 600));
      }

      final avisoLink = _avisoLinkInestable(_linkCtrl.text.trim());
      if (avisoLink != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Aviso sobre este link'),
            content: Text(
              '$avisoLink\n\nCuando deje de funcionar, usa "Actualizar link" en '
              'el menú ⋮ de esta lectura en Biblioteca para pegar el link nuevo '
              'sin tener que editar todo de nuevo.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }

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
                Autocomplete<String>(
                  textEditingController: _tituloCtrl,
                  focusNode: _tituloFocus,
                  optionsMaxHeight: 220,
                  optionsBuilder: (TextEditingValue value) {
                    final texto = value.text.trim().toLowerCase();
                    if (texto.isEmpty) return const Iterable<String>.empty();
                    return _titulosConocidos.where((t) => t.toLowerCase().contains(texto)).take(8);
                  },
                  onSelected: (seleccion) {
                    _tituloCtrl.text = seleccion;
                    _cargarCamposBloqueados();
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Título'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un título' : null,
                    );
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: tiposLectura
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _tipo = v ?? 'Manhwa'),
                ),
                const SizedBox(height: 14),
                Autocomplete<String>(
                  textEditingController: _plataformaCtrl,
                  focusNode: _plataformaFocus,
                  optionsMaxHeight: 220,
                  optionsBuilder: (TextEditingValue value) {
                    final texto = value.text.trim().toLowerCase();
                    if (texto.isEmpty) return const Iterable<String>.empty();
                    return _plataformasConocidas.where((p) => p.toLowerCase().contains(texto)).take(8);
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Plataforma (ej. MangaDex)'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe la plataforma' : null,
                    );
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _capituloCtrl,
                  decoration: const InputDecoration(labelText: 'Capítulo donde te quedaste'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el capítulo' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _linkCtrl,
                  decoration: const InputDecoration(labelText: 'Link del último capítulo'),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Pega el link del capítulo';
                    final uri = Uri.tryParse(v.trim());
                    if (uri == null || !uri.hasScheme) return 'El link no parece válido';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _frecuenciaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cada cuántos días se actualiza',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Escribe cada cuántos días';
                    final n = int.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Debe ser un número mayor a 0';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _estadoLectura,
                  decoration: const InputDecoration(labelText: 'Marcador de lectura'),
                  items: estadosLectura.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _estadoLectura = v ?? 'leyendo'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Contenido +18'),
                  subtitle: const Text('Se oculta en Biblioteca y solo se ve en la Bóveda'),
                  value: _esAdulto,
                  onChanged: (v) => setState(() => _esAdulto = v),
                ),
                const SizedBox(height: 10),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Datos de la obra (opcional)'),
                  subtitle: Text(
                    _cargandoCamposObra
                        ? 'Buscando si esta obra ya tiene datos registrados…'
                        : 'Ayuda a otros usuarios aportando info de esta obra',
                  ),
                  children: camposObra.keys.map((campo) {
                    final bloqueado = _camposBloqueados.containsKey(campo);
                    final esFecha = camposDeFecha.contains(campo);
                    final opciones = opcionesCampo[campo];

                    if (opciones != null && !bloqueado) {
                      final ctrl = _obraCtrls[campo]!;
                      final valorActual = opciones.contains(ctrl.text) ? ctrl.text : null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DropdownButtonFormField<String>(
                          initialValue: valorActual,
                          decoration: InputDecoration(labelText: etiquetaCampo(campo, _tipo)),
                          hint: const Text('Sin especificar'),
                          items: opciones
                              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                              .toList(),
                          onChanged: (v) => setState(() => ctrl.text = v ?? ''),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        controller: _obraCtrls[campo],
                        enabled: !bloqueado,
                        readOnly: esFecha,
                        onTap: (esFecha && !bloqueado) ? () => _elegirFecha(campo) : null,
                        decoration: InputDecoration(
                          labelText: etiquetaCampo(campo, _tipo),
                          helperText: campo == 'genero' && !bloqueado
                              ? 'Separa varios géneros con coma (ej. Acción, Fantasía)'
                              : esFecha && !bloqueado
                                  ? 'Toca para elegir día, mes y año'
                                  : (bloqueado ? 'Ya validado, no se puede modificar' : null),
                          suffixIcon: bloqueado
                              ? const Icon(Icons.lock_outline, size: 18)
                              : (esFecha ? const Icon(Icons.calendar_today, size: 18) : null),
                          filled: bloqueado,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
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