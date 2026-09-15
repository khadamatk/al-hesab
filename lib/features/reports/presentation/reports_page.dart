import 'package:flutter/material.dart';

import '../../../core/money/minor_units.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../data/reports_repository.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.repository,
    required this.workspaceId,
  });
  final ReportsRepository repository;
  final int workspaceId;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late String month;
  late DateTime from, to;
  String period = 'month';
  ReportsSnapshot? snapshot;
  ReportsSnapshot? previousSnapshot;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = _formatMonth(now);
    from = DateTime(now.year, now.month);
    to = DateTime(now.year, now.month + 1).subtract(const Duration(days: 1));
    load();
  }

  @override
  void didUpdateWidget(covariant ReportsPage old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId) load();
  }

  Future<void> load() async {
    final days = to.difference(from).inDays + 1;
    final previousTo = from.subtract(const Duration(days: 1));
    final previousFrom = previousTo.subtract(Duration(days: days - 1));
    final values = await Future.wait([
      widget.repository.loadRange(
        widget.workspaceId,
        _formatDate(from),
        _formatDate(to),
      ),
      widget.repository.loadRange(
        widget.workspaceId,
        _formatDate(previousFrom),
        _formatDate(previousTo),
      ),
    ]);
    if (mounted) {
      setState(() {
        snapshot = values[0];
        previousSnapshot = values[1];
      });
    }
  }

  void changeMonth(int delta) {
    final p = month.split('-');
    final d = DateTime(int.parse(p[0]), int.parse(p[1]) + delta);
    setState(() {
      month = _formatMonth(d);
      from = DateTime(d.year, d.month);
      to = DateTime(d.year, d.month + 1).subtract(const Duration(days: 1));
      period = 'month';
      snapshot = null;
      previousSnapshot = null;
    });
    load();
  }

  void _selectPeriod(String value) {
    final now = DateTime.now();
    setState(() {
      period = value;
      if (value == 'day') from = to = DateTime(now.year, now.month, now.day);
      if (value == 'week') {
        from = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
        to = from.add(const Duration(days: 6));
      }
      if (value == 'last7') {
        to = DateTime(now.year, now.month, now.day);
        from = to.subtract(const Duration(days: 6));
      }
      if (value == 'month') {
        month = _formatMonth(now);
        from = DateTime(now.year, now.month);
        to = DateTime(
          now.year,
          now.month + 1,
        ).subtract(const Duration(days: 1));
      }
      snapshot = null;
      previousSnapshot = null;
    });
    load();
  }

  Future<void> _customPeriod() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (range == null) return;
    setState(() {
      period = 'custom';
      from = range.start;
      to = range.end;
      snapshot = null;
      previousSnapshot = null;
    });
    load();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'التقارير',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'كل عملة مستقلة — بدون إجماليات مضللة',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => changeMonth(-1),
              icon: const Icon(Icons.chevron_right),
            ),
            Text(month, textDirection: TextDirection.ltr),
            IconButton(
              onPressed: () => changeMonth(1),
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('اليوم'),
                selected: period == 'day',
                onSelected: (_) => _selectPeriod('day'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('هذا الأسبوع'),
                selected: period == 'week',
                onSelected: (_) => _selectPeriod('week'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('آخر 7 أيام'),
                selected: period == 'last7',
                onSelected: (_) => _selectPeriod('last7'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('الشهر'),
                selected: period == 'month',
                onSelected: (_) => _selectPeriod('month'),
              ),
              const SizedBox(width: 6),
              ActionChip(
                label: Text(
                  period == 'custom'
                      ? '${_formatDate(from)} — ${_formatDate(to)}'
                      : 'فترة مخصصة',
                ),
                onPressed: _customPeriod,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: snapshot == null
              ? const Center(child: CircularProgressIndicator())
              : _isEmpty(snapshot!)
              ? const AppEmptyState(
                  icon: Icons.insights_outlined,
                  title: 'التقارير هتظهر مع أول حركة',
                  message:
                      'أضف حسابًا ورصيدًا أو سجّل دخلًا ومصروفًا، وهنا هتلاقي الصورة المالية كاملة.',
                )
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    children: [
                      if (previousSnapshot != null)
                        _PeriodComparison(snapshot!, previousSnapshot!),
                      _sectionTitle(context, 'التدفق النقدي خلال الفترة'),
                      if (snapshot!.cashFlow.isEmpty)
                        const _EmptyCard('لا توجد حركة مالية خلال هذه الفترة')
                      else
                        ...snapshot!.cashFlow.map((e) => _CashFlowCard(e)),
                      _sectionTitle(context, 'أرصدة الحسابات الحالية'),
                      if (snapshot!.balances.isEmpty)
                        const _EmptyCard('لا توجد حسابات بأرصدة')
                      else
                        ..._groupBalances(snapshot!.balances).entries.map(
                          (entry) => _CurrencyBalances(entry.key, entry.value),
                        ),
                      _sectionTitle(context, 'الفئات خلال الفترة'),
                      if (snapshot!.categories.isEmpty)
                        const _EmptyCard('لا توجد بيانات فئات خلال هذه الفترة')
                      else
                        ..._groupCategories(snapshot!.categories).entries.map(
                          (entry) => _CategoryCard(entry.key, entry.value),
                        ),
                      _sectionTitle(context, 'الديون والمستحقات المفتوحة'),
                      if (snapshot!.obligations.isEmpty)
                        const _EmptyCard('لا توجد التزامات مفتوحة')
                      else
                        ...snapshot!.obligations.map((e) => _ObligationCard(e)),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );

  static String _formatMonth(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static bool _isEmpty(ReportsSnapshot value) =>
      value.balances.isEmpty &&
      value.cashFlow.isEmpty &&
      value.categories.isEmpty &&
      value.obligations.isEmpty;
}

Widget _sectionTitle(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 6),
  child: Text(text, style: Theme.of(context).textTheme.titleLarge),
);

class _PeriodComparison extends StatelessWidget {
  const _PeriodComparison(this.current, this.previous);

  final ReportsSnapshot current;
  final ReportsSnapshot previous;

  @override
  Widget build(BuildContext context) {
    final oldByCurrency = {
      for (final item in previous.cashFlow) item.currencyCode: item,
    };
    if (current.cashFlow.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'مقارنة بالفترة السابقة',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (final item in current.cashFlow)
              _ComparisonLine(item, oldByCurrency[item.currencyCode]),
          ],
        ),
      ),
    );
  }
}

