# SCHEMA.md - نموذج البيانات SQLite

## عَ الحساب - Schema Version 4

هذا الملف هو المرجع التنفيذي لقاعدة البيانات. أي اختلاف في الكود يحتاج تحديث هذا الملف و`CHANGELOG.md` أولًا.

## 1. قواعد حاكمة

- `PRAGMA foreign_keys = ON` لكل اتصال.
- كل timestamps بصيغة UTC ISO 8601؛ التاريخ المالي المحلي `YYYY-MM-DD`، والشهر `YYYY-MM`.
- كل مبلغ `INTEGER` بوحدة العملة الصغرى. ممنوع `REAL` و`double` للحفظ أو التجميع.
- لا يوجد رصيد حالي مخزن؛ رصيد الجيب = `SUM(ledger_entries.amount_minor)`.
- لا يوجد `exchange_rate` مخزن أو خدمة سعر حي. المعدل الفعلي مشتق من مبلغَي التحويل عند العرض.
- كل إنشاء/تعديل/حذف لحركة وقيودها وروابطها يتم داخل SQLite transaction.
- السجلات المالية لا تُحذف بطريقة تكسر المراجعة؛ الإلغاء/العكس موثق. حذف draft غير المرتبط فقط مسموح.
- النصوص الاسمية تُقص وتُرفض إن كانت فارغة بعد `trim`.

## 2. الجداول الأساسية

### `app_metadata`

| العمود | النوع |
| :---- | :---- |
| `key` | TEXT PRIMARY KEY |
| `value` | TEXT NOT NULL |

يحفظ `schema_version` ومؤشرات seed فقط، وليس أرصدة أو بيانات مالية.

### `transaction_splits` (من Version 4)

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `transaction_id` | INTEGER NOT NULL | FK transactions، ON DELETE CASCADE |
| `category_id` | INTEGER NOT NULL | فئة مصروف داخل نفس مساحة العملية |
| `amount_minor` | INTEGER NOT NULL | أكبر من صفر، ومجموع الأجزاء يساوي إجمالي العملية |
| `created_at` | TEXT NOT NULL | UTC |

العملية المقسمة لها قيد خصم واحد فقط؛ أجزاء الفئات تستخدم في التقارير والميزانيات ولا تُنشئ خصومات إضافية.

### `workspaces`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `name` | TEXT NOT NULL COLLATE NOCASE | اسم فريد بين المساحات النشطة |
| `type` | TEXT NOT NULL | CHECK: `personal`, `freelance`, `business`, `other` |
| `is_archived` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

فهرس فريد: `UNIQUE(name COLLATE NOCASE)`.

### `currencies`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `code` | TEXT PRIMARY KEY COLLATE NOCASE | ISO-like uppercase code |
| `symbol` | TEXT NOT NULL | |
| `decimal_digits` | INTEGER NOT NULL DEFAULT 2 | CHECK بين 0 و3 |
| `is_active` | INTEGER NOT NULL DEFAULT 1 | CHECK 0/1 |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

Seed idempotent: EGP، USD، MAD. لا يتغير `decimal_digits` بعد وجود ledger entries للعملة.

### `accounts`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `workspace_id` | INTEGER NOT NULL | FK workspaces، ON DELETE RESTRICT |
| `name` | TEXT NOT NULL COLLATE NOCASE | فريد داخل المساحة |
| `type` | TEXT NOT NULL | CHECK: `cash`, `bank`, `mobile_wallet`, `paypal`, `other` |
| `institution` | TEXT | اسم البنك/المزود اختياري |
| `identifier_hint` | TEXT | آخر 4 أرقام أو وصف غير سري؛ لا تحفظ بيانات دخول |
| `allow_negative` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `is_archived` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

فهرس فريد: `(workspace_id, name COLLATE NOCASE)`.

### `account_pockets`

كل صف هو رصيد عملة داخل حساب؛ PayPal يمكن أن يملك عدة صفوف.

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `account_id` | INTEGER NOT NULL | FK accounts، ON DELETE RESTRICT |
| `currency_code` | TEXT NOT NULL | FK currencies، ON UPDATE CASCADE ON DELETE RESTRICT |
| `is_archived` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

قيد فريد: `UNIQUE(account_id, currency_code)`.

### `categories`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `workspace_id` | INTEGER NOT NULL | FK workspaces، ON DELETE RESTRICT |
| `name` | TEXT NOT NULL COLLATE NOCASE | |
| `kind` | TEXT NOT NULL | CHECK: `income`, `expense` |
| `icon`, `color_hex` | TEXT | اختياريان |
| `is_system` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `is_archived` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

