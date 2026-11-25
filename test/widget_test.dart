import 'package:flutter_test/flutter_test.dart';

import 'package:testdeploy/main.dart';

void main() {
  testWidgets('App loads the birth-certificate upload page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('ماسح شهادة الميلاد المصرية'), findsOneWidget);
    expect(find.text('اختر صورة الشهادة'), findsOneWidget);
    expect(find.text('مسح الحقول'), findsOneWidget);
    expect(find.text('اسم الأب'), findsOneWidget);
    expect(find.text('بيانات المولود'), findsOneWidget);
    expect(find.text('بيانات الأب'), findsOneWidget);
    expect(find.text('بيانات الأم'), findsOneWidget);
    expect(find.text('بيانات الشهادة'), findsOneWidget);
    expect(find.text('الرقم القومي للأب'), findsOneWidget);
    expect(find.text('ديانة الأم'), findsOneWidget);
  });
}
