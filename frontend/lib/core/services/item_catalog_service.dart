import 'dart:async';

/// แจ้งการเปลี่ยนรายการอุปกรณ์ข้ามหน้าที่ไม่ได้ใช้ BLoC ร่วมกัน
class ItemCatalogService {
  ItemCatalogService._();

  static final ItemCatalogService instance = ItemCatalogService._();

  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  void notifyChanged() => _changes.add(null);
}
