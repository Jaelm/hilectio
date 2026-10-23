import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'screens/verify_email_screen.dart';
import 'screens/elegir_apodo_screen.dart';
import 'services/notification_service.dart';
import 'services/ads_service.dart';
import 'services/tema_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService().init();
  await MobileAds.instance.initialize();
  // Marca este dispositivo (y los que agregues en ads_service.dart) como
  // "de prueba": con el ID de anuncio real, siguen viendo anuncios pero
  // etiquetados como prueba, sin riesgo para la cuenta de AdMob.
  await MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: dispositivosDePrueba),
  );
  await TemaController.instance.cargar();
  runApp(const HilectioApp());
}

class HilectioApp extends StatelessWidget {
  const HilectioApp({super.key});

  ThemeData _construirTema(Color semilla, Brightness brillo) => ThemeData(
        colorSchemeSeed: semilla,
        brightness: brillo,
        useMaterial3: true,
        fontFamily: 'Helvetica Neue',
      );

  @override
  Widget build(BuildContext context) {
    final tema = TemaController.instance;
    return AnimatedBuilder(
      animation: tema,
      builder: (context, _) => MaterialApp(
        title: 'Hilectio',
        debugShowCheckedModeBanner: false,
        themeMode: tema.modo,
        theme: _construirTema(tema.paleta.semilla, Brightness.light),
        darkTheme: _construirTema(tema.paleta.semilla, Brightness.dark),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // userChanges() (a diferencia de authStateChanges()) también emite
    // cuando se llama a user.reload(), lo que permite que esta pantalla
    // avance sola apenas el usuario confirma su correo.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        if (!user.emailVerified) {
          return const VerifyEmailScreen();
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('usuarios')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userDocSnap) {
            if (userDocSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final apodo = userDocSnap.data?.data()?['apodo'] as String?;
            if (apodo == null || apodo.trim().isEmpty) {
              return const ElegirApodoScreen();
            }
            return const HomeShell();
          },
        );
      },
    );
  }
}