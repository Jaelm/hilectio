import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'biblioteca_screen.dart';
import 'perfil_screen.dart';
import 'cofres_screen.dart';
import 'descubrir_screen.dart';
import '../services/ads_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _saliendo = false;

  static const _screens = [
    BibliotecaScreen(),
    DescubrirScreen(),
    CofresScreen(),
    PerfilScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Anuncio "fijo" de la primera apertura del día (si corresponde). Se
    // dispara después del primer frame para no competir con el arranque de
    // la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdsService().mostrarAnuncioFijoSiCorresponde();
    });
  }

  /// Al presionar "atrás" en la pantalla principal (que es salir de la
  /// app): con cierta probabilidad se muestra un anuncio antes de dejar
  /// salir de verdad.
  Future<void> _manejarSalida() async {
    if (_saliendo) return;
    _saliendo = true;
    await AdsService().mostrarAnuncioAleatorioAlSalir();
    if (mounted) SystemNavigator.pop();
    _saliendo = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _manejarSalida();
      },
      child: Scaffold(
        body: SafeArea(child: _screens[_index]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Biblioteca'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Descubrir'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Cofres'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}