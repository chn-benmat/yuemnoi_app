import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/thai_address.dart';

class AssetThaiAddressRepository implements ThaiAddressRepository {
  AssetThaiAddressRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<List<ThaiProvince>>? _cached;

  @override
  Future<List<ThaiProvince>> load() => _cached ??= _load();

  Future<List<ThaiProvince>> _load() async {
    try {
      return await _bundle.loadStructuredBinaryData(
        'assets/data/thai_addresses.json',
        (bytes) => compute(_decodeAddresses, bytes),
      );
    } catch (_) {
      // เปิดให้ลองโหลด asset ใหม่ได้ หากการอ่านครั้งก่อนล้มเหลว
      _cached = null;
      rethrow;
    }
  }
}

List<ThaiProvince> _decodeAddresses(ByteData source) {
  final data =
      jsonDecode(utf8.decode(Uint8List.sublistView(source)))
          as Map<String, dynamic>;
  return List.unmodifiable(
    (data['provinces'] as List).cast<Map<String, dynamic>>().map(
      (province) => ThaiProvince(
        id: province['id'] as int,
        name: province['name'] as String,
        districts: List.unmodifiable(
          (province['districts'] as List).cast<Map<String, dynamic>>().map(
            (district) => ThaiDistrict(
              id: district['id'] as int,
              name: district['name'] as String,
              subdistricts: List.unmodifiable(
                (district['subdistricts'] as List)
                    .cast<Map<String, dynamic>>()
                    .map(
                      (subdistrict) => ThaiSubdistrict(
                        id: subdistrict['id'] as int,
                        name: subdistrict['name'] as String,
                        postalCodes: List.unmodifiable(
                          (subdistrict['postal_codes'] as List).cast<String>(),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
