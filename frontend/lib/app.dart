import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/navigation/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';

class YuemnoiApp extends StatefulWidget {
  const YuemnoiApp({super.key, this.initialRoute = AppRoutes.login});

  final String initialRoute;

  @override
  State<YuemnoiApp> createState() => _YuemnoiAppState();
}

class _YuemnoiAppState extends State<YuemnoiApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = AppRoutes.createRouter(initialLocation: widget.initialRoute);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthBloc>(
      create: (context) =>
          AuthBloc(authRepository: AuthRepositoryImpl(AuthRemoteDataSource())),
      child: MaterialApp.router(
        title: 'Yuemnoi App',
        theme: AppTheme.lightTheme,
        themeMode: ThemeMode.light,
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
      ),
    );
  }
}
