# إصدار «عَ الحساب»

## ملفات التوقيع الحساسة

ملفا `android/key.properties` و`android/app/al-hesab-upload.jks` محليان ومُستبعدان من Git. يجب نسخهما معًا إلى وسيط آمن ومشفّر. ضياع المفتاح أو كلمات مروره قد يمنع إصدار تحديثات بنفس هوية التطبيق.

لا ترسل محتوى `key.properties` في محادثة أو بريد غير مشفّر، ولا ترفع ملف `.jks` إلى مستودع عام.

## بناء الإصدار

```powershell
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

## تثبيت APK على هاتف Android

1. فعّل خيارات المطور وUSB debugging، أو انقل ملف APK للهاتف.
2. عبر USB: `adb install -r build\app\outputs\flutter-apk\app-release.apk`.
3. إذا كانت نسخة قديمة موقعة بمفتاح مختلف، احذفها أولًا بعد أخذ نسخة من بياناتها.
4. اختبر إنشاء حساب ورصيد، دخلًا ومصروفًا وتحويلًا، دينًا ودفعة، ميزانية، تقريرًا، ونسخة احتياطية واستعادة.

## ملفات التسليم

- APK للتجربة المباشرة: `build\app\outputs\flutter-apk\app-release.apk`.
- AAB لمتجر Google Play: `build\app\outputs\bundle\release\app-release.aab`.

