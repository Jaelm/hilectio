import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'logros_service.dart';

enum TipoCofre { normal, raro, legendario }
enum Pool { titulos, fotos }

/// Las "fotos de perfil" que salen de los cofres son nombres simbólicos
/// (no imágenes reales), así que se representan con un ícono.
const Map<String, IconData> iconosFoto = {
  'Hoja': Icons.eco,
  'Pluma': Icons.edit_outlined,
  'Taza': Icons.local_cafe,
  'Luna': Icons.nightlight_round,
  'Estrella': Icons.star,
  'Fuego': Icons.local_fire_department,
  'Rayo': Icons.bolt,
  'Corona': Icons.workspace_premium,
  'Dragón': Icons.whatshot,
  'Fénix': Icons.auto_awesome,
};

class CofresService {
  static const Map<TipoCofre, int> costos = {
    TipoCofre.normal: 100,
    TipoCofre.raro: 300,
    TipoCofre.legendario: 700,
  };

  static const Map<TipoCofre, Map<String, int>> probabilidades = {
    TipoCofre.normal: {'comun': 70, 'raro': 25, 'legendario': 5},
    TipoCofre.raro: {'comun': 40, 'raro': 45, 'legendario': 15},
    TipoCofre.legendario: {'comun': 20, 'raro': 40, 'legendario': 40},
  };

  static const Map<Pool, Map<String, List<String>>> catalogos = {
    Pool.titulos: {
      'comun': [
        'Solo un Capítulo Más',
        'Lector Novato',
        'Aventurero de Nivel 1',
        'Devorador de Páginas',
        'Acumulador de Pestañas',
        'Hojear Casual',
        'Aprendiz de Tinta',
        'Aficionado al Shōnen',
        'Lector de Fin de Semana',
        'Insomnio Literario',
        'Rata de Biblioteca',
        'Lector en Tránsito',
        'Consumidor de Prólogos',
        'Siempre en Pausa',
        'Coleccionista de Marcadores',
        'Entusiasta del Manhwa',
        'Lector de Bolsillo',
        'Escaneador de Paneles',
        'Alma de Protagonista',
        'Lector de Madrugada',
      ],
      'raro': [
        'Arquero del Streaming',
        'Lector de Rango A',
        'Mago del Grimorio',
        'Cazador de Spoilers',
        'Navegante de Capítulos',
        'Erudito del Webtoon',
        'Experto en Isekai',
        'Cultivador de Rango Medio',
        'Maratón de Fin de Semana',
        'Guardián de la Biblioteca',
        'Maestro del Cliffhanger',
        'Crítico de Manhua',
        'Sabio de las Viñetas',
        'Caballero de la Lectura',
        'Coleccionista de Relatos',
        'Lector Empedernido',
        'Cazador de Capítulos',
        'Adicto a la Tinta',
        'Lector Sin Fronteras',
        'Pionero de Historias',
      ],
      'legendario': [
        'Monarca de las Sombras Literarias',
        'Rey de los Lectores',
        'Arquero Genial de las Letras',
        'Lector de Clase S',
        'Gran Mago de la Lectura',
        'Emperador del Cultivo',
        'Dios de la Tinta',
        'Oráculo de Hilectio',
        'Devorador de Mundos',
        'Soberano del Cliffhanger',
        'Archimago de los Manhwas',
        'El Que Lo Ha Leído Todo',
        'Leyenda de las Páginas',
        'Señor de los Webtoons',
        'Erudito Trascendental',
        'Conquistador de Capítulos',
        'Titán de las Letras',
        'Inmortal del Manhua',
        'Héroe de la Biblioteca',
        'Leyenda del Streaming Literario',
      ],
    },
    Pool.fotos: {
      'comun': ['Hoja', 'Pluma', 'Taza', 'Luna', 'Estrella'],
      'raro': ['Fuego', 'Rayo', 'Corona'],
      'legendario': ['Dragón', 'Fénix'],
    },
  };

  final _rand = Random();

  DocumentReference<Map<String, dynamic>> get _userDoc => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(FirebaseAuth.instance.currentUser!.uid);

  String _sortearRareza(TipoCofre cofre) {
    final pesos = probabilidades[cofre]!;
    final total = pesos.values.reduce((a, b) => a + b);
    final tiro = _rand.nextInt(total);
    int acumulado = 0;
    for (final entry in pesos.entries) {
      acumulado += entry.value;
      if (tiro < acumulado) return entry.key;
    }
    return pesos.keys.last;
  }

  Future<Map<String, dynamic>> abrirCofre({
    required TipoCofre cofre,
    required Pool pool,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final resultado = await FirebaseFirestore.instance.runTransaction<Map<String, dynamic>>((tx) async {
      final snap = await tx.get(_userDoc);
      final data = snap.data() ?? {};
      final int tokensActuales = data['tokens'] ?? 0;
      final costo = costos[cofre]!;

      if (tokensActuales < costo) {
        return {'error': 'No tienes suficientes tokens'};
      }

      final campoInventario = pool == Pool.titulos ? 'titulosObtenidos' : 'fotosObtenidas';
      final List<dynamic> inventarioActual = List.from(data[campoInventario] ?? []);

      final rareza = _sortearRareza(cofre);
      final opciones = catalogos[pool]![rareza]!;
      final item = opciones[_rand.nextInt(opciones.length)];

      final yaTenia = inventarioActual.contains(item);
      int tokensFinales = tokensActuales - costo;

      if (yaTenia) {
        final devolucion = (costo * 0.5).round();
        tokensFinales += devolucion;
        tx.set(_userDoc, {'tokens': tokensFinales}, SetOptions(merge: true));
        return {
          'item': item,
          'rareza': rareza,
          'yaTenia': true,
          'devolucion': devolucion,
          'tokens': tokensFinales,
        };
      } else {
        tx.set(_userDoc, {
          'tokens': tokensFinales,
          campoInventario: FieldValue.arrayUnion([item]),
        }, SetOptions(merge: true));
        return {
          'item': item,
          'rareza': rareza,
          'yaTenia': false,
          'tokens': tokensFinales,
        };
      }
    });

    if (resultado['error'] == null) {
      final logros = await LogrosService().alAbrirCofre(
        uid,
        esComun: cofre == TipoCofre.normal,
        rarezaResultado: resultado['rareza'] as String,
        fueDuplicado: resultado['yaTenia'] == true,
      );
      resultado['logrosDesbloqueados'] = logros;
    }
    return resultado;
  }
}