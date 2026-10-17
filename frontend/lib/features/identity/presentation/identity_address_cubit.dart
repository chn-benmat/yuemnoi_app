import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/thai_address.dart';

class IdentityAddressState {
  const IdentityAddressState({
    this.provinces = const [],
    this.loading = false,
    this.error = false,
    this.province,
    this.district,
    this.subdistrict,
  });

  final List<ThaiProvince> provinces;
  final bool loading, error;
  final ThaiProvince? province;
  final ThaiDistrict? district;
  final ThaiSubdistrict? subdistrict;

  List<ThaiDistrict> get districts => province?.districts ?? const [];
  List<ThaiSubdistrict> get subdistricts => district?.subdistricts ?? const [];
  List<String> get postalCodes => subdistrict?.postalCodes ?? const [];
}

class IdentityAddressCubit extends Cubit<IdentityAddressState> {
  IdentityAddressCubit(this._repository) : super(const IdentityAddressState());

  final ThaiAddressRepository _repository;

  Future<void> load() async {
    if (state.loading || state.provinces.isNotEmpty) return;
    emit(const IdentityAddressState(loading: true));
    try {
      final provinces = await _repository.load();
      if (provinces.isEmpty) throw const FormatException('ไม่มีข้อมูลจังหวัด');
      if (!isClosed) emit(IdentityAddressState(provinces: provinces));
    } catch (_) {
      if (!isClosed) emit(const IdentityAddressState(error: true));
    }
  }

  void selectProvince(ThaiProvince province) {
    if (province == state.province || !state.provinces.contains(province)) {
      return;
    }
    emit(IdentityAddressState(provinces: state.provinces, province: province));
  }

  void selectDistrict(ThaiDistrict district) {
    if (district == state.district || !state.districts.contains(district)) {
      return;
    }
    emit(
      IdentityAddressState(
        provinces: state.provinces,
        province: state.province,
        district: district,
      ),
    );
  }

  void selectSubdistrict(ThaiSubdistrict subdistrict) {
    if (subdistrict == state.subdistrict ||
        !state.subdistricts.contains(subdistrict)) {
      return;
    }
    emit(
      IdentityAddressState(
        provinces: state.provinces,
        province: state.province,
        district: state.district,
        subdistrict: subdistrict,
      ),
    );
  }

  void reset() => emit(
    IdentityAddressState(
      provinces: state.provinces,
      loading: state.loading,
      error: state.error,
    ),
  );
}
