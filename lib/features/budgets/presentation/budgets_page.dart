import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/money/minor_units.dart';
import '../../setup/data/finance_setup_repository.dart';
import '../data/budget_repository.dart';

class BudgetsPage extends StatefulWidget {
  const BudgetsPage({
    super.key,
    required this.repository,
    required this.setup,
    required this.workspaceId,
  });
  final BudgetRepository repository;
  final FinanceSetupRepository setup;
  final int workspaceId;
  @override
  State<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends State<BudgetsPage> {
  late String month;
  List<BudgetItem>? items;
  @override
  void initState() {
    super.initState();
    month = _month(DateTime.now());
    load();
  }

  @override
  void didUpdateWidget(covariant BudgetsPage old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId) load();
  }

  Future<void> load() async {
    final value = await widget.repository.list(widget.workspaceId, month);
    if (mounted) setState(() => items = value);
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
                    'الميزانيات',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'تابع حدود الصرف لكل عملة وفئة',
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
            FilledButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('ميزانية'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items!.isEmpty
              ? const Center(child: Text('لا توجد ميزانيات لهذا الشهر'))
              : ListView(children: items!.map(card).toList()),
        ),
      ],
    ),
  );

  Widget card(BudgetItem item) {
    final percent = (item.progress * 100).round();
    final color = percent >= 100
        ? Theme.of(context).colorScheme.error
        : percent >= item.thresholdPercent
        ? Colors.orange
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  item.categoryId == null
                      ? Icons.account_balance_wallet_outlined
                      : Icons.label_outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.categoryName ?? 'الميزانية الإجمالية',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(item.currencyCode, textDirection: TextDirection.ltr),
                PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? edit(item) : remove(item),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('تعديل الحد')),
                    PopupMenuItem(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ],
            ),
            Text(
              '${MinorUnits.format(item.spentMinor, decimalDigits: 2)} من ${MinorUnits.format(item.limitMinor, decimalDigits: 2)} ${item.currencyCode}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: item.progress.clamp(0, 1),
              color: color,
              minHeight: 9,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('$percent%'),
                const Spacer(),
                if (percent >= 100)
                  Text('تم تجاوز الميزانية', style: TextStyle(color: color))
                else if (percent >= item.thresholdPercent)
                  Text('وصلت لحد التنبيه', style: TextStyle(color: color)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void changeMonth(int delta) {
    final parts = month.split('-');
    final date = DateTime(int.parse(parts[0]), int.parse(parts[1]) + delta);
    setState(() {
      month = _month(date);
      items = null;
    });
    load();
  }

  Future<void> add() async {
    final currencies = (await widget.setup.listCurrencies())
        .where((e) => e.isActive)
        .toList();
    final categories = (await widget.setup.listCategories(
      widget.workspaceId,
    )).where((e) => e.type == 'expense').toList();
    if (!mounted || currencies.isEmpty) return;
    final result = await showDialog<_BudgetInput>(
      context: context,
      builder: (_) =>
          _BudgetDialog(currencies: currencies, categories: categories),
    );
    if (result == null) return;
    try {
      await widget.repository.create(
        workspaceId: widget.workspaceId,
        currencyCode: result.currency,
        limitMinor: MinorUnits.parse(result.limit, decimalDigits: 2),
        month: month,
        categoryId: result.categoryId,
      );
      await load();
    } on DatabaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('توجد ميزانية مماثلة لنفس الشهر والعملة'),
          ),
        );
      }
    }
  }

  Future<void> edit(BudgetItem item) async {
    final controller = TextEditingController(
      text: MinorUnits.format(item.limitMinor, decimalDigits: 2),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل حد الميزانية'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الحد الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repository.updateLimit(
        item.id,
        MinorUnits.parse(controller.text, decimalDigits: 2),
      );
      await load();
    }
  }

  Future<void> remove(BudgetItem item) async {
    await widget.repository.delete(item.id);
    await load();
  }

  static String _month(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.currencies, required this.categories});
  final List<CurrencyItem> currencies;
  final List<NamedSetupItem> categories;
  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late String currency;
  int? category;
  final limit = TextEditingController();
  @override
  void initState() {
    super.initState();
    currency = widget.currencies.first.code;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('ميزانية جديدة'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          initialValue: currency,
          decoration: const InputDecoration(labelText: 'العملة'),
          items: widget.currencies
              .map((e) => DropdownMenuItem(value: e.code, child: Text(e.code)))
              .toList(),
          onChanged: (v) => currency = v!,
        ),
        DropdownButtonFormField<int?>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'النطاق'),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('إجمالي المصروفات'),
            ),
            ...widget.categories.map(
              (e) => DropdownMenuItem<int?>(value: e.id, child: Text(e.name)),
            ),
          ],
          onChanged: (v) => category = v,
        ),
        TextField(
          controller: limit,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'الحد الشهري'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () {
          if (limit.text.trim().isNotEmpty) {
            Navigator.pop(
              context,
              _BudgetInput(currency, category, limit.text),
            );
          }
        },
        child: const Text('حفظ'),
      ),
    ],
  );
}

class _BudgetInput {
  const _BudgetInput(this.currency, this.categoryId, this.limit);
  final String currency, limit;
  final int? categoryId;
}
