class ItemDetailRouteArgs {
  const ItemDetailRouteArgs({this.ownerLoadingLayout = false});

  // เลือกเฉพาะรูปแบบระหว่างโหลด สิทธิ์จัดการยังใช้ข้อมูลที่โหลดจริง
  final bool ownerLoadingLayout;
}
