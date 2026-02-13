import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/glass_theme.dart';
import 'screens/main_screen.dart';
import 'providers/settings_provider.dart';

class FileCopyApp extends ConsumerWidget {
  const FileCopyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Hafiportrait Manager',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: GlassTheme.lightTheme,
      darkTheme: GlassTheme.darkTheme,
      home: const MainScreen(),
    );
  }
}
