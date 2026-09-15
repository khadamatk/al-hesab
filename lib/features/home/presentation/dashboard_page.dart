import 'package:flutter/material.dart';

import '../../../core/money/minor_units.dart';
import '../../../core/theme/app_theme.dart';
import '../../budgets/data/budget_repository.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../reports/data/reports_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.workspaceId,
    required this.reports,
    required this.budgets,
    required this.ledger,
    required this.balancesHidden,
    required this.onToggleBalances,
    required this.onOpenMovements,
    required this.onOpenBudgets,
    required this.onOpenReports,
    required this.onOpenObligations,
  });

  final int workspaceId;
  final ReportsRepository reports;
  final BudgetRepository budgets;
  final LedgerRepository ledger;
  final bool balancesHidden;
  final VoidCallback onToggleBalances;
  final VoidCallback onOpenMovements;
  final VoidCallback onOpenBudgets;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenObligations;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  _DashboardData? data;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) load();
  }

  Future<void> load() async {
    final now = DateTime.now();
    final month =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final values = await Future.wait([
      widget.reports.load(widget.workspaceId, month),
      widget.budgets.list(widget.workspaceId, month),
      widget.ledger.listTransactions(widget.workspaceId),
    ]);
    if (!mounted) return;
    setState(
      () => data = _DashboardData(
        values[0] as ReportsSnapshot,
        values[1] as List<BudgetItem>,
        values[2] as List<TransactionItem>,
      ),
    );
  }

  String money(int value, String currency) => widget.balancesHidden
      ? '••••••'
      : '${MinorUnits.format(value, decimalDigits: 2)} $currency';

  @override
  Widget build(BuildContext context) {
    final value = data;
    if (value == null) return const Center(child: CircularProgressIndicator());
    final totals = <String, int>{};
    for (final item in value.reports.balances) {
      totals.update(
        item.currencyCode,
        (v) => v + item.balanceMinor,
        ifAbsent: () => item.balanceMinor,
      );
    }
    final today = _date(DateTime.now());
    final todayTotals = <String, ({int income, int expense})>{};
    for (final item in value.transactions.where((e) => e.occurredOn == today)) {
      final current = todayTotals[item.currencyCode] ?? (income: 0, expense: 0);
      todayTotals[item.currencyCode] = (
        income: current.income + (item.type == 'income' ? item.amountMinor : 0),
        expense:
            current.expense + (item.type == 'expense' ? item.amountMinor : 0),
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أهلاً بيك 👋',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      'ملخصك المالي',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: widget.onToggleBalances,
                tooltip: widget.balancesHidden
                    ? 'إظهار الأرصدة'
                    : 'إخفاء الأرصدة',
                icon: Icon(
                  widget.balancesHidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppTheme.ink,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إجمالي الأرصدة',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (totals.isEmpty)
                  const Text(
                    'أضف حسابًا ورصيدًا للبدء',
                    style: TextStyle(color: Colors.white),
                  )
                else
                  ...totals.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        money(e.value, e.key),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickButton(
                      Icons.north_east_rounded,
                      'مصروف',
                      widget.onOpenMovements,
                    ),
                    _QuickButton(
                      Icons.south_west_rounded,
                      'دخل',
                      widget.onOpenMovements,
                    ),
                    _QuickButton(
                      Icons.swap_horiz_rounded,
                      'تحويل',
                      widget.onOpenMovements,
                    ),
                    _QuickButton(
                      Icons.handshake_outlined,
                      'دين',
                      widget.onOpenObligations,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'نظرة سريعة',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text('اليوم', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          if (todayTotals.isEmpty)
            _InfoCard(
              title: 'لسه مفيش حركة مسجلة النهاردة',
              icon: Icons.today_outlined,
              onTap: widget.onOpenMovements,
            )
          else
            ...todayTotals.entries.map(
              (entry) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.goldSoft,
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: AppTheme.ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Metric(
                          'دخل اليوم',
                          money(entry.value.income, entry.key),
                          AppTheme.green,
                        ),
                      ),
                      Expanded(
                        child: _Metric(
                          'مصروف اليوم',
                          money(entry.value.expense, entry.key),
                          AppTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (value.reports.obligations.any(
            (e) => e.payableMinor > 0 || e.receivableMinor > 0,
          )) ...[
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                onTap: widget.onOpenObligations,
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.ink,
                  child: Icon(Icons.handshake_outlined, color: AppTheme.gold),
                ),
                title: const Text(
                  'التزامات مفتوحة',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  value.reports.obligations
                      .where((e) => e.payableMinor > 0 || e.receivableMinor > 0)
                      .map(
                        (e) =>
                            '${e.currencyCode}: عليك ${money(e.payableMinor, e.currencyCode)} · ليك ${money(e.receivableMinor, e.currencyCode)}',
                      )
                      .join('\n'),
                ),
                trailing: const Icon(Icons.arrow_back_rounded),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'الشهر الحالي',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: widget.onOpenReports,
                child: const Text('كل التقارير'),
              ),
            ],
          ),
          if (value.reports.cashFlow.isEmpty)
            const _InfoCard(
              title: 'لا توجد حركة هذا الشهر',
              icon: Icons.insights_outlined,
            )
          else
            ...value.reports.cashFlow.map(
              (e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          e.currencyCode,
                          style: Theme.of(
                            context,
                          ).textTheme.titleLarge?.copyWith(color: AppTheme.ink),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.auto_graph_rounded,
                          color: AppTheme.ink,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _Metric(
                            'الدخل',
                            money(e.incomeMinor, e.currencyCode),
                            AppTheme.green,
                          ),
                        ),
                        Expanded(
                          child: _Metric(
                            'المصروف',
                            money(e.expenseMinor, e.currencyCode),
                            AppTheme.ink,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'الميزانيات',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: widget.onOpenBudgets,
                child: const Text('عرض الكل'),
              ),
            ],
          ),
          if (value.budgets.isEmpty)
            _InfoCard(
              title: 'حدد ميزانية شهرية وتحكم في صرفك',
              icon: Icons.donut_large_rounded,
              onTap: widget.onOpenBudgets,
            )
          else
            ...value.budgets
                .take(2)
                .map(
                  (e) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.categoryName ?? 'الميزانية العامة',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              Text(e.currencyCode),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: e.progress.clamp(0, 1),
                              minHeight: 9,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('${(e.progress * 100).round()}% مستخدم'),
                              const Spacer(),
                              Text(money(e.spentMinor, e.currencyCode)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'آخر الحركات',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: widget.onOpenMovements,
                child: const Text('عرض الكل'),
              ),
            ],
          ),
          if (value.transactions.isEmpty)
            const _InfoCard(
              title: 'لا توجد حركات بعد',
              icon: Icons.receipt_long_outlined,
            )
          else
            ...value.transactions
                .take(4)
                .map(
                  (e) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.goldSoft,
                        child: Icon(
                          _transactionIcon(e.type),
                          color: AppTheme.ink,
                        ),
                      ),
                      title: Text(
                        _transactionLabel(e.type),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        e.note?.isNotEmpty == true ? e.note! : e.occurredOn,
                      ),
                      trailing: Text(
                        money(e.amountMinor, e.currencyCode),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _QuickButton extends StatelessWidget {
  const _QuickButton(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.gold,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.ink),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.color);
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.inkSoft)),
      const SizedBox(height: 3),
      Text(
        value,
        textDirection: TextDirection.ltr,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.icon, this.onTap});
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppTheme.goldSoft,
        child: Icon(icon, color: AppTheme.ink),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: onTap == null ? null : const Icon(Icons.arrow_back_rounded),
    ),
  );
}

class _DashboardData {
  const _DashboardData(this.reports, this.budgets, this.transactions);
  final ReportsSnapshot reports;
  final List<BudgetItem> budgets;
  final List<TransactionItem> transactions;
}

IconData _transactionIcon(String type) => switch (type) {
  'income' => Icons.south_west_rounded,
  'expense' => Icons.north_east_rounded,
  'transfer' => Icons.swap_horiz_rounded,
  _ => Icons.receipt_long_outlined,
};

String _transactionLabel(String type) =>
    const {
      'income': 'دخل',
      'expense': 'مصروف',
      'transfer': 'تحويل',
      'opening_balance': 'رصيد افتتاحي',
      'obligation_funding': 'تمويل دين',
      'obligation_settlement': 'دفعة دين',
    }[type] ??
    'حركة مالية';
