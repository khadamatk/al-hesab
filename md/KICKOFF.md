# KICKOFF.md - بوابة التنفيذ

## Phase 12 - العملة الافتراضية 1.4.0

- اكتمل فصل تفضيل الحساب عن تفضيل جيب العملة؛ يمكن اختيار MAD افتراضيًا داخل حساب «في جيبي» مع بقاء الحساب نفسه مفضلاً.
- Schema Version 3 يرقّي القواعد القديمة في مكانها ويحفظ الحسابات والجيوب والحركات والأرصدة.
- الحسابات الجديدة تجعل أول عملة مضافة افتراضية، والحسابات القديمة تتذكر آخر جيب مستخدم إلى أن يختار المستخدم عملة ثابتة.

## Phase 11 - تحديث تجربة الاستخدام 1.3.0

- أُغلقت بوابة الأمان وإصدار APK النهائي المموّه والموقع جاهز للتوزيع والاختبار الفعلي.
- اكتمل البحث وفلاتر الحركات، تكرار العملية، مراجعة ما قبل الحفظ، عرض الحساب المفضّل والرصيد في النموذج، ومقارنة التقارير بالفترة السابقة.
- اكتمل تقوية إعداد Android بمنع النسخ السحابي التلقائي والاتصال الواضح غير المشفّر.
- لا توجد مهاجرة قاعدة بيانات في هذا الإصدار، لذلك الترقية من 1.1 تحفظ البيانات كما هي على Schema Version 2.
- المرحلة التالية: recurring templates بموافقة يدوية، مرفقات محلية، وتقسيم العملية، وكلها تحتاج Schema Version 3 واختبارات ترقية منفصلة.

## Phase 10 - تحديث الاستخدام الفعلي 1.1.0

- اكتمل تنفيذ تصحيح الحركات، الفئات الرئيسية والفرعية، تعديل الفئات، أولوية الحسابات، وفلاتر التقارير في 2026-08-13.
- Schema Version 2 يرقّي بيانات Version 1 في مكانها من غير حذف الحركات أو الأرصدة.
- نجح التحليل والاختبارات واختبار ترقية قاعدة Version 1 وبناء APK Release موقع.
- المتبقي: تثبيت `releases/1.1.0/al-hesab-1.1.0.apk` فوق النسخة المستخدمة على الهاتف وتنفيذ قبول فعلي قصير قبل اعتماد التحديث نهائيًا.

## الحالة

- Phase 0 مكتملة: Flutter/Android والقالب المشترك.
- Phase 1 مكتملة: التطبيق والهوية وRTL والمحاكي والأيقونة المؤقتة.
- Phase 2A مكتملة: نموذج المنتج والوثائق الجديدة اجتازت فحوص الاتساق.
- Phase 2B مكتملة في 2026-08-04: Schema Version 1 والـledger والالتزامات و20 اختبارًا وDebug APK وAndroid smoke test.
- Phase 3 مكتملة في 2026-08-04: واجهات المساحات والحسابات والجيوب والعملات والقنوات والفئات والأطراف، مع PayPal متعدد العملات وربط InstaPay بالبنك و23 اختبارًا ناجحًا.
- Phase 4 مكتملة في 2026-08-04: الرصيد الافتتاحي والدخل والمصروف والتحويل وATM وFX والديون والمستحقات والدفعات الجزئية وحركة أصل القروض.
- Phase 5 مكتملة في 2026-08-04: الميزانيات الشهرية الإجمالية والفئوية، الفصل حسب المساحة والعملة، وتنبيهات 80% و100% غير المتكررة.
- Phase 6 مكتملة في 2026-08-04: تقارير الأرصدة والتدفق النقدي والفئات والديون والمستحقات مع فصل العملات والمساحات والأشهر.
- Phase 7 مكتملة في 2026-08-04: نظام التصميم والهوية والشعار الجديد والوضع الداكن والحالات الفارغة والاستجابة للنص الكبير والشاشات الصغيرة.
- Phase 8 مكتملة في 2026-08-04: النسخ المحلي والاستعادة المفحوصة والرجوع الآمن واختبارات التلف وتدقيق الأسرار والسجلات والاعتمادات.
- Phase 9 Release Candidate جاهز في 2026-08-04: APK/AAB موقعان، سياسة الخصوصية، checksums، واختبار تثبيت وترقية على المحاكي.
- المتبقي لإغلاق Phase 9: حفظ نسخة خارجية مشفرة من مفتاح التوقيع، واختبار القبول على هاتف Android فعلي عند توصيله.

## Phase 2B - Database Foundation (Completed)

1. استبدال schema المؤقت في `AppDatabase` بـSchema Version 1 من `SCHEMA.md`.
2. إنشاء migrations forward-only وtransaction helpers.
3. تنفيذ Money parser/formatter بدون `double` لعملات 0 و2 و3 منازل.
4. إنشاء workspaces/currencies/accounts/pockets/categories/counterparties/channels.
5. إنشاء transactions/ledger_entries وقواعد العمليات الذرية.
6. إنشاء obligations/payments.
7. إنشاء budgets/alerts.
8. seed idempotent للعملات وقوالب الفئات.
9. repositories/fixtures المطلوبة لاختبار القواعد، بدون بناء UI نهائي بعد.

## Definition of Done - Phase 2B

- `PRAGMA foreign_keys = ON` مثبت بالاختبار بعد الإنشاء وإعادة الفتح.
- schema version وmigrations والseed لا تتكرر.
- كل قيود uniqueness وFK وCHECK تعمل.
- لا يوجد تخزين مالي `REAL`/`double` أو current balance mutable.
- اختبارات minor units لعملات 0 و2 و3 منازل، مع رفض إدخال غير صالح.
- اختبارات opening balance/income/expense/adjustment والرصيد الناتج.
- تحويل نفس العملة ذري ويحافظ على الإجمالي؛ الرسوم فقط تخفضه.
- تحويل USD إلى EGP/MAD يحفظ المبلغين بلا rate تلقائي.
- PayPal متعدد الجيوب وInstaPay كقناة وATM bank-to-cash مختبرون.
- payable/receivable والدفعات الجزئية وعدم تجاوز الأصل مختبرون.
- voided transactions مستبعدة من الرصيد والتقارير.
- workspace/currency isolation مثبتة fixtures معروفة.
- `dart format`, `flutter analyze`, `flutter test`, وDebug APK ناجحة.

## الترتيب بعد Phase 2B

1. Workspaces + accounts + pockets + currencies + channels UI.
2. Categories + counterparties UI.
3. Income/expense/transfers/obligations UI.
4. Budgets & alerts.
5. Reports.
6. Backup/security/release hardening.

## أوامر التحقق

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```
