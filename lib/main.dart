import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'features/auth/auth_screen.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const FrshNearbyApp());
}

class FrshNearbyApp extends StatelessWidget {
  const FrshNearbyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF2F6B45);
    const ink = Color(0xFF183326);
    const line = Color(0xFFE2E8DD);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        scaffoldBackgroundColor: const Color(0xFFF9FAF5),
        textTheme: GoogleFonts.nunitoSansTextTheme().apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFBA1A1A)),
          ),
        ),
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        for (final locale in supportedLocales) {
          if (locale.languageCode == deviceLocale?.languageCode) return locale;
        }
        return const Locale('en');
      },
      home: const _ResponsiveAuthPreview(),
    );
  }
}

class _ResponsiveAuthPreview extends StatelessWidget {
  const _ResponsiveAuthPreview();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a desktop-sized browser, present the app inside a phone-sized
        // preview. Phones and narrow browser windows keep the native full view.
        if (constraints.maxWidth < 800) return const AuthScreen();

        final phoneHeight = (constraints.maxHeight - 64).clamp(640.0, 860.0);
        return Scaffold(
          backgroundColor: const Color(0xFFEFF4E9),
          body: Stack(
            children: [
              Positioned(
                top: -120,
                right: -80,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCEBDD),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: -160,
                left: -100,
                child: Container(
                  width: 420,
                  height: 420,
                  decoration: const BoxDecoration(
                    color: Color(0xFFDCEBDD),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 430,
                  height: phoneHeight,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF183326),
                    borderRadius: BorderRadius.circular(38),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: const AuthScreen(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
