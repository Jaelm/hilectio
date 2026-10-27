import 'package:cloud_firestore/cloud_firestore.dart';

/// Marcadores de progreso que el usuario le puede poner a una lectura.
const Map<String, String> estadosLectura = {
  'leyendo': 'Leyendo',
  'pendiente': 'Pendiente',
  'abandonado': 'Abandonado',
  'terminado': 'Terminado',
};

/// Días de la semana en que normalmente se actualiza la obra. Se usa en vez
/// de "cada cuántos días" porque el usuario no siempre lee el mismo día que
/// sale el capítulo (a veces lo lee uno o dos días después), así que contar
/// desde "hoy" hace que el recordatorio se vaya desfasando con el tiempo;
/// anclarlo a un día fijo de la semana no tiene ese problema.
const Map<String, String> diasSemana = {
  'lunes': 'Lunes',
  'martes': 'Martes',
  'miercoles': 'Miércoles',
  'jueves': 'Jueves',
  'viernes': 'Viernes',
  'sabado': 'Sábado',
  'domingo': 'Domingo',
};

/// Convierte la clave de [diasSemana] al número de día de `DateTime`
/// (lunes = 1 ... domingo = 7). Si la clave no se reconoce, cae en lunes.
int numeroDiaSemana(String dia) {
  const orden = [
    'lunes',
    'martes',
    'miercoles',
    'jueves',
    'viernes',
    'sabado',
    'domingo',
  ];
  final indice = orden.indexOf(dia);
  return indice == -1 ? DateTime.monday : indice + 1;
}

class Lectura {
  final String id;
  final String titulo;
  final String tipo; // Manhwa, Manga, Manhua, Novela, Libro, Otro
  final String plataforma;
  final String capituloActual;
  final String link;
  final String diaActualizacion; // clave de diasSemana
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
    required this.diaActualizacion,
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
      diaActualizacion:
          diasSemana.containsKey(data['diaActualizacion']) ? data['diaActualizacion'] : 'lunes',
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
      'diaActualizacion': diaActualizacion,
      'esAdulto': esAdulto,
      'estado': estado,
      'actualizadoEn': FieldValue.serverTimestamp(),
    };
  }
}