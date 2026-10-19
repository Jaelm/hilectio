import 'package:flutter/material.dart';
import 'biblioteca_screen.dart';
import 'perfil_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    BibliotecaScreen(),
    Center(child: Text('Descubrir')),
    Center(child: Text('Cofres')),
    PerfilScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }
}