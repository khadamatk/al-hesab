# إصدار iOS وTestFlight — عَ الحساب 1.3.0

## المتطلبات

- جهاز Mac حديث ونسخة Xcode مدعومة من App Store Connect.
- عضوية Apple Developer Program باسم الناشر المناسب.
- إنشاء App ID بالمعرّف `com.khadamatk.alhesab`.
- إنشاء التطبيق في App Store Connect بالاسم «عَ الحساب» قبل الرفع أو بعده.

## البناء على Mac

```bash
flutter doctor -v
flutter clean
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

داخل Xcode اختر Runner ثم Signing & Capabilities، فعّل Automatically manage signing، واختر Team. بعد نجاح تشغيل التطبيق على iPhone أو Simulator:

```bash
flutter build ipa --release --obfuscate --split-debug-info=build/ios-symbols
```

أو استخدم Product > Archive من Xcode ثم Distribute App > App Store Connect > Upload.

## بيانات App Store Connect المقترحة

- Bundle ID: `com.khadamatk.alhesab`
- Version: `1.3.0`
- Build: `3` (يجب زيادته إذا سبق رفع build 3).
- App Privacy: «لا نجمع بيانات من هذا التطبيق» ما دام الإصدار دون analytics/backend/ads.
- Export Compliance: لا يستخدم تشفيرًا غير معفى؛ `ITSAppUsesNonExemptEncryption = false`.
- يلزم رابط HTTPS عام لسياسة الخصوصية باسم «خدماتك للبرمجيات»؛ وجود السياسة داخل التطبيق وحده لا يغني عن رابط App Store Connect.
- احتفظ بملفات `build/ios-symbols` وملفات dSYM ولا توزعها مع IPA.

## قبل الإرسال للمراجعة

1. اختبر الترقية والنسخ والاستعادة على iPhone فعلي.
2. التقط Screenshots بمقاسات App Store المطلوبة ومن دون بيانات مالية حقيقية.
3. أدخل وصف التطبيق والكلمات المفتاحية والتصنيف العمري وبيانات الدعم.
4. أضف رابط سياسة الخصوصية العام وبيانات التواصل.
5. ارفع إلى TestFlight وابدأ بمجموعة اختبار داخلية قبل المراجعة العامة.
