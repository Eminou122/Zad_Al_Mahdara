const supportWhatsAppNumber = '22249413435';
const supportWhatsAppMessage =
    'السلام عليكم ورحمة الله وبركاته، أحتاج إلى المساعدة بخصوص الفرق والانضمام إليها في تطبيق زاد المحظرة.';

Uri supportWhatsAppUri() => Uri.parse(
  'https://wa.me/$supportWhatsAppNumber?text=${Uri.encodeComponent(supportWhatsAppMessage)}',
);
