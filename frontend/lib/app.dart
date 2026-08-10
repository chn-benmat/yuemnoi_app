import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/navigation/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

class YuemnoiApp extends StatelessWidget {
  const YuemnoiApp({super.key, this.initialRoute = AppRoutes.login});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthBloc>(
      create: (context) => AuthBloc(
        authRepository: AuthRepositoryImpl(AuthRemoteDataSource()),
      ),
      child: MaterialApp(
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
      ),
    );
  }
}
