import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/home/data/datasources/home_supabase_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _RealHttpOverrides();
  });

  test('fetches live items from Supabase and searches with Thai queries', () async {
    const supabaseUrl = 'https://dkfqjyjjawpgiqhehrvl.supabase.co';
    const anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRrZnFqeWpqYXdwZ2lxaGVocnZsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcwMzMxNzEsImV4cCI6MjA5MjYwOTE3MX0.zQ81fpkHBEv_JdzAEko84tL9C_GN5f95xMo9QLA4scU';

    final client = SupabaseClient(supabaseUrl, anonKey);
    final dataSource = HomeSupabaseDataSource(supabaseClient: client);

    final items = await dataSource.fetchNearbyItems();
    print('SUCCESS: Fetched ${items.length} items from Supabase directly!');
    expect(items.length, greaterThanOrEqualTo(20));

    // ทดสอบค้นหาภาษาไทย "กล้อง"
    final cameras = await dataSource.fetchNearbyItems(searchQuery: 'กล้อง');
    print('SUCCESS: Search "กล้อง" found ${cameras.length} items:');
    for (final c in cameras) {
      print(' - ${c.title} (${c.categoryId})');
    }
    expect(cameras, isNotEmpty);

    // ทดสอบค้นหาด้วยคำในคำอธิบาย "กันฝน"
    final tents = await dataSource.fetchNearbyItems(searchQuery: 'กันฝน');
    print('SUCCESS: Search "กันฝน" found ${tents.length} items:');
    for (final t in tents) {
      print(' - ${t.title} (${t.description})');
    }
    expect(tents, isNotEmpty);

    // ทดสอบค้นหาด้วยคำพ้อง "สว่าน"
    final drills = await dataSource.fetchNearbyItems(searchQuery: 'สว่าน');
    print('SUCCESS: Search "สว่าน" found ${drills.length} items:');
    for (final d in drills) {
      print(' - ${d.title}');
    }
    expect(drills, isNotEmpty);

    // ทดสอบค้นหาสินค้าใหม่ ID 37 "โกะโจ"
    final gojoItems = await dataSource.fetchNearbyItems(searchQuery: 'โกะโจ');
    print('SUCCESS: Search "โกะโจ" found ${gojoItems.length} items:');
    for (final g in gojoItems) {
      print(' - ${g.title} (ID: ${g.id})');
    }
    expect(gojoItems, isNotEmpty);

    // ทดสอบค้นหาด้วยชื่อบัญชีผู้ปล่อยเช่า "John Doe"
    final johnItems = await dataSource.fetchNearbyItems(searchQuery: 'John Doe');
    print('SUCCESS: Search owner "John Doe" found ${johnItems.length} items:');
    for (final j in johnItems) {
      print(' - ${j.title} (Owner: ${j.ownerName})');
    }
    expect(johnItems, isNotEmpty);
  });
}
