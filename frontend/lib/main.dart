import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'core/navigation/app_routes.dart';
import 'core/network/auth_session.dart';
import 'core/network/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env.local');
  await SupabaseConfig.initialize();

  final isAuthenticated = await AuthSession.restore();
  runApp(
    YuemnoiApp(
      initialRoute: isAuthenticated ? AppRoutes.home : AppRoutes.login,
    ),
  );
}
