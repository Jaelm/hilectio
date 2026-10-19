import 'package:cloud_firestore/cloud_firestore.dart';

/// Marcadores de progreso que el usuario le puede poner a una lectura.
const Map<String, String> estadosLectura = {
  'leyendo': 'Leyendo',
  'pendiente': 'Pendiente',
  'abandonado': 'Abandonado',
  'terminado': 'Terminado',
};

class Lectura {
  final String id;
  final String titulo;
  final String tipo; // Manhwa, Manga, Manhua, Novela, Libro, Otro
  final String plataforma;
  final String capituloActual;
  final String link;
  final int frecuenciaDias;
  final bool esAdulto;
  final String estado; // leyendo, pendiente, abandonado, terminado (ver estadosLectura)
  final DateTime actualizadoEn;

  Lectura({
    required this.id,
    required this.titulo,
    required this.tipo,
    required this.plataforma,
    required this.capituloActual,
    required this.link,
    required this.frecuenciaDias,
    required this.esAdulto,
    required this.estado,
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
      esAdulto: data['esAdulto'] ?? false,
      estado: estadosLectura.containsKey(data['estado']) ? data['estado'] : 'leyendo',
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
      'esAdulto': esAdulto,
      'estado': estado,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
  }
}