قيد فريد: `UNIQUE(workspace_id, kind, name COLLATE NOCASE)`.

### `counterparties`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `workspace_id` | INTEGER NOT NULL | FK workspaces، ON DELETE RESTRICT |
| `name` | TEXT NOT NULL COLLATE NOCASE | |
| `type` | TEXT NOT NULL DEFAULT 'other' | client/vendor/lender/borrower/other |
| `contact_note` | TEXT | لا تحفظ أسرارًا |
| `is_archived` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

قيد فريد: `UNIQUE(workspace_id, name COLLATE NOCASE)`.

### `payment_channels`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `workspace_id` | INTEGER NOT NULL | FK workspaces، ON DELETE RESTRICT |
| `name` | TEXT NOT NULL COLLATE NOCASE | مثال InstaPay أو ATM |
| `type` | TEXT NOT NULL | instapay/atm/bank_transfer/paypal/manual/other |
| `is_archived` | INTEGER NOT NULL DEFAULT 0 | CHECK 0/1 |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

قيد فريد: `UNIQUE(workspace_id, name COLLATE NOCASE)`.

### `channel_accounts`

يربط قناة مثل InstaPay بالحسابات البنكية التي يمكن استخدامها منها.

| العمود | النوع |
| :---- | :---- |
| `channel_id` | INTEGER NOT NULL FK payment_channels ON DELETE CASCADE |
| `account_id` | INTEGER NOT NULL FK accounts ON DELETE CASCADE |

PRIMARY KEY: `(channel_id, account_id)`. طبقة repository تتحقق أن الحساب والقناة في المساحة نفسها.

## 3. سجل الحركات

### `transactions`

رأس العملية ومعناها التجاري. الأثر المالي موجود فقط في `ledger_entries`.

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `workspace_id` | INTEGER NOT NULL | FK workspaces، ON DELETE RESTRICT |
| `type` | TEXT NOT NULL | `income`, `expense`, `transfer`, `opening_balance`, `adjustment`, `obligation_funding`, `obligation_settlement` |
| `category_id` | INTEGER | FK categories، ON DELETE RESTRICT |
| `counterparty_id` | INTEGER | FK counterparties، ON DELETE SET NULL |
| `channel_id` | INTEGER | FK payment_channels، ON DELETE SET NULL |
| `related_transaction_id` | INTEGER | FK transactions، ON DELETE SET NULL؛ رسوم/نقل بين مساحات |
| `occurred_on` | TEXT NOT NULL | `YYYY-MM-DD` محلي |
| `note` | TEXT | |
| `status` | TEXT NOT NULL DEFAULT 'posted' | posted/voided |
| `void_reason` | TEXT | إلزامي عند voided |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

Indexes: `(workspace_id, occurred_on)`, `(category_id, occurred_on)`, `counterparty_id`, `channel_id`.

### `ledger_entries`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `transaction_id` | INTEGER NOT NULL | FK transactions، ON DELETE CASCADE |
| `pocket_id` | INTEGER NOT NULL | FK account_pockets، ON DELETE RESTRICT |
| `role` | TEXT NOT NULL | source/destination/single |
| `amount_minor` | INTEGER NOT NULL | signed non-zero؛ موجب يزيد الرصيد وسالب يخفضه |
| `created_at` | TEXT NOT NULL | UTC |

Indexes: `(pocket_id, transaction_id)` و`transaction_id`.  
رصيد الجيب يجمع قيود transactions ذات `status = 'posted'` فقط.

قواعد repository داخل transaction واحدة:

- income: قيد `single` موجب وفئة income.
- expense: قيد `single` سالب وفئة expense.
- opening_balance/adjustment: قيد واحد signed مع note/سبب.
- transfer: قيدان فقط؛ source سالب وdestination موجب.
- تحويل نفس العملة: القيمة المطلقة للقيدين متساوية.
- تحويل مختلف العملات: العملتان مختلفتان والقيمتان الفعليتان موجبتان وغير صفريتين؛ effective rate مشتق فقط.
- كل pocket في الحركة ينتمي لمساحة transaction. النقل بين المساحات يستخدم حركتين مرتبطتين.
- fee مصروف مستقل مرتبط بالتحويل عبر `related_transaction_id`.

### `transaction_fx_details`

