import 'package:flutter/material.dart';
import 'package:frontend/features/splashscreen/presentation/pages/splashscreen.dart';
import 'core/theme/app_theme.dart';

class YuemnoiApp extends StatelessWidget {
  const YuemnoiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yuemnoi App',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
