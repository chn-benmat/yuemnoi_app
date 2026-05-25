import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/splashscreen/presentation/pages/splashscreen.dart';

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