يحفظ حقيقة التسوية العابرة للعملات سواء كانت بين حسابين يملكهما المستخدم أو دفعة لطرف خارجي. لا يمثل سعرًا حيًا ولا ينفذ تحويلًا تلقائيًا.

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `transaction_id` | INTEGER PRIMARY KEY | FK transactions، ON DELETE CASCADE |
| `source_currency_code` | TEXT NOT NULL | FK currencies، ON DELETE RESTRICT |
| `source_amount_minor` | INTEGER NOT NULL | CHECK > 0؛ ما خُصم فعليًا |
| `destination_currency_code` | TEXT NOT NULL | FK currencies، ON DELETE RESTRICT |
| `destination_amount_minor` | INTEGER NOT NULL | CHECK > 0؛ ما وصل فعليًا للحساب أو الطرف |
| `created_at` | TEXT NOT NULL | UTC |

قيد CHECK يمنع تساوي العملتين. في تحويل مملوك للمستخدم تطابق القيم قيود source/destination. في دفعة لطرف خارجي قد يوجد ledger entry للمصدر فقط، بينما يحتفظ هذا الجدول بالمبلغ الذي استلمه الطرف. الرسوم تبقى transaction مصروف مستقلة بعملتها الفعلية.

## 4. الديون والمستحقات

### `obligations`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `workspace_id` | INTEGER NOT NULL | FK workspaces، ON DELETE RESTRICT |
| `counterparty_id` | INTEGER NOT NULL | FK counterparties، ON DELETE RESTRICT |
| `direction` | TEXT NOT NULL | CHECK payable/receivable |
| `nature` | TEXT NOT NULL | CHECK loan/credit_purchase/invoice/money_lent/other |
| `currency_code` | TEXT NOT NULL | FK currencies، ON DELETE RESTRICT |
| `category_id` | INTEGER | FK categories، ON DELETE RESTRICT؛ income للـinvoice وexpense للـcredit_purchase |
| `principal_minor` | INTEGER NOT NULL | CHECK > 0 |
| `opened_on` | TEXT NOT NULL | YYYY-MM-DD |
| `due_on` | TEXT | YYYY-MM-DD، يجب ألا يسبق opened_on |
| `note` | TEXT | |
| `status` | TEXT NOT NULL DEFAULT 'open' | open/partial/settled/cancelled |
| `cancel_reason` | TEXT | إلزامي عند cancelled |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

Indexes: `(workspace_id, direction, status, due_on)` و`counterparty_id`.

قواعد repository: `loan` payable، `credit_purchase` payable، `invoice` receivable، و`money_lent` receivable. invoice يحتاج فئة income، وcredit_purchase يحتاج فئة expense؛ loan/money_lent لا يحتاجان فئة لأن حركة الأصل ليست دخلًا أو مصروفًا.

### `obligation_fundings`

يربط حركة أصل القرض أو المال المُقرض بالالتزام من غير تصنيفها دخلًا أو مصروفًا.

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `obligation_id` | INTEGER NOT NULL | FK obligations، ON DELETE RESTRICT |
| `transaction_id` | INTEGER NOT NULL UNIQUE | FK transactions، ON DELETE RESTRICT |
| `amount_minor` | INTEGER NOT NULL | CHECK > 0؛ بعملة الالتزام |
| `created_at` | TEXT NOT NULL | UTC |

مجموع التمويلات المنشورة لا يتجاوز أصل الالتزام. loan funding يزيد pocket، وmoney_lent funding يخفضه؛ كلاهما خارج income/expense.

### `obligation_payments`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `obligation_id` | INTEGER NOT NULL | FK obligations، ON DELETE RESTRICT |
| `transaction_id` | INTEGER NOT NULL UNIQUE | FK transactions، ON DELETE RESTRICT |
| `amount_minor` | INTEGER NOT NULL | CHECK > 0؛ بعملة الالتزام |
| `created_at` | TEXT NOT NULL | UTC |

المتبقي = `principal_minor - SUM(posted obligation_payments.amount_minor)`. repository يمنع مجموع دفعات أكبر من الأصل ويحدّث الحالة داخل transaction.

تقارير الـMVP cash basis: collection لفاتورة invoice يدخل ضمن income، وتسوية credit_purchase تدخل ضمن expense. تمويل/سداد أصل loan أو money_lent يؤثر في الرصيد والالتزام فقط، وأي فائدة أو رسوم تسجل expense transaction منفصلة مرتبطة.

## 5. الميزانيات

