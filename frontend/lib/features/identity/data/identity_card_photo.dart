import 'package:flutter/services.dart';

const identityCardAspectRatio = 85.6 / 53.98;
const _channel = MethodChannel('yuemnoi/identity_card_photo');

Future<Uint8List> prepareIdentityCardPhoto(
  String path, {
  required double previewAspectRatio,
}) async {
  final jpeg = await _channel.invokeMethod<Uint8List>('prepare', {
    'path': path,
    'previewAspectRatio': previewAspectRatio,
    'cardAspectRatio': identityCardAspectRatio,
  });
  if (jpeg == null || jpeg.isEmpty) {
    throw const FormatException('Cannot prepare card photo');
  }
  return jpeg;
}
