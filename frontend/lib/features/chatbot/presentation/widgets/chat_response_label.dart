// ป้ายอิงชนิดผลที่บริการส่งมา ไม่เดาจากข้อมูลการค้นหา
String chatResponseLabel(String? kind, {bool hasQuestions = false}) {
  if (hasQuestions) return 'สอบถามข้อมูลเพิ่มเติม';
  return switch (kind) {
    'clarification' => 'สอบถามข้อมูลเพิ่มเติม',
    'comparison' => 'ผลการเปรียบเทียบ',
    'recommendation' => 'สรุปคำแนะนำ',
    'item_details' => 'ข้อมูลสินค้า',
    'technical' => 'ข้อมูลทางเทคนิค',
    'overview' => 'รายการอุปกรณ์',
    'app_information' => 'ข้อมูลแอป',
    'conversation' || 'information' => 'คำตอบ',
    _ => 'สรุปคำแนะนำ',
  };
}