### `budgets`

| العمود | النوع | ملاحظات |
| :---- | :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT | |
| `workspace_id` | INTEGER NOT NULL | FK workspaces، ON DELETE RESTRICT |
| `currency_code` | TEXT NOT NULL | FK currencies، ON DELETE RESTRICT |
| `category_id` | INTEGER | FK expense category، ON DELETE RESTRICT؛ NULL عام |
| `monthly_limit_minor` | INTEGER NOT NULL | CHECK > 0 |
| `alert_threshold_percent` | INTEGER NOT NULL DEFAULT 80 | CHECK 1..99 |
| `month` | TEXT NOT NULL | YYYY-MM |
| `created_at`, `updated_at` | TEXT NOT NULL | UTC |

```sql
CREATE UNIQUE INDEX uq_category_budget
ON budgets(workspace_id, currency_code, category_id, month)
WHERE category_id IS NOT NULL;

CREATE UNIQUE INDEX uq_general_budget
ON budgets(workspace_id, currency_code, month)
WHERE category_id IS NULL;
```

### `budget_alerts`

| العمود | النوع |
| :---- | :---- |
| `id` | INTEGER PK AUTOINCREMENT |
| `budget_id` | INTEGER NOT NULL FK budgets ON DELETE CASCADE |
| `level` | TEXT NOT NULL CHECK threshold/exceeded |
| `triggered_at` | TEXT NOT NULL |

قيد فريد: `UNIQUE(budget_id, level)`.

## 6. العلاقات

```text
workspaces 1 ──< accounts 1 ──< account_pockets >──1 currencies
workspaces 1 ──< categories
workspaces 1 ──< counterparties
workspaces 1 ──< payment_channels >──< accounts
workspaces 1 ──< transactions 1 ──< ledger_entries >──1 account_pockets
transactions 1 ──0..1 transaction_fx_details
counterparties 1 ──< obligations 1 ──< obligation_fundings/payments >──1 transactions
workspaces/currencies/categories 1 ──< budgets 1 ──< budget_alerts
```

## 7. Seed وmigrations

- Schema version 1 يُنشأ في transaction واحدة.
- Seed currencies: EGP، USD، MAD باستخدام upsert لا يكرر البيانات.
- Seed category templates تُنسخ لكل مساحة جديدة: مصروفات أساسية + «أخرى»، ودخل أساسي + «دخل آخر».
- قنوات InstaPay وATM لا تُنشأ عالميًا؛ يضيفها المستخدم داخل المساحة ويربطها بالحساب الصحيح.
- كل migration future-only، idempotent في حدود الإصدار، ومختبرة من نسخة سابقة فعلية.

## 8. اختبارات قبول قاعدة البيانات

- إنشاء وإعادة فتح DB مع foreign keys مفعلة.
- seed لا يتكرر.
- uniqueness لكل المساحات والحسابات والجيوب والفئات.
- تحويل minor units لعملات 0 و2 و3 منازل بدون `double`.
- رصيد افتتاحي ودخل ومصروف وتسوية ينتجون الرصيد المتوقع.
- تحويل نفس العملة يحافظ على الإجمالي؛ الرسوم وحدها تخفضه.
- تحويل USD إلى EGP/MAD يحتفظ بالمبلغين بلا سعر تلقائي.
- دفعة PayPal لطرف خارجي تحتفظ بما خُصم وما استلمه الطرف حتى من دون destination pocket مملوك للمستخدم.
- InstaPay يؤثر في البنك المرتبط ولا ينشئ رصيد قناة.
- ATM يخفض البنك ويزيد الكاش، والعمولة مصروف مستقل.
- PayPal متعدد العملات يفصل كل pocket.
- الدفعات الجزئية وحالات الالتزام والمتبقي وعدم تجاوز الأصل.
- تمويل loan/money_lent مرتبط بالالتزام، محدود بالأصل، ويغير الرصيد بلا تلويث الدخل/المصروف.
- invoice/credit_purchase يظهران cash-basis، بينما أصل loan/money_lent لا يلوث تقارير الدخل والمصروف.
- voided transactions لا تدخل في الرصيد والتقارير.
- لا تختلط workspaces أو currencies في أي aggregation.

## 9. جداول مؤجلة

- `import_batches` و`import_rows` بعد اختيار آلية الاستيراد البنكي.
- `ai_insights` بعد حسم الخصوصية والخدمة.
- جداول sync/auth فقط إذا تغير قرار single-device.
