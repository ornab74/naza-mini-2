import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart'
    show FlutterCryptography;

import 'controller.dart';
import 'screens/naza_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Select the Android/iOS native AES-GCM implementation before the crypto
  // service constructs its cipher. This avoids the much slower pure-Dart
  // fallback on mobile; Linux keeps its OpenSSL fast path.
  FlutterCryptography.enable();
  final controller = NazaController();
  await controller.initialize();
  runApp(NazaApp(controller: controller));
  unawaited(controller.bootstrap());
}

class NazaApp extends StatelessWidget {
  const NazaApp({super.key, required this.controller});

  final NazaController controller;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7C5CFF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NAZA • LlamaDart',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: const Color(0xFF10111A),
        ),
        scaffoldBackgroundColor: Colors.transparent,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.055),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF9C83FF), width: 1.4),
          ),
        ),
      ),
      home: NazaShell(controller: controller),
      // This build is launched with Flutter's --enable-software-rendering
      // flag by run_linux.sh. Keep the setting visible in the UI as well.
    );
  }
}
