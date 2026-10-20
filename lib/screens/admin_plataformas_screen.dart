import 'package:flutter/material.dart';
import 'ranking_plataformas_view.dart';

/// Atajo desde Perfil (admin) a la misma vista de ranking de plataformas que
/// ahora también pueden ver todos los usuarios desde Descubrir. Aquí, además,
/// el admin puede cambiar el ícono de cada plataforma.
class AdminPlataformasScreen extends StatelessWidget {
  const AdminPlataformasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plataformas')),
      body: const RankingPlataformasView(),
    );
  }
}