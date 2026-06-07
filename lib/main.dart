import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/main_screen.dart';
import 'services/audio_service.dart';
import 'services/music_audio_handler.dart';
import 'services/persistence_service.dart';
import 'services/theme_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPersistence();
  await Supabase.initialize(
    url: 'https://snhcyaydegtubucwopia.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNuaGN5YXlkZWd0dWJ1Y3dvcGlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3MzQyODAsImV4cCI6MjA5NjMxMDI4MH0.erijkhC64AhtV4-npTHQk9ZGSeG_S19lwIMboWZ7hQ8',
  );
  ensureBackgroundAudioService = () async {
    await ensureMusicAudioService();
  };
  runApp(const MyApp());
  unawaited(_initializePlaybackServices());
}

Future<void> _initializePlaybackServices() async {
  try {
    await ensureMusicAudioService();
    await initAudioPlayback();
    await restorePlaybackState();
  } catch (error, stackTrace) {
    debugPrint('Playback service init failed: $error\n$stackTrace');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeChoice>(
      valueListenable: appThemeChoiceNotifier,
      builder: (context, themeChoice, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lightAppTheme(themeChoice),
          darkTheme: darkAppTheme(themeChoice),
          themeMode: themeModeForChoice(themeChoice),
          themeAnimationDuration: const Duration(milliseconds: 360),
          themeAnimationCurve: Curves.easeOutCubic,
          home: child,
        );
      },
      child: const MainScreen(),
    );
  }
}
