import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una paleta de color para elegir: el nombre que ve el usuario y el color
/// "semilla" con el que Material 3 genera todo el esquema de colores (claro
/// y oscuro) automáticamente.
class PaletaColor {
  final String id;
  final String nombre;
  final Color semilla;
  const PaletaColor({required this.id, required this.nombre, required this.semilla});
}

const List<PaletaColor> paletasDisponibles = [
  PaletaColor(id: 'naranja', nombre: 'Naranja', semilla: Color(0xFFC96F4A)),
  PaletaColor(id: 'azul', nombre: 'Azul', semilla: Color(0xFF3F6FB5)),
  PaletaColor(id: 'verde', nombre: 'Verde', semilla: Color(0xFF4C8C5C)),
  PaletaColor(id: 'morado', nombre: 'Morado', semilla: Color(0xFF7A5CC9)),
  PaletaColor(id: 'rosa', nombre: 'Rosa', semilla: Color(0xFFC9557D)),
];

const String _paletaPorDefecto = 'naranja';
const String _claveModo = 'tema_modo';
const String _clavePaleta = 'tema_paleta';

/// Controla el tema de toda la app: modo (claro/oscuro/según el sistema) y
/// paleta de color elegida. Es un [ChangeNotifier] para que [MaterialApp] se
/// reconstruya solo cuando el usuario cambia algo, y guarda la elección con
/// `shared_preferences` (solo en este dispositivo) para que se recuerde
/// entre aperturas de la app.
class TemaController extends ChangeNotifier {
  TemaController._();

  /// Instancia única: así cualquier pantalla puede leerla/escucharla (para
  /// reconstruirse cuando cambia) o cambiarla, sin tener que pasarla a mano
  /// por todo el árbol de widgets.
  static final TemaController instance = TemaController._();

  ThemeMode _modo = ThemeMode.system;
  String _paletaId = _paletaPorDefecto;

  ThemeMode get modo => _modo;
  String get paletaId => _paletaId;
  PaletaColor get paleta =>
      paletasDisponibles.firstWhere((p) => p.id == _paletaId, orElse: () => paletasDisponibles.first);

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final modoGuardado = prefs.getString(_claveModo);
    final paletaGuardada = prefs.getString(_clavePaleta);
    _modo = switch (modoGuardado) {
      'claro' => ThemeMode.light,
      'oscuro' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (paletaGuardada != null && paletasDisponibles.any((p) => p.id == paletaGuardada)) {
      _paletaId = paletaGuardada;
    }
    notifyListeners();
  }

  Future<void> cambiarModo(ThemeMode nuevo) async {
    _modo = nuevo;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveModo, switch (nuevo) {
      ThemeMode.light => 'claro',
      ThemeMode.dark => 'oscuro',
      ThemeMode.system => 'sistema',
    });
  }

  Future<void> cambiarPaleta(String id) async {
    if (!paletasDisponibles.any((p) => p.id == id)) return;
    _paletaId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clavePaleta, id);
  }
}