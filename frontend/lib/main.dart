import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'core/navigation/app_routes.dart';
import 'core/network/auth_session.dart';
import 'core/network/supabase_client.dart';

import 'core/services/user_presence_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');
  await SupabaseConfig.initialize();

  final isAuthenticated = await AuthSession.restore();
  if (isAuthenticated) {
    UserPresenceService.instance.initialize();
  }

  runApp(
    YuemnoiApp(
      initialRoute: isAuthenticated ? AppRoutes.home : AppRoutes.login,
    ),
  );
}
