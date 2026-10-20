import 'dart:async';
import 'dart:math';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ID real del bloque de anuncios "Intersticial principal" (cuenta propia de
/// AdMob del proyecto Hilectio).
const String idAnuncioInterstitialAndroid = 'ca-app-pub-6174555891569247/3191756579';

/// IDs de dispositivos marcados como "de prueba" ante Google: en estos
/// dispositivos, los anuncios con el ID real de arriba se sirven igual pero
/// van etiquetados como anuncio de prueba (no generan ingresos ni cuentan
/// como tráfico real), así que verlos/tocarlos ahí no arriesga la cuenta de
/// AdMob. La PRIMERA vez que corras la app con el ID real, en la consola de
/// `flutter run` (o en logcat) va a aparecer un mensaje de Google con tu ID
/// de dispositivo de prueba, algo como:
///   "...use RequestConfiguration.Builder#setTestDeviceIds(Arrays.asList
///   ("33BE2250B43518CCDA7DE426D04EE231"))..."
/// Copia ese ID (la parte entre comillas) y agrégalo a esta lista.
const List<String> dispositivosDePrueba = [
  'B5D91ECA64ECAAB8405BB04004D0C357', // Xiaomi M2101K6G (teléfono de prueba)
];

/// Tope diario de anuncios (el fijo de entrada + el aleatorio al salir
/// cuentan para el mismo tope).
const int topeAnunciosPorDia = 2;

/// Probabilidad de que, al intentar salir de la app, se muestre el anuncio
/// "aleatorio" (si todavía no se llegó al tope diario).
const double probabilidadAnuncioAlSalir = 0.5;

/// Maneja la carga/los límites de los anuncios intersticiales. El conteo
/// diario se guarda localmente en el dispositivo (no en Firestore): es un
/// límite de experiencia de usuario, no algo que necesite sincronizarse
/// entre dispositivos ni protegerse con reglas de seguridad.
class AdsService {
  String _hoy() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  Future<int> _contadorHoy(SharedPreferences prefs) async {
    final dia = prefs.getString('anuncios_dia') ?? '';
    if (dia != _hoy()) return 0;
    return prefs.getInt('anuncios_contador') ?? 0;
  }

  Future<void> _registrarAnuncioMostrado(SharedPreferences prefs) async {
    final actual = await _contadorHoy(prefs);
    await prefs.setString('anuncios_dia', _hoy());
    await prefs.setInt('anuncios_contador', actual + 1);
  }

  /// Carga y muestra un intersticial. Devuelve true si realmente se mostró
  /// (y el usuario llegó a cerrarlo), false si falló la carga o se agotó el
  /// tiempo de espera.
  Future<bool> _cargarYMostrar() async {
    final completer = Completer<bool>();

    InterstitialAd.load(
      adUnitId: idAnuncioInterstitialAndroid,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(true);
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );

    // Red de seguridad: si por lo que sea ningún callback dispara (sin
    // internet, anuncio que nunca termina de cargar), no nos quedamos
    // esperando para siempre.
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => false,
    );
  }

  /// Anuncio "fijo" de la primera apertura del día. Se llama una vez al
  /// entrar a la pantalla principal; no hace nada si ya se mostró hoy o si
  /// ya se llegó al tope diario.
  Future<void> mostrarAnuncioFijoSiCorresponde() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('anuncio_fijo_dia') == _hoy()) return;
    if (await _contadorHoy(prefs) >= topeAnunciosPorDia) return;

    final mostrado = await _cargarYMostrar();
    if (mostrado) {
      await prefs.setString('anuncio_fijo_dia', _hoy());
      await _registrarAnuncioMostrado(prefs);
    }
  }

  /// Anuncio "aleatorio" al presionar atrás para salir de la app. Con
  /// [probabilidadAnuncioAlSalir] de probabilidad, y solo si no se superó
  /// el tope diario.
  Future<void> mostrarAnuncioAleatorioAlSalir() async {
    final prefs = await SharedPreferences.getInstance();
    if (await _contadorHoy(prefs) >= topeAnunciosPorDia) return;
    if (Random().nextDouble() > probabilidadAnuncioAlSalir) return;

    final mostrado = await _cargarYMostrar();
    if (mostrado) {
      await _registrarAnuncioMostrado(prefs);
    }
  }
}