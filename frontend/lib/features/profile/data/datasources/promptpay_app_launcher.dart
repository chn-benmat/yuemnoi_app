import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef PromptPayApp = ({String packageName, String name});

abstract final class PromptPayAppLauncher {
  static const _channel = MethodChannel('yuemnoi/promptpay_apps');

  // เพิ่ม package ที่ AndroidManifest.xml เมื่อเพิ่มแอปในรายการนี้
  static const _apps = {
    'com.kasikorn.retail.mbanking.wap': 'K PLUS',
    'com.scb.phone': 'SCB EASY',
    'ktbcs.netbank': 'Krungthai NEXT',
    'com.bbl.mobilebanking': 'Bangkok Bank Mobile Banking',
    'com.krungsri.kma': 'krungsri',
    'com.TMBTOUCH.PRODUCTION': 'ttb touch',
    'com.mobilife.gsb.mymo': 'MyMo by GSB',
    'com.kasikornbank.makebykbank': 'MAKE by KBank',
    'th.co.truemoney.wallet': 'TrueMoney',
    'com.ktb.customer.qr': 'เป๋าตัง',
  };

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<List<PromptPayApp>> installedApps() async {
    final packages = await _channel.invokeListMethod<String>(
      'installedApps',
      _apps.keys.toList(),
    );
    final installed = packages?.toSet() ?? const <String>{};
    return [
      for (final app in _apps.entries)
        if (installed.contains(app.key))
          (packageName: app.key, name: app.value),
    ];
  }

  static Future<bool> open(PromptPayApp app) async =>
      await _channel.invokeMethod<bool>('openApp', app.packageName) ?? false;
}
