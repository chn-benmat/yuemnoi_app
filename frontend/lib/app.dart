import 'package:flutter/material.dart';

import 'core/navigation/app_routes.dart';
import 'core/theme/app_theme.dart';

class YuemnoiApp extends StatelessWidget {
  const YuemnoiApp({super.key, this.initialRoute = AppRoutes.login});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yuemnoi App',
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      onGenerateInitialRoutes: (routeName) {
        final route = AppRoutes.onGenerateRoute(RouteSettings(name: routeName));
        return route == null
            ? const <Route<dynamic>>[]
            : <Route<dynamic>>[route];
      },
      onGenerateRoute: (settings) => AppRoutes.onGenerateRoute(settings),
    );
  }
}
