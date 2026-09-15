# عَ الحساب - Offline Money Manager

تطبيق Flutter عربي لإدارة الأموال الشخصية والفريلانس والشركة: حسابات وأرصدة متعددة العملات، دخل ومصروف، تحويلات، ديون ومستحقات، ميزانيات وتقارير، مع تشغيل محلي كامل.

**الهوية:** «عَ الحساب» - «كل صَرفة محسوبة»  
**Project:** `al_hesab`  
**Package ID:** `com.khadamatk.alhesab`

## النموذج باختصار

- مساحة مستقلة للشخصي والفريلانس والشركة.
- الحساب هو مكان المال؛ لكل حساب pockets حسب العملات.
- PayPal حساب متعدد العملات.
- InstaPay وATM قنوات تنفيذ وليستا أرصدة.
- الرصيد مشتق من ledger الحركات.
- تحويل العملة يسجل المبلغين الفعليين بلا سعر تلقائي.
- الديون payable والمستحقات receivable تدعم دفعات جزئية.

## اقرأ بالترتيب

1. [`BRD.md`](./BRD.md)
2. [`USER_STORIES.md`](./USER_STORIES.md)
3. [`SRS.md`](./SRS.md)
4. [`MODULES.md`](./MODULES.md)
5. [`SCHEMA.md`](./SCHEMA.md)
6. [`CLAUDE.md`](./CLAUDE.md)
7. [`SECURITY.md`](./SECURITY.md)
8. [`KICKOFF.md`](./KICKOFF.md)
9. [`CHANGELOG.md`](./CHANGELOG.md)

## التشغيل

```powershell
flutter pub get
flutter run -d emulator-5554
```

راجع `CHANGELOG.md` لمعرفة آخر مرحلة مكتملة.
