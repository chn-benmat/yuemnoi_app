import 'dart:async';

enum CallAudioTone { none, dialTone, ringtone }

class CallAudioService {
  CallAudioService();

  Timer? _toneTimer;
  CallAudioTone _currentTone = CallAudioTone.none;

  CallAudioTone get currentTone => _currentTone;
  bool get isPlaying => _currentTone != CallAudioTone.none;

  /// เล่นเสียงรอสาย (ตู๊ด... ตู๊ด...) สำหรับฝั่งผู้โทร
  void playDialTone() {
    stopAll();
    _currentTone = CallAudioTone.dialTone;

    // จำลองจังหวะเสียงรอสาย (ตู๊ด 1.2 วินาที, เว้นวรรค 2 วินาที)
    _toneTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {});
  }

  /// เล่นเสียงเรียกเข้าสำหรับฝั่งผู้รับสาย
  void playRingtone() {
    stopAll();
    _currentTone = CallAudioTone.ringtone;

    // จำลองจังหวะเสียงเรียกเข้า
    _toneTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {});
  }

  /// หยุดเสียงทั้งหมดทันที
  void stopAll() {
    _toneTimer?.cancel();
    _toneTimer = null;
    _currentTone = CallAudioTone.none;
  }

  void dispose() {
    stopAll();
  }
}
