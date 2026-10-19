import 'package:cloud_firestore/cloud_firestore.dart';

class Lectura {
  final String id;
  final String titulo;
  final String tipo; // Manhwa, Manga, Manhua, Libro
  final String plataforma;
  final String capituloActual;
  final String link;
  final int frecuenciaDias; // cada cuántos días se actualiza
  final DateTime actualizadoEn;

  Lectura({
    required this.id,
    required this.titulo,
    required this.tipo,
    required this.plataforma,
    required this.capituloActual,
    required this.link,
    required this.frecuenciaDias,
    required this.actualizadoEn,
  });

  factory Lectura.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Lectura(
      id: doc.id,
      titulo: data['titulo'] ?? '',
      tipo: data['tipo'] ?? 'Manhwa',
      plataforma: data['plataforma'] ?? '',
      capituloActual: data['capituloActual'] ?? '',
      link: data['link'] ?? '',
      frecuenciaDias: data['frecuenciaDias'] ?? 7,
      actualizadoEn: (data['actualizadoEn'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'titulo': titulo,
      'tipo': tipo,
      'plataforma': plataforma,
      'capituloActual': capituloActual,
      'link': link,
      'frecuenciaDias': frecuenciaDias,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
  }
}