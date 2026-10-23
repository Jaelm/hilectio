import 'package:flutter/material.dart';
import '../services/tema_service.dart';

/// Elegir modo (claro/oscuro/según el sistema) y paleta de color. Se guarda
/// solo en este dispositivo (ver [TemaController]) y se aplica al instante,
/// sin tener que reiniciar la app.
class AparienciaScreen extends StatelessWidget {
  const AparienciaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = TemaController.instance;
    return AnimatedBuilder(
      animation: tema,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Apariencia')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Modo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode_outlined)),
                ButtonSegment(
                    value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.settings_suggest_outlined)),
              ],
              selected: {tema.modo},
              onSelectionChanged: (seleccion) => tema.cambiarModo(seleccion.first),
            ),
            const SizedBox(height: 28),
            const Text('Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: paletasDisponibles.map((p) {
                final seleccionada = p.id == tema.paletaId;
                return GestureDetector(
                  onTap: () => tema.cambiarPaleta(p.id),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: p.semilla,
                          shape: BoxShape.circle,
                          border: seleccionada
                              ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: seleccionada
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(height: 6),
                      Text(p.nombre, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}