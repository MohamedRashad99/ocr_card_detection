import 'package:flutter_test/flutter_test.dart';

import 'package:testdeploy/main.dart';

void main() {
  testWidgets('App loads the birth-certificate upload page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('قراءة شهادة الميلاد (OCR)'), findsOneWidget);
    expect(find.text('اختر صورة الشهادة'), findsOneWidget);
    expect(find.text('مسح الحقول'), findsOneWidget);
    expect(find.text('اسم الأب'), findsOneWidget);
  });
}
