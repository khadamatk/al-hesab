# CLAUDE.md - سياق المشروع الثابت

## عَ الحساب - Offline Money Manager

هذا الملف يُقرأ أول كل جلسة. القرارات هنا لا تتغير من غير نقاش صريح مع المستخدم؛ سجل التنفيذ في `CHANGELOG.md`.

## تعليمات إجبارية

1. اقرأ `CHANGELOG.md` في بداية الجلسة.
2. اعتبر `SCHEMA.md` مرجع قاعدة البيانات و`SRS.md` مرجع السلوك.
3. حدّث `CHANGELOG.md` في نهاية العمل بما تم ولماذا وما تبقى.
4. لا تبدأ مرحلة قبل نجاح exit criteria للمرحلة السابقة.

## القرارات المعمارية الثابتة

| القرار | القيمة | السبب |
| :---- | :---- | :---- |
| Stack | Flutter/Dart | Android + iOS بكود واحد |
| Identity | `al_hesab` / `com.khadamatk.alhesab` | الاسم «عَ الحساب» |
| State | Riverpod | DI وحالة قابلة للاختبار |
| Database | SQLite عبر `sqflite` | Offline-first بلا backend |
| User model | Single-user بلا auth | كل تنصيب مستقل |
| Financial spaces | personal/freelance/business/other | منع خلط السياقات |
| Accounts | account containers + currency pockets | دعم PayPal متعدد العملات |
| Balances | مشتقة من ledger entries | مراجعة واتساق بدل رقم mutable |
| Money | Integer minor units | منع أخطاء floating point |
| Channels | InstaPay/ATM وغيرها metadata مرتبطة بحساب | القناة ليست رصيدًا |
| FX | مبلغ مصدر ومبلغ وجهة فعليان فقط | بلا سعر حي أو تخمين |
| Debts | payable + receivable + partial payments | احتياجات الشخصي والفريلانس والشركة |

## قواعد لا يجب كسرها

1. ممنوع تخزين أو تجميع المال بـ`double` أو SQLite `REAL`.
2. ممنوع حقل current balance قابل للتعديل؛ الرصيد = مجموع القيود المنشورة.
3. ممنوع اعتبار التحويل الداخلي دخلًا أو مصروفًا؛ الرسوم فقط مصروف.
4. InstaPay لا يملك balance أو pocket؛ يؤثر في البنك المختار ويحفظ كقناة.
5. ATM withdrawal تحويل bank-to-cash؛ الرسوم حركة منفصلة.
6. PayPal حساب متعدد الجيوب عند الحاجة، وليس حسابًا منفصلًا لكل عملة.
7. التحويل العابر للعملات يحتاج مبلغين صريحين؛ لا سعر صرف تلقائي ولا `exchange_rate` مخزن كحقيقة.
8. المساحات والعملات لا تختلط في aggregation. النقل بين مساحتين حركتان مرتبطتان بتصنيف واضح.
9. كل عملية متعددة الصفوف داخل SQLite transaction مع foreign keys مفعّلة.
10. الحركات المالية posted لا تُحذف بصمت؛ void/reversal له سبب وأثر قابل للمراجعة.
11. استيراد البنك والأسعار الحية وAI وsync مؤجلة.
12. لا تحفظ بيانات دخول أو أرقام بطاقات/حسابات كاملة أو أسرار داخل التطبيق.
13. تقارير MVP cash basis: invoice collection دخل وcredit purchase payment مصروف؛ أصل loan/money lent ليس دخلًا أو مصروفًا، والفوائد/الرسوم منفصلة.

## مراجع التنفيذ

- `BRD.md`: نطاق المنتج ولماذا.
- `USER_STORIES.md`: سيناريوهات القبول.
- `SRS.md`: المتطلبات المرقمة.
- `MODULES.md`: الوحدات وترتيب البناء.
- `SCHEMA.md`: الجداول والقيود والاختبارات.
- `SECURITY.md`: الأمان والخصوصية.
- `KICKOFF.md`: بوابة المرحلة الحالية.
