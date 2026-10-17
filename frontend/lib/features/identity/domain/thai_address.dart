class ThaiProvince {
  const ThaiProvince({
    required this.id,
    required this.name,
    required this.districts,
  });

  final int id;
  final String name;
  final List<ThaiDistrict> districts;
}

class ThaiDistrict {
  const ThaiDistrict({
    required this.id,
    required this.name,
    required this.subdistricts,
  });

  final int id;
  final String name;
  final List<ThaiSubdistrict> subdistricts;
}

class ThaiSubdistrict {
  const ThaiSubdistrict({
    required this.id,
    required this.name,
    required this.postalCodes,
  });

  final int id;
  final String name;
  final List<String> postalCodes;
}

abstract interface class ThaiAddressRepository {
  Future<List<ThaiProvince>> load();
}
