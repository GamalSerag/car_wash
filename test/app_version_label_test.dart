import 'package:car_wash/screens/splash_screen.dart';
import 'package:car_wash/widgets/app_version_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  testWidgets(
    'Splash shows installed version at physical bottom right in RTL',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'car_wash',
        packageName: 'com.maghsala.car_wash',
        version: '1.0.9',
        buildNumber: '11',
        buildSignature: '',
      );
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: SplashScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('الإصدار 1.0.9 (11)'), findsOneWidget);
      final rect = tester.getRect(find.byType(AppVersionLabel));
      expect(rect.right, closeTo(304, 1));
      expect(rect.bottom, closeTo(624, 1));
      expect(tester.takeException(), isNull);
    },
  );
}
