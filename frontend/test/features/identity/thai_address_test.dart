import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/identity/data/asset_thai_address_repository.dart';
import 'package:frontend/features/identity/domain/thai_address.dart';
import 'package:frontend/features/identity/presentation/identity_address_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<ThaiProvince> provinces;
  setUpAll(() async {
    provinces = await AssetThaiAddressRepository().load();
  });

  test('เปิด repository ใหม่ใช้รายการที่อยู่เดิมที่แปลงแล้ว', () async {
    expect(await AssetThaiAddressRepository().load(), same(provinces));
  });

  test('ข้อมูลทั้งประเทศไม่มีรหัสซ้ำและสัมพันธ์กันครบทุกระดับ', () {
    final districts = provinces
        .expand((province) => province.districts)
        .toList();
    final subdistricts = districts
        .expand((district) => district.subdistricts)
        .toList();
    expect(provinces, hasLength(77));
    expect(districts, hasLength(928));
    expect(subdistricts, hasLength(7436));
    expect(provinces.map((province) => province.id).toSet(), hasLength(77));
    expect(districts.map((district) => district.id).toSet(), hasLength(928));
    expect(
      subdistricts.map((subdistrict) => subdistrict.id).toSet(),
      hasLength(7436),
    );
    for (final province in provinces) {
      expect(province.name.trim(), isNotEmpty);
      expect(province.districts, isNotEmpty);
      for (final district in province.districts) {
        expect(district.id ~/ 100, province.id);
        expect(district.subdistricts, isNotEmpty);
        for (final subdistrict in district.subdistricts) {
          expect(subdistrict.id ~/ 100, district.id);
          expect(subdistrict.postalCodes, isNotEmpty);
          expect(
            subdistrict.postalCodes.toSet(),
            hasLength(subdistrict.postalCodes.length),
          );
          expect(
            subdistrict.postalCodes.every(
              (code) => RegExp(r'^[1-9][0-9]{4}$').hasMatch(code),
            ),
            true,
          );
        }
      }
    }
    final bangkok = provinces.singleWhere(
      (province) => province.name == 'กรุงเทพมหานคร',
    );
    expect(bangkok.districts, hasLength(50));
    final nongKhaem = bangkok.districts.singleWhere(
      (district) => district.name == 'หนองแขม',
    );
    expect(
      nongKhaem.subdistricts
          .singleWhere((subdistrict) => subdistrict.name == 'หนองแขม')
          .postalCodes,
      ['10160'],
    );
    expect(
      subdistricts.where((subdistrict) => subdistrict.postalCodes.length > 1),
      hasLength(88),
    );
  });

  test('ไม่ยอมเลือกอำเภอหรือตำบลข้ามพื้นที่ที่เลือกไว้', () async {
    final cubit = IdentityAddressCubit(_LoadedRepository(provinces));
    addTearDown(cubit.close);
    await cubit.load();
    final bangkok = provinces.firstWhere((province) => province.id == 10);
    final chiangMai = provinces.firstWhere((province) => province.id == 50);
    cubit.selectProvince(bangkok);
    cubit.selectDistrict(chiangMai.districts.first);
    expect(cubit.state.district, isNull);
    cubit.selectDistrict(bangkok.districts.first);
    cubit.selectSubdistrict(chiangMai.districts.first.subdistricts.first);
    expect(cubit.state.subdistrict, isNull);
    cubit.selectSubdistrict(bangkok.districts.first.subdistricts.first);
    expect(cubit.state.postalCodes, ['10200']);
  });
}

class _LoadedRepository implements ThaiAddressRepository {
  const _LoadedRepository(this.provinces);
  final List<ThaiProvince> provinces;
  @override
  Future<List<ThaiProvince>> load() async => provinces;
}
