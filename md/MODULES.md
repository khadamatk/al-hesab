# MODULES.md - تقسيم الوحدات

## عَ الحساب (Flutter)

معمارية feature-first بطبقات presentation/domain/data خفيفة، وRiverpod للـstate والاعتماديات، وSQLite عبر repositories.

```text
lib/
  app/                 app shell, routing
  core/
    database/          schema, migrations, transaction helpers
    money/             minor-unit parsing/formatting
    theme/             themes and shared UI
  features/
    workspaces/
    accounts/
    categories/
    counterparties/
    transactions/
    obligations/
    budgets/
    reports/
```

## Module 1 - Database & Money Core

**المسؤولية:** schema versioning، migrations، foreign keys، transaction boundaries، integer minor units.

- `AppDatabase` وschema v1.
- Money parser/formatter لعملات 0 و2 و3 منازل.
- قواعد timestamps والتاريخ المحلي.
- اختبارات القيود وإعادة الفتح والـseed.

## Module 2 - Workspaces

**المسؤولية:** فصل الشخصي والفريلانس والشركة.

- `Workspace` و`WorkspaceRepository`.
- إنشاء/إعادة تسمية/أرشفة واختيار المساحة النشطة.
- منع تسرب الاستعلامات بين المساحات.

## Module 3 - Accounts, Pockets & Channels

**المسؤولية:** أماكن الأموال والأرصدة وقنوات التنفيذ.

- `Account` و`AccountPocket` وbalance queries.
- cash/bank/mobile wallet/PayPal/other.
- PayPal متعدد العملات.
- `PaymentChannel` و`ChannelAccountLink` لـInstaPay وATM وغيرها.
- الرصيد الافتتاحي كحركة.

## Module 4 - Categories & Counterparties

- فئات income/expense لكل مساحة.
- أطراف client/vendor/lender/borrower/other.
- إعادة الربط والأرشفة الآمنة.

## Module 5 - Transactions & Ledger

**المسؤولية:** كل أثر على الرصيد.

- income، expense، opening balance، adjustment.
- same-currency transfer.
- cross-currency transfer بمبلغين فعليين.
- رسوم كحركة مصروف مرتبطة.
- InstaPay metadata وربط البنك.
- ATM bank-to-cash flow.
- voiding بدل تعديل رصيد صامت.

## Module 6 - Obligations

**المسؤولية:** الديون التي على المستخدم والمستحقات التي له.

- payable/receivable lifecycle.
- استلام قرض وسداد دين.
- إنشاء مستحق وتحصيله.
- دفعات جزئية، متبقي، استحقاق، وحالات.

## Module 7 - Budgets & Alerts

- ميزانية عامة أو فئوية لكل مساحة وعملة وشهر.
- expense-only aggregation.
- 80%/100% local notifications مع deduplication.
- إعادة حساب بعد void/edit.

## Module 8 - Reports

- أرصدة الحسابات والجيوب.
- دخل/مصروف/تدفق نقدي.
- تقارير فئات وحسابات وأطراف.
- ديون ومستحقات.
- فصل صارم للمساحات والعملات.

## ترتيب البناء

1. Database & Money Core.
2. Workspaces.
3. Accounts, Pockets, Currencies & Channels.
4. Categories & Counterparties.
5. Transactions & Ledger.
6. Obligations.
7. Budgets & Alerts.
8. Reports.
9. UX/accessibility/release hardening.

## مؤجل

- Bank/PayPal/InstaPay automatic import.
- Live exchange rates.
- AI insights.
- Sync/Auth/Backend.
- Tax/legal accounting module.
