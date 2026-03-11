// lib/main.dart
// Startpunkt der App

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Nur Hochformat erlauben
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Statusbar-Farbe anpassen (dunkles Design)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const VokabeltrainerApp());
}

class VokabeltrainerApp extends StatelessWidget {
  const VokabeltrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VokabelTrainer C1',
      debugShowCheckedModeBanner: false,

      // Dunkles Farbschema
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4ECDC4),
          secondary: Color(0xFFFF6B35),
          surface: Color(0xFF16213E),
        ),
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        useMaterial3: true,
      ),

      home: const HomeScreen(),
    );
  }
}
