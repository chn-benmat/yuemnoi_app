import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../constants/colors.dart';

class AppPermissionService {
  AppPermissionService._();

  /// ตรวจสอบและขอสิทธิ์การใช้งานกล้องถ่ายรูป
  static Future<bool> requestCameraPermission(BuildContext context) async {
    if (kIsWeb) return true;

    try {
      final status = await Permission.camera.status;
      if (status.isGranted || status.isLimited) {
        return true;
      }

      if (status.isPermanentlyDenied) {
        if (context.mounted) {
          await _showPermissionDeniedDialog(
            context: context,
            title: 'ขอสิทธิ์เข้าถึงกล้อง',
            message:
                'แอปพลิเคชันต้องการสิทธิ์การเข้าถึงกล้องถ่ายรูป เพื่อให้คุณสามารถถ่ายรูปภาพส่งในแชทหรือลงประกาศสินค้าได้\n\nกรุณาเปิดการอนุญาตในการตั้งค่าของอุปกรณ์',
            icon: Icons.camera_alt_rounded,
          );
        }
        return false;
      }

      final result = await Permission.camera.request();
      if (result.isGranted || result.isLimited) {
        return true;
      }

      if (result.isPermanentlyDenied && context.mounted) {
        await _showPermissionDeniedDialog(
          context: context,
          title: 'ขอสิทธิ์เข้าถึงกล้อง',
          message:
              'แอปพลิเคชันต้องการสิทธิ์การเข้าถึงกล้องถ่ายรูป เพื่อให้คุณสามารถถ่ายรูปภาพส่งในแชทหรือลงประกาศสินค้าได้\n\nกรุณาเปิดการอนุญาตในการตั้งค่าของอุปกรณ์',
          icon: Icons.camera_alt_rounded,
        );
      }
      return false;
    } catch (e) {
      debugPrint('Camera permission error: $e');
      return true; // Fallback to let system handle
    }
  }

  /// ขอสิทธิ์แจ้งเตือนจากระบบโดยตรงเมื่อเปิดแอปครั้งแรก
  static Future<void> requestNotificationPermission() async {
    final notifications = FlutterLocalNotificationsPlugin();
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        await notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!
            .requestNotificationsPermission();
      case TargetPlatform.iOS:
        await notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()!
            .requestPermissions(alert: true, badge: true, sound: true);
      default:
        break;
    }
  }

  /// ตรวจสอบและขอสิทธิ์การเข้าถึงคลังรูปภาพ (Gallery / Photos)
  static Future<bool> requestGalleryPermission(BuildContext context) async {
    if (kIsWeb) return true;

    try {
      Permission permissionToRequest = Permission.photos;

      if (Platform.isAndroid) {
        final photosStatus = await Permission.photos.status;
        if (photosStatus.isGranted || photosStatus.isLimited) {
          return true;
        }

        final storageStatus = await Permission.storage.status;
        if (storageStatus.isGranted || storageStatus.isLimited) {
          return true;
        }

        final photoReq = await Permission.photos.request();
        if (photoReq.isGranted || photoReq.isLimited) {
          return true;
        }

        final storageReq = await Permission.storage.request();
        if (storageReq.isGranted || storageReq.isLimited) {
          return true;
        }

        if ((photoReq.isPermanentlyDenied || storageReq.isPermanentlyDenied) &&
            context.mounted) {
          await _showPermissionDeniedDialog(
            context: context,
            title: 'ขอสิทธิ์เข้าถึงคลังรูปภาพ',
            message:
                'แอปพลิเคชันต้องการสิทธิ์การเข้าถึงคลังรูปภาพ เพื่อให้คุณสามารถเลือกรูปภาพส่งในแชทหรือลงประกาศสินค้าได้\n\nกรุณาเปิดการอนุญาตในการตั้งค่าของอุปกรณ์',
            icon: Icons.photo_library_rounded,
          );
        }
        return false;
      } else {
        // iOS
        final status = await permissionToRequest.status;
        if (status.isGranted || status.isLimited) {
          return true;
        }

        if (status.isPermanentlyDenied) {
          if (context.mounted) {
            await _showPermissionDeniedDialog(
              context: context,
              title: 'ขอสิทธิ์เข้าถึงคลังรูปภาพ',
              message:
                  'แอปพลิเคชันต้องการสิทธิ์การเข้าถึงคลังรูปภาพ เพื่อให้คุณสามารถเลือกรูปภาพส่งในแชทหรือลงประกาศสินค้าได้\n\nกรุณาเปิดการอนุญาตในการตั้งค่าของอุปกรณ์',
              icon: Icons.photo_library_rounded,
            );
          }
          return false;
        }

        final result = await permissionToRequest.request();
        if (result.isGranted || result.isLimited) {
          return true;
        }

        if (result.isPermanentlyDenied && context.mounted) {
          await _showPermissionDeniedDialog(
            context: context,
            title: 'ขอสิทธิ์เข้าถึงคลังรูปภาพ',
            message:
                'แอปพลิเคชันต้องการสิทธิ์การเข้าถึงคลังรูปภาพ เพื่อให้คุณสามารถเลือกรูปภาพส่งในแชทหรือลงประกาศสินค้าได้\n\nกรุณาเปิดการอนุญาตในการตั้งค่าของอุปกรณ์',
            icon: Icons.photo_library_rounded,
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('Gallery permission error: $e');
      return true; // Fallback
    }
  }

  /// แสดง Dialog แจ้งเตือนเมื่อสิทธิ์ถูกปฏิเสธ พร้อมปุ่มเปิดการตั้งค่า
  static Future<void> _showPermissionDeniedDialog({
    required BuildContext context,
    required String title,
    required String message,
    required IconData icon,
    VoidCallback? customAction,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primaryColor.withValues(alpha: 0.12),
            child: Icon(icon, size: 30, color: AppColors.primaryColor),
          ),
          title: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.4,
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'ยกเลิก',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                if (customAction != null) {
                  customAction();
                } else {
                  openAppSettings();
                }
              },
              child: const Text(
                'เปิดการตั้งค่า',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}
