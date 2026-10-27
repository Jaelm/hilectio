import 'package:flutter/material.dart';
import 'biblioteca_screen.dart';
import 'perfil_screen.dart';
import 'cofres_screen.dart';
import 'descubrir_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final PageController _pageController;

  static const _screens = [
    BibliotecaScreen(),
    DescubrirScreen(),
    CofresScreen(),
    PerfilScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _irA(int i) {
    setState(() => _index = i);
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          onPageChanged: (i) => setState(() => _index = i),
          children: _screens,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _irA,
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