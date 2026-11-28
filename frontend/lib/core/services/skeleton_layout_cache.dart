import 'package:shared_preferences/shared_preferences.dart';

/// จำรูปร่างเนื้อหาที่แต่ละหน้าแสดงครั้งล่าสุด เพื่อให้ skeleton รอบถัดไป
/// มีจำนวนและชนิดรายการตรงกับข้อมูลที่กำลังจะขึ้น แทนการเดาจำนวนตายตัว
///
/// เก็บเป็นรายการ token สั้น ๆ ต่อ key (เช่น 'u' = ยังไม่อ่าน) ในหน่วยความจำ
/// และเขียนลง SharedPreferences เพื่อให้ใช้ได้หลังเปิดแอปใหม่
class SkeletonLayoutCache {
  SkeletonLayoutCache._();

  static final instance = SkeletonLayoutCache._();
  static const _prefix = 'skeleton_layout.';

  final Map<String, List<String>> _memory = {};
  SharedPreferences? _prefs;

  /// โหลดค่าที่เคยบันทึกไว้ เรียกครั้งเดียวตอนเปิดแอป ถ้าไม่เรียกจะใช้แค่หน่วยความจำ
  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
  }

  /// รูปร่างล่าสุดของ key นี้ หรือ null ถ้ายังไม่เคยแสดงข้อมูล
  List<String>? read(String key) {
    final cached = _memory[key];
    if (cached != null) return cached;
    final stored = _prefs?.getStringList('$_prefix$key');
    if (stored != null) _memory[key] = stored;
    return stored;
  }

  /// บันทึกรูปร่างที่แสดงอยู่ ตัดเหลือ [max] รายการแรกเพราะ skeleton เกินหนึ่งจอไม่มีใครเห็น
  void write(String key, List<String> tokens, {int max = 8}) {
    final next = tokens.length > max ? tokens.sublist(0, max) : tokens;
    final current = _memory[key];
    if (current != null && _sameTokens(current, next)) return;
    _memory[key] = List.unmodifiable(next);
    _prefs?.setStringList('$_prefix$key', next).ignore();
  }

  /// จำนวนรายการล่าสุด ใช้กับหน้าที่ทุกรายการหน้าตาเหมือนกัน
  int count(String key, {required int fallback}) =>
      read(key)?.length ?? fallback;

  void writeCount(String key, int count, {int max = 8}) =>
      write(key, List.filled(count.clamp(0, max), '1'), max: max);

  static bool _sameTokens(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