class _ComparisonLine extends StatelessWidget {
  const _ComparisonLine(this.current, this.previous);

  final CashFlowReportItem current;
  final CashFlowReportItem? previous;

  @override
  Widget build(BuildContext context) {
    final oldNet = previous?.netMinor ?? 0;
    final difference = current.netMinor - oldNet;
    final improved = difference >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            current.currencyCode,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Icon(
            improved ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            color: improved
                ? Colors.green
                : Theme.of(context).colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 5),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${difference >= 0 ? '+' : ''}${MinorUnits.format(difference, decimalDigits: 2)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: improved
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CashFlowCard extends StatelessWidget {
  const _CashFlowCard(this.item);
  final CashFlowReportItem item;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.currency_exchange),
              const SizedBox(width: 8),
              Text(
                item.currencyCode,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const Divider(),
          _moneyRow('الدخل', item.incomeMinor, item.currencyCode, Colors.green),
          _moneyRow(
            'المصروف',
            item.expenseMinor,
            item.currencyCode,
            Theme.of(context).colorScheme.error,
          ),
          _moneyRow(
            'الصافي',
            item.netMinor,
            item.currencyCode,
            item.netMinor >= 0
                ? Colors.green
                : Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    ),
  );
}

class _CurrencyBalances extends StatelessWidget {
  const _CurrencyBalances(this.currency, this.items);
  final String currency;
  final List<BalanceReportItem> items;
  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (sum, e) => sum + e.balanceMinor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _moneyRow(
              'إجمالي $currency',
              total,
              currency,
              Theme.of(context).colorScheme.primary,
            ),
            const Divider(),
            ...items.map(
              (e) => _moneyRow(e.accountName, e.balanceMinor, currency, null),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard(this.currency, this.items);
  final String currency;
  final List<CategoryReportItem> items;
  @override
  Widget build(BuildContext context) {
    final max = items.fold<int>(
      1,
      (m, e) => e.amountMinor > m ? e.amountMinor : m,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.category_outlined),
                const SizedBox(width: 8),
                Text(currency, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            ...items.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  children: [
                    _moneyRow(
                      '${e.name} (${e.kind == 'income' ? 'دخل' : 'مصروف'})',
                      e.amountMinor,
                      currency,
                      e.kind == 'income' ? Colors.green : null,
                    ),
                    LinearProgressIndicator(
                      value: e.amountMinor / max,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObligationCard extends StatelessWidget {
  const _ObligationCard(this.item);
  final ObligationReportItem item;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.handshake_outlined),
              const SizedBox(width: 8),
              Text(
                item.currencyCode,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const Divider(),
          _moneyRow(
            'عليك',
            item.payableMinor,
            item.currencyCode,
            Theme.of(context).colorScheme.error,
          ),
          _moneyRow(
            'ليك',
            item.receivableMinor,
            item.currencyCode,
            Colors.green,
          ),
        ],
      ),
    ),
  );
}

Widget _moneyRow(String label, int amount, String currency, Color? color) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '${MinorUnits.format(amount, decimalDigits: 2)} $currency',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );

Map<String, List<BalanceReportItem>> _groupBalances(
  List<BalanceReportItem> items,
) {
  final map = <String, List<BalanceReportItem>>{};
  for (final e in items) {
    map.putIfAbsent(e.currencyCode, () => []).add(e);
  }
  return map;
}

Map<String, List<CategoryReportItem>> _groupCategories(
  List<CategoryReportItem> items,
) {
  final map = <String, List<CategoryReportItem>>{};
  for (final e in items) {
    map.putIfAbsent(e.currencyCode, () => []).add(e);
  }
  return map;
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
