import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/glass_theme.dart';
import 'screens/main_screen.dart';
import 'providers/settings_provider.dart';

class FileCopyApp extends ConsumerWidget {
  const FileCopyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));

    return MaterialApp(
      title: 'Hafiportrait Manager',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: GlassTheme.lightTheme,
      darkTheme: GlassTheme.darkTheme,
      home: const MainScreen(),
    );
  }
}
