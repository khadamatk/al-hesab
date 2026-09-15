import 'package:flutter/material.dart';

import '../../../core/money/minor_units.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../obligations/data/obligation_repository.dart';
import '../../setup/data/finance_setup_repository.dart';
import '../data/ledger_repository.dart';

class MoneyMovementPage extends StatefulWidget {
  const MoneyMovementPage({
    super.key,
    required this.setup,
    required this.ledger,
    required this.workspaceId,
  });
  final FinanceSetupRepository setup;
  final LedgerRepository ledger;
  final int workspaceId;
  @override
  State<MoneyMovementPage> createState() => MoneyMovementPageState();
}

class MoneyMovementPageState extends State<MoneyMovementPage> {
  List<TransactionItem>? items;
  List<AccountItem> accounts = const [];
  List<NamedSetupItem> filterCategories = const [];
  List<NamedSetupItem> filterParties = const [];
  String query = '';
  String typeFilter = 'all';
  int? accountFilter;
  int? categoryFilter, partyFilter;
  String? currencyFilter, fromFilter, toFilter;
  int? minAmountFilter, maxAmountFilter;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant MoneyMovementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId) load();
  }

  Future<void> load() async {
    final values = await Future.wait([
      widget.ledger.listTransactions(widget.workspaceId),
      widget.setup.listAccounts(widget.workspaceId),
      widget.setup.listCategories(widget.workspaceId),
      widget.setup.listCounterparties(widget.workspaceId),
    ]);
    if (mounted) {
      setState(() {
        items = values[0] as List<TransactionItem>;
        accounts = values[1] as List<AccountItem>;
        filterCategories = values[2] as List<NamedSetupItem>;
        filterParties = values[3] as List<NamedSetupItem>;
      });
    }
  }

  List<TransactionItem> get filteredItems {
    final normalized = query.trim().toLowerCase();
    final pocketIds = accountFilter == null
        ? const <int>{}
        : accounts
              .firstWhere((account) => account.id == accountFilter)
              .pockets
              .map((pocket) => pocket.id)
              .toSet();
    return (items ?? const <TransactionItem>[]).where((item) {
      final matchesType = typeFilter == 'all' || item.type == typeFilter;
      final matchesAccount =
          accountFilter == null ||
          pocketIds.contains(item.sourcePocketId) ||
          pocketIds.contains(item.destinationPocketId);
      final matchesAdvanced =
          (categoryFilter == null ||
              item.categoryId == categoryFilter ||
              item.splitCategoryIds.contains(categoryFilter)) &&
          (partyFilter == null || item.counterpartyId == partyFilter) &&
          (currencyFilter == null ||
              item.currencyCode.split(',').contains(currencyFilter)) &&
          (fromFilter == null || item.occurredOn.compareTo(fromFilter!) >= 0) &&
          (toFilter == null || item.occurredOn.compareTo(toFilter!) <= 0) &&
          (minAmountFilter == null || item.amountMinor >= minAmountFilter!) &&
          (maxAmountFilter == null || item.amountMinor <= maxAmountFilter!);
      final searchable = [
        transactionLabel(item.type),
        item.note ?? '',
        item.currencyCode,
        item.occurredOn,
      ].join(' ').toLowerCase();
      return matchesType &&
          matchesAccount &&
          matchesAdvanced &&
          (normalized.isEmpty || searchable.contains(normalized));
    }).toList();
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
                    'الحركة المالية',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'دخل، مصروف، تحويل، أو رصيد افتتاحي',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('عملية'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (items != null && items!.isNotEmpty) ...[
          TextField(
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              hintText: 'ابحث في الوصف أو العملة أو التاريخ',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final filter in const {
                  'all': 'الكل',
                  'expense': 'مصروف',
                  'income': 'دخل',
                  'transfer': 'تحويل',
                }.entries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(filter.value),
                      selected: typeFilter == filter.key,
                      onSelected: (_) =>
                          setState(() => typeFilter = filter.key),
                    ),
                  ),
                PopupMenuButton<int?>(
                  tooltip: 'فلترة بالحساب',
                  initialValue: accountFilter,
                  onSelected: (value) => setState(() => accountFilter = value),
                  itemBuilder: (context) => [
                    const PopupMenuItem<int?>(
                      value: null,
                      child: Text('كل الحسابات'),
                    ),
                    ...accounts.map(
                      (account) => PopupMenuItem<int?>(
                        value: account.id,
                        child: Text(account.name),
                      ),
                    ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(
                      accountFilter == null
                          ? 'كل الحسابات'
                          : accounts
                                .firstWhere((a) => a.id == accountFilter)
                                .name,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.tune_rounded),
                    label: Text(
                      _advancedFilterCount == 0
                          ? 'فلترة متقدمة'
                          : 'فلاتر: $_advancedFilterCount',
                    ),
                    onPressed: showAdvancedFilters,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (items != null && items!.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.gold,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: AppTheme.ink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_graph_rounded,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'آخر نشاط',
                        style: TextStyle(
                          color: AppTheme.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${items!.length} عملية مسجلة',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: AppTheme.ink),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_back_rounded, color: AppTheme.ink),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('أحدث العمليات', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
        ],
        Expanded(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items!.isEmpty
              ? AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'لسه مفيش حركة مالية',
                  message: 'ابدأ برصيد افتتاحي، أو سجّل أول دخل أو مصروف.',
                  actionLabel: 'إضافة أول عملية',
                  onAction: add,
                )
              : filteredItems.isEmpty
              ? const AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'مفيش عمليات مطابقة',
                  message: 'غيّر كلمات البحث أو الفلاتر وحاول تاني.',
                )
              : ListView(
                  children: filteredItems
                      .map(
                        (e) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              radius: 23,
                              backgroundColor: _transactionColor(
                                context,
                                e.type,
                              ).withValues(alpha: .12),
                              child: Icon(
                                transactionIcon(e.type),
                                color: _transactionColor(context, e.type),
                              ),
                            ),
                            title: Text(
                              transactionLabel(e.type),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${e.occurredOn}${e.note == null || e.note!.isEmpty ? '' : ' • ${e.note}'}',
                            ),
                            trailing: Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(
                                '${MinorUnits.format(e.amountMinor, decimalDigits: 2)} ${e.currencyCode}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _transactionColor(context, e.type),
                                ),
                              ),
                            ),
                            onTap: () => editItem(e),
                            onLongPress: () => showTransactionActions(e),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    ),
  );

  int get _advancedFilterCount => [
    categoryFilter,
    partyFilter,
    currencyFilter,
    fromFilter,
    toFilter,
    minAmountFilter,
    maxAmountFilter,
  ].where((value) => value != null).length;

  Future<void> showAdvancedFilters() async {
    var selectedCategory = categoryFilter;
    var selectedParty = partyFilter;
    var selectedCurrency = currencyFilter;
    var selectedFrom = fromFilter;
    var selectedTo = toFilter;
    final minController = TextEditingController(
      text: minAmountFilter == null
          ? ''
          : MinorUnits.format(minAmountFilter!, decimalDigits: 2),
    );
    final maxController = TextEditingController(
      text: maxAmountFilter == null
          ? ''
          : MinorUnits.format(maxAmountFilter!, decimalDigits: 2),
    );
    final currencies =
        accounts
            .expand((account) => account.pockets)
            .map((pocket) => pocket.currencyCode)
            .toSet()
            .toList()
          ..sort();
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<String?> pickDate(String? current) async {
            final picked = await showDatePicker(
              context: context,
              initialDate: current == null
                  ? DateTime.now()
                  : DateTime.parse(current),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            return picked?.toIso8601String().substring(0, 10);
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                MediaQuery.viewInsetsOf(context).bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'فلترة متقدمة',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedCategory,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'الفئة'),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('كل الفئات'),
                        ),
                        ...filterCategories.map(
                          (item) => DropdownMenuItem<int?>(
                            value: item.id,
                            child: Text(item.displayName),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setSheetState(() => selectedCategory = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedParty,
                      decoration: const InputDecoration(labelText: 'الطرف'),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('كل الأطراف'),
                        ),
                        ...filterParties.map(
                          (item) => DropdownMenuItem<int?>(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setSheetState(() => selectedParty = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedCurrency,
                      decoration: const InputDecoration(labelText: 'العملة'),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('كل العملات'),
                        ),
                        ...currencies.map(
                          (code) => DropdownMenuItem<String?>(
                            value: code,
                            child: Text(code),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setSheetState(() => selectedCurrency = value),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'أقل مبلغ',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: maxController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'أكبر مبلغ',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final date = await pickDate(selectedFrom);
                              if (date != null) {
                                setSheetState(() => selectedFrom = date);
                              }
                            },
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text(selectedFrom ?? 'من تاريخ'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final date = await pickDate(selectedTo);
                              if (date != null) {
                                setSheetState(() => selectedTo = date);
                              }
                            },
                            icon: const Icon(Icons.event_outlined),
                            label: Text(selectedTo ?? 'إلى تاريخ'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            selectedCategory = null;
                            selectedParty = null;
                            selectedCurrency = null;
                            selectedFrom = null;
                            selectedTo = null;
                            minController.clear();
                            maxController.clear();
                            setSheetState(() {});
                          },
                          child: const Text('مسح الكل'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('تطبيق'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (apply != true || !mounted) return;
    int? parsedMin;
    int? parsedMax;
    try {
      parsedMin = minController.text.trim().isEmpty
          ? null
          : MinorUnits.parse(minController.text, decimalDigits: 2);
      parsedMax = maxController.text.trim().isEmpty
          ? null
          : MinorUnits.parse(maxController.text, decimalDigits: 2);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('راجع قيم الحد الأدنى والأقصى')),
        );
      }
      return;
    }
    if (parsedMin != null && parsedMax != null && parsedMin > parsedMax) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الحد الأدنى أكبر من الحد الأقصى')),
      );
      return;
    }
    setState(() {
      categoryFilter = selectedCategory;
      partyFilter = selectedParty;
      currencyFilter = selectedCurrency;
      fromFilter = selectedFrom;
      toFilter = selectedTo;
      minAmountFilter = parsedMin;
      maxAmountFilter = parsedMax;
    });
  }

  Future<void> add({String? initialType}) async {
    final accounts = await widget.setup.listAccounts(widget.workspaceId);
    final pockets = [
      for (final a in accounts)
        for (final p in a.pockets)
          _PocketChoice(
            p.id,
            '${a.isFavorite ? '★ ' : ''}${a.name} — ${p.currencyCode} · ${MinorUnits.format(p.balanceMinor, decimalDigits: 2)}',
            p.currencyCode,
          ),
    ];
    final categories = await widget.setup.listCategories(widget.workspaceId);
    final parties = await widget.setup.listCounterparties(widget.workspaceId);
    final channels = await widget.setup.listChannels(widget.workspaceId);
    if (!mounted) return;
    if (pockets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف حسابًا وجيب عملة أولًا')),
      );
      return;
    }
    final input = await showDialog<_MovementInput>(
      context: context,
      builder: (context) => _MovementDialog(
        pockets: pockets,
        categories: categories,
        parties: parties,
        channels: channels,
        initialType: initialType,
      ),
    );
    if (input == null) return;
    if (!await _confirmMovement(input, pockets)) return;
    try {
      await _postInput(input, pockets);
      await widget.setup.markAccountUsedByPocket(input.sourcePocketId);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorText(e))));
      }
    }
  }

  Future<void> _postInput(
    _MovementInput input,
    List<_PocketChoice> pockets,
  ) async {
    final amount = MinorUnits.parse(input.amount, decimalDigits: 2);
    final date = input.occurredOn;
    switch (input.type) {
      case 'opening_balance':
        await widget.ledger.postOpeningBalance(
          workspaceId: widget.workspaceId,
          pocketId: input.sourcePocketId,
          amountMinor: amount,
          occurredOn: date,
          note: input.note ?? 'الرصيد الافتتاحي',
        );
      case 'income':
        await widget.ledger.postIncome(
          workspaceId: widget.workspaceId,
          pocketId: input.sourcePocketId,
          amountMinor: amount,
          categoryId: input.categoryId!,
          occurredOn: date,
          counterpartyId: input.partyId,
          channelId: input.channelId,
          note: input.note,
        );
      case 'expense':
        if (input.splits.isEmpty) {
          await widget.ledger.postExpense(
            workspaceId: widget.workspaceId,
            pocketId: input.sourcePocketId,
            amountMinor: amount,
            categoryId: input.categoryId!,
            occurredOn: date,
            counterpartyId: input.partyId,
            channelId: input.channelId,
            note: input.note,
          );
        } else {
          await widget.ledger.postSplitExpense(
            workspaceId: widget.workspaceId,
            pocketId: input.sourcePocketId,
            amountMinor: amount,
            splits: input.splits
                .map(
                  (split) => SplitAllocation(
                    categoryId: split.categoryId,
                    amountMinor: MinorUnits.parse(
                      split.amount,
                      decimalDigits: 2,
                    ),
                  ),
                )
                .toList(),
            occurredOn: date,
            counterpartyId: input.partyId,
            channelId: input.channelId,
            note: input.note,
          );
        }
      case 'transfer':
        final destination = pockets.firstWhere(
          (e) => e.id == input.destinationPocketId,
        );
        final source = pockets.firstWhere((e) => e.id == input.sourcePocketId);
        await widget.ledger.postTransfer(
          workspaceId: widget.workspaceId,
          sourcePocketId: input.sourcePocketId,
          destinationPocketId: input.destinationPocketId!,
          sourceAmountMinor: amount,
          destinationAmountMinor: source.currency == destination.currency
              ? null
              : MinorUnits.parse(input.receivedAmount!, decimalDigits: 2),
          occurredOn: date,
          channelId: input.channelId,
          note: input.note,
        );
    }
  }

  Future<void> editItem(TransactionItem item) async {
    if (item.splitCategoryIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعديل العملية المقسمة نفسها غير متاح بعد؛ ألغِها وأنشئ تقسيمًا جديدًا للحفاظ على دقة المراجعة',
          ),
        ),
      );
      return;
    }
    if (!const {
      'income',
      'expense',
      'transfer',
      'opening_balance',
    }.contains(item.type)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يمكن تعديل حركات الدخل والمصروف والتحويل والرصيد الافتتاحي فقط',
          ),
        ),
      );
      return;
    }
    final accounts = await widget.setup.listAccounts(widget.workspaceId);
    final pockets = [
      for (final a in accounts)
        for (final p in a.pockets)
          _PocketChoice(
            p.id,
            '${a.isFavorite ? '★ ' : ''}${a.name} — ${p.currencyCode} · ${MinorUnits.format(p.balanceMinor, decimalDigits: 2)}',
            p.currencyCode,
          ),
    ];
    final categories = await widget.setup.listCategories(widget.workspaceId);
    final parties = await widget.setup.listCounterparties(widget.workspaceId);
    final channels = await widget.setup.listChannels(widget.workspaceId);
    if (!mounted) return;
    final input = await showDialog<_MovementInput>(
      context: context,
      builder: (context) => _MovementDialog(
        pockets: pockets,
        categories: categories,
        parties: parties,
        channels: channels,
        initial: item,
      ),
    );
    if (input == null) return;
    if (!await _confirmMovement(input, pockets, correction: true)) return;
    try {
      final amount = MinorUnits.parse(input.amount, decimalDigits: 2);
      final source = pockets.firstWhere((e) => e.id == input.sourcePocketId);
      final destination = pockets
          .where((e) => e.id == input.destinationPocketId)
          .firstOrNull;
      await widget.ledger.correctTransaction(
        transactionId: item.id,
        workspaceId: widget.workspaceId,
        sourcePocketId: input.sourcePocketId,
        amountMinor: amount,
        occurredOn: input.occurredOn,
        destinationPocketId: input.destinationPocketId,
        destinationAmountMinor:
            destination != null && destination.currency != source.currency
            ? MinorUnits.parse(input.receivedAmount!, decimalDigits: 2)
            : null,
        categoryId: input.categoryId,
        counterpartyId: input.partyId,
        channelId: input.channelId,
        note: input.note,
      );
      await widget.setup.markAccountUsedByPocket(input.sourcePocketId);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorText(e))));
      }
    }
  }

  Future<void> repeatItem(TransactionItem item) async {
    if (item.splitCategoryIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('كرر العملية المقسمة بإنشاء مصروف جديد وتفعيل التقسيم'),
        ),
      );
      return;
    }
    final supported = const {
      'income',
      'expense',
      'transfer',
      'opening_balance',
    }.contains(item.type);
    if (!supported) return;
    final loadedAccounts = await widget.setup.listAccounts(widget.workspaceId);
    final pockets = [
      for (final account in loadedAccounts)
        for (final pocket in account.pockets)
          _PocketChoice(
            pocket.id,
            '${account.isFavorite ? '★ ' : ''}${account.name} — ${pocket.currencyCode} · ${MinorUnits.format(pocket.balanceMinor, decimalDigits: 2)}',
            pocket.currencyCode,
          ),
    ];
    final categories = await widget.setup.listCategories(widget.workspaceId);
    final parties = await widget.setup.listCounterparties(widget.workspaceId);
    final channels = await widget.setup.listChannels(widget.workspaceId);
    if (!mounted) return;
    final input = await showDialog<_MovementInput>(
      context: context,
      builder: (context) => _MovementDialog(
        pockets: pockets,
        categories: categories,
        parties: parties,
        channels: channels,
        initial: item,
        repeat: true,
      ),
    );
    if (input == null || !await _confirmMovement(input, pockets)) return;
    try {
      await _postInput(input, pockets);
      await widget.setup.markAccountUsedByPocket(input.sourcePocketId);
      await load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorText(error))));
      }
    }
  }

  Future<bool> _confirmMovement(
    _MovementInput input,
    List<_PocketChoice> pockets, {
    bool correction = false,
  }) async {
    final source = pockets.firstWhere(
      (pocket) => pocket.id == input.sourcePocketId,
    );
    final destination = pockets
        .where((pocket) => pocket.id == input.destinationPocketId)
        .firstOrNull;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          correction ? 'تأكيد تصحيح العملية' : 'راجع العملية قبل الحفظ',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConfirmationRow('النوع', transactionLabel(input.type)),
            _ConfirmationRow('المبلغ', '${input.amount} ${source.currency}'),
            _ConfirmationRow('الحساب', source.label),
            if (destination != null) _ConfirmationRow('إلى', destination.label),
            _ConfirmationRow('التاريخ', input.occurredOn),
            if (input.note != null) _ConfirmationRow('الوصف', input.note!),
            if (input.splits.isNotEmpty)
              _ConfirmationRow('التقسيم', '${input.splits.length} فئات'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تعديل'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_rounded),
            label: Text(correction ? 'تأكيد التصحيح' : 'حفظ العملية'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> showTransactionActions(TransactionItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل العملية'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.repeat_rounded),
              title: const Text('تكرار كعملية جديدة'),
              subtitle: const Text('بنفس التفاصيل وتاريخ اليوم'),
              onTap: () => Navigator.pop(context, 'repeat'),
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('إلغاء العملية'),
              onTap: () => Navigator.pop(context, 'void'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await editItem(item);
      case 'repeat':
        await repeatItem(item);
      case 'void':
        await voidItem(item);
    }
  }

  Future<void> voidItem(TransactionItem item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء العملية؟'),
        content: const Text(
          'لن تُحذف؛ ستظل محفوظة للمراجعة ولن تؤثر على الرصيد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إلغاء العملية'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.ledger.voidTransaction(item.id, 'ألغيت من المستخدم');
      await load();
    }
  }
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.pockets,
    required this.categories,
    required this.parties,
    required this.channels,
    this.initial,
    this.initialType,
    this.repeat = false,
  });
  final List<_PocketChoice> pockets;
  final List<NamedSetupItem> categories, parties, channels;
  final TransactionItem? initial;
  final String? initialType;
  final bool repeat;
  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  late String type;
  late int source;
  int? destination, category, party, channel;
  late final TextEditingController amount, received, note;
  late String occurredOn;
  bool splitMode = false;
  String? splitError;
  final List<_SplitDraft> splitDrafts = [];
  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    type =
        initial?.type ??
        (widget.initialType == 'atm' ? 'transfer' : widget.initialType) ??
        'expense';
    source = initial?.sourcePocketId ?? widget.pockets.first.id;
    destination = initial?.destinationPocketId;
    category = initial?.categoryId;
    party = initial?.counterpartyId;
    channel =
        initial?.channelId ??
        (widget.initialType == 'atm'
            ? widget.channels.where((e) => e.type == 'atm').firstOrNull?.id
            : null);
    amount = TextEditingController(
      text: initial == null
          ? ''
          : MinorUnits.format(initial.amountMinor, decimalDigits: 2),
    );
    received = TextEditingController(
      text: initial?.destinationAmountMinor == null
          ? ''
          : MinorUnits.format(
              initial!.destinationAmountMinor!,
              decimalDigits: 2,
            ),
    );
    note = TextEditingController(text: initial?.note ?? '');
    occurredOn = widget.repeat
        ? DateTime.now().toIso8601String().substring(0, 10)
        : initial?.occurredOn ??
              DateTime.now().toIso8601String().substring(0, 10);
    final expenseCategories = widget.categories
        .where((item) => item.type == 'expense')
        .toList();
    if (expenseCategories.isNotEmpty) {
      splitDrafts.addAll([
        _SplitDraft(expenseCategories.first.id),
        _SplitDraft(
          expenseCategories.length > 1
              ? expenseCategories[1].id
              : expenseCategories.first.id,
        ),
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = type == 'income' ? 'income' : 'expense';
    final cats = widget.categories.where((e) => e.type == kind).toList();
    if (type == 'income' || type == 'expense') {
      if (!cats.any((e) => e.id == category)) category = cats.firstOrNull?.id;
    }
    final sourcePocket = widget.pockets.firstWhere((e) => e.id == source);
    final destinationPocket = widget.pockets
        .where((e) => e.id == destination)
        .firstOrNull;
    final crossCurrency =
        type == 'transfer' &&
        destinationPocket != null &&
        sourcePocket.currency != destinationPocket.currency;
    return AlertDialog(
      title: Text(
        widget.repeat
            ? 'تكرار العملية'
            : widget.initial == null
            ? 'عملية مالية جديدة'
            : 'تعديل العملية',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Padding(
            // The first floating label extends above its field. Keep it inside
            // the scroll viewport so it is not clipped on real devices.
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'نوع العملية'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('مصروف')),
                    DropdownMenuItem(value: 'income', child: Text('دخل')),
                    DropdownMenuItem(
                      value: 'transfer',
                      child: Text('تحويل / سحب ATM'),
                    ),
                    DropdownMenuItem(
                      value: 'opening_balance',
                      child: Text('رصيد افتتاحي'),
                    ),
                  ],
                  onChanged: widget.initial == null
                      ? (v) => setState(() {
                          type = v!;
                          destination = null;
                          category = null;
                        })
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: source,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: type == 'transfer' ? 'من حساب' : 'الحساب',
                  ),
                  items: widget.pockets
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.id,
                          child: Text(
                            e.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => source = v!),
                ),
                if (type == 'transfer') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: destination,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'إلى حساب'),
                    items: widget.pockets
                        .where((e) => e.id != source)
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              e.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => destination = v),
                  ),
                ],
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('التاريخ'),
                  subtitle: Text(occurredOn, textDirection: TextDirection.ltr),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final current = DateTime.parse(occurredOn);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: current,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(
                        () => occurredOn = picked.toIso8601String().substring(
                          0,
                          10,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: type == 'transfer' ? 'المبلغ المرسل' : 'المبلغ',
                  ),
                ),
                if (type == 'expense' && widget.initial == null) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تقسيم العملية'),
                    subtitle: const Text('وزّع المبلغ على أكثر من فئة'),
                    value: splitMode,
                    onChanged: (value) => setState(() {
                      splitMode = value;
                      splitError = null;
                    }),
                  ),
                  if (splitMode) ...[
                    for (var index = 0; index < splitDrafts.length; index++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<int>(
                                initialValue: splitDrafts[index].categoryId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'الفئة ${index + 1}',
                                ),
                                items: cats
                                    .map(
                                      (item) => DropdownMenuItem(
                                        value: item.id,
                                        child: Text(
                                          item.displayName,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) => setState(
                                  () => splitDrafts[index].categoryId = value!,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: splitDrafts[index].amount,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'المبلغ',
                                ),
                              ),
                            ),
                            if (splitDrafts.length > 2)
                              IconButton(
                                onPressed: () =>
                                    setState(() => splitDrafts.removeAt(index)),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: cats.isEmpty
                            ? null
                            : () => setState(
                                () =>
                                    splitDrafts.add(_SplitDraft(cats.first.id)),
                              ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('إضافة فئة'),
                      ),
                    ),
                    if (splitError != null)
                      Text(
                        splitError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ],
                if (crossCurrency) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: received,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'المبلغ المستلم بـ${destinationPocket.currency}',
                    ),
                  ),
                ],
                if (type == 'income' || (type == 'expense' && !splitMode)) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'الفئة'),
                    items: cats
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(e.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => category = v),
                  ),
                ],
                if (widget.parties.isNotEmpty &&
                    (type == 'income' || type == 'expense')) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: party,
                    decoration: const InputDecoration(
                      labelText: 'الطرف (اختياري)',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('بدون'),
                      ),
                      ...widget.parties.map(
                        (e) => DropdownMenuItem<int?>(
                          value: e.id,
                          child: Text(e.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => party = v),
                  ),
                ],
                if (widget.channels.isNotEmpty &&
                    type != 'opening_balance') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: channel,
                    decoration: const InputDecoration(
                      labelText: 'القناة (اختياري)',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('بدون'),
                      ),
                      ...widget.channels.map(
                        (e) => DropdownMenuItem<int?>(
                          value: e.id,
                          child: Text(e.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => channel = v),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            final splitInputs = splitMode
                ? splitDrafts
                      .map(
                        (draft) => _SplitInput(
                          draft.categoryId,
                          draft.amount.text.trim(),
                        ),
                      )
                      .toList()
                : const <_SplitInput>[];
            if (splitMode) {
              try {
                final total = MinorUnits.parse(amount.text, decimalDigits: 2);
                final allocated = splitInputs.fold<int>(
                  0,
                  (sum, split) =>
                      sum + MinorUnits.parse(split.amount, decimalDigits: 2),
                );
                if (splitInputs.length < 2 || allocated != total) {
                  setState(
                    () => splitError = 'مجموع التقسيم لازم يساوي المبلغ',
                  );
                  return;
                }
              } catch (_) {
                setState(() => splitError = 'راجع مبالغ التقسيم');
                return;
              }
            }
            if (amount.text.trim().isEmpty ||
                (type == 'transfer' && destination == null) ||
                (crossCurrency && received.text.trim().isEmpty) ||
                ((type == 'income' || (type == 'expense' && !splitMode)) &&
                    category == null)) {
              return;
            }
            Navigator.pop(
              context,
              _MovementInput(
                type,
                source,
                destination,
                amount.text,
                crossCurrency ? received.text : null,
                category,
                party,
                channel,
                note.text.trim().isEmpty ? null : note.text.trim(),
                occurredOn,
                splitInputs,
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _PocketChoice {
  const _PocketChoice(this.id, this.label, this.currency);
  final int id;
  final String label, currency;
}

class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _MovementInput {
  const _MovementInput(
    this.type,
    this.sourcePocketId,
    this.destinationPocketId,
    this.amount,
    this.receivedAmount,
    this.categoryId,
    this.partyId,
    this.channelId,
    this.note,
    this.occurredOn,
    this.splits,
  );
  final String type, amount;
  final int sourcePocketId;
  final int? destinationPocketId, categoryId, partyId, channelId;
  final String? receivedAmount, note;
  final String occurredOn;
  final List<_SplitInput> splits;
}

class _SplitInput {
  const _SplitInput(this.categoryId, this.amount);
  final int categoryId;
  final String amount;
}

class _SplitDraft {
  _SplitDraft(this.categoryId) : amount = TextEditingController();
  int categoryId;
  final TextEditingController amount;
}

IconData transactionIcon(String type) => switch (type) {
  'income' => Icons.south_west,
  'expense' => Icons.north_east,
  'transfer' => Icons.swap_horiz,
  'opening_balance' => Icons.flag_outlined,
  'obligation_funding' => Icons.handshake_outlined,
  'obligation_settlement' => Icons.payments_outlined,
  _ => Icons.receipt_long,
};
String transactionLabel(String type) =>
    const {
      'income': 'دخل',
      'expense': 'مصروف',
      'transfer': 'تحويل',
      'opening_balance': 'رصيد افتتاحي',
      'obligation_funding': 'تمويل دين',
      'obligation_settlement': 'دفعة دين',
      'adjustment': 'تسوية',
    }[type] ??
    type;
Color _transactionColor(BuildContext context, String type) => switch (type) {
  'income' => const Color(0xFF16865C),
  'expense' => Theme.of(context).colorScheme.error,
  'transfer' => const Color(0xFF3578B8),
  _ => Theme.of(context).colorScheme.primary,
};
String _errorText(Object e) {
  final text = e.toString();
  if (text.contains('Insufficient')) return 'الرصيد غير كافٍ';
  if (text.contains('linked')) {
    return 'قناة InstaPay غير مرتبطة بالحساب المختار';
  }
  if (e is FormatException) return 'اكتب مبلغًا صحيحًا';
  return 'تعذر حفظ العملية';
}

class ObligationsPage extends StatefulWidget {
  const ObligationsPage({
    super.key,
    required this.setup,
    required this.repository,
    required this.workspaceId,
  });
  final FinanceSetupRepository setup;
  final ObligationRepository repository;
  final int workspaceId;
  @override
  State<ObligationsPage> createState() => _ObligationsPageState();
}

class _ObligationsPageState extends State<ObligationsPage> {
  List<ObligationItem>? items;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant ObligationsPage old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId) load();
  }

  Future<void> load() async {
    final v = await widget.repository.list(widget.workspaceId);
    if (mounted) setState(() => items = v);
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
                    'الديون والمستحقات',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'اللي عليك واللي ليك والدفعات الجزئية',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('إضافة'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items!.isEmpty
              ? const Center(child: Text('لا توجد ديون أو مستحقات'))
              : ListView(
                  children: items!
                      .map(
                        (e) => Card(
                          child: ListTile(
                            leading: Icon(
                              e.direction == 'payable'
                                  ? Icons.upload
                                  : Icons.download,
                            ),
                            title: Text(e.counterpartyName),
                            subtitle: Text(
                              '${e.direction == 'payable' ? 'عليك' : 'ليك'} • ${natureLabel(e.nature)} • ${statusLabel(e.status)}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) =>
                                  value == 'fund' ? fund(e) : settle(e),
                              itemBuilder: (context) => [
                                if ((e.nature == 'loan' ||
                                        e.nature == 'money_lent') &&
                                    e.fundedMinor < e.principalMinor)
                                  const PopupMenuItem(
                                    value: 'fund',
                                    child: Text('تحريك أصل المبلغ'),
                                  ),
                                if (e.remainingMinor > 0)
                                  PopupMenuItem(
                                    value: 'settle',
                                    child: Text(
                                      e.direction == 'payable'
                                          ? 'تسجيل دفعة'
                                          : 'تسجيل تحصيل',
                                    ),
                                  ),
                              ],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${MinorUnits.format(e.remainingMinor, decimalDigits: 2)} ${e.currencyCode}',
                                    textDirection: TextDirection.ltr,
                                  ),
                                  const Icon(Icons.more_horiz),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    ),
  );
  Future<void> add() async {
    final parties = await widget.setup.listCounterparties(widget.workspaceId),
        currencies = (await widget.setup.listCurrencies())
            .where((e) => e.isActive)
            .toList(),
        categories = await widget.setup.listCategories(widget.workspaceId);
    if (!mounted) return;
    if (parties.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أضف الطرف أولًا')));
      return;
    }
    final v = await showDialog<_DebtInput>(
      context: context,
      builder: (context) => _DebtDialog(
        parties: parties,
        currencies: currencies,
        categories: categories,
      ),
    );
    if (v == null) return;
    try {
      await widget.repository.create(
        workspaceId: widget.workspaceId,
        counterpartyId: v.partyId,
        direction: v.direction,
        nature: v.nature,
        currencyCode: v.currency,
        principalMinor: MinorUnits.parse(v.amount, decimalDigits: 2),
        openedOn: DateTime.now().toIso8601String().substring(0, 10),
        categoryId: v.categoryId,
        note: v.note,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر إضافة الدين؛ راجع النوع والفئة')),
        );
      }
    }
  }

  Future<void> settle(ObligationItem item) =>
      _moveObligation(item, funding: false);
  Future<void> fund(ObligationItem item) =>
      _moveObligation(item, funding: true);

  Future<void> _moveObligation(
    ObligationItem item, {
    required bool funding,
  }) async {
    final accounts = await widget.setup.listAccounts(widget.workspaceId);
    final pockets = [
      for (final a in accounts)
        for (final p in a.pockets)
          _PocketChoice(p.id, '${a.name} — ${p.currencyCode}', p.currencyCode),
    ];
    if (!mounted || pockets.isEmpty) return;
    int pocket = pockets.first.id;
    final obligationAmount = TextEditingController(
      text: MinorUnits.format(
        funding ? item.principalMinor - item.fundedMinor : item.remainingMinor,
        decimalDigits: 2,
      ),
    );
    final pocketAmount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            funding
                ? 'تحريك أصل المبلغ'
                : item.direction == 'payable'
                ? 'تسجيل دفعة'
                : 'تسجيل تحصيل',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: pocket,
                items: pockets
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.id, child: Text(e.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => pocket = v!),
              ),
              TextField(
                controller: obligationAmount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'المبلغ بـ${item.currencyCode}',
                ),
              ),
              if (pockets.firstWhere((e) => e.id == pocket).currency !=
                  item.currencyCode)
                TextField(
                  controller: pocketAmount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'المبلغ الفعلي بـ${pockets.firstWhere((e) => e.id == pocket).currency}',
                  ),
                ),
            ],
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
      ),
    );
    if (ok == true) {
      try {
        final obligationMinor = MinorUnits.parse(
          obligationAmount.text,
          decimalDigits: 2,
        );
        final selected = pockets.firstWhere((e) => e.id == pocket);
        final crossCurrency = selected.currency != item.currencyCode;
        final pocketMinor = crossCurrency
            ? MinorUnits.parse(pocketAmount.text, decimalDigits: 2)
            : obligationMinor;
        final fx = crossCurrency
            ? (item.direction == 'payable'
                  ? FxSettlement(
                      sourceCurrencyCode: selected.currency,
                      sourceAmountMinor: pocketMinor,
                      destinationCurrencyCode: item.currencyCode,
                      destinationAmountMinor: obligationMinor,
                    )
                  : FxSettlement(
                      sourceCurrencyCode: item.currencyCode,
                      sourceAmountMinor: obligationMinor,
                      destinationCurrencyCode: selected.currency,
                      destinationAmountMinor: pocketMinor,
                    ))
            : null;
        final date = DateTime.now().toIso8601String().substring(0, 10);
        if (funding) {
          await widget.repository.fund(
            obligationId: item.id,
            pocketId: pocket,
            obligationAmountMinor: obligationMinor,
            pocketAmountMinor: pocketMinor,
            occurredOn: date,
            fxSettlement: fx,
          );
        } else {
          await widget.repository.settle(
            obligationId: item.id,
            pocketId: pocket,
            obligationAmountMinor: obligationMinor,
            pocketAmountMinor: pocketMinor,
            occurredOn: date,
            fxSettlement: fx,
          );
        }
        await load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الدفعة غير صالحة أو الرصيد غير كافٍ'),
            ),
          );
        }
      }
    }
  }
}

class _DebtDialog extends StatefulWidget {
  const _DebtDialog({
    required this.parties,
    required this.currencies,
    required this.categories,
  });
  final List<NamedSetupItem> parties, categories;
  final List<CurrencyItem> currencies;
  @override
  State<_DebtDialog> createState() => _DebtDialogState();
}

class _DebtDialogState extends State<_DebtDialog> {
  late int party;
  late String currency;
  String direction = 'payable', nature = 'loan';
  int? category;
  final amount = TextEditingController(), note = TextEditingController();
  @override
  void initState() {
    super.initState();
    party = widget.parties.first.id;
    currency = widget.currencies.first.code;
  }

  @override
  Widget build(BuildContext context) {
    final needsCategory = nature == 'invoice' || nature == 'credit_purchase';
    final kind = nature == 'invoice' ? 'income' : 'expense';
    final cats = widget.categories.where((e) => e.type == kind).toList();
    if (needsCategory && !cats.any((e) => e.id == category)) {
      category = cats.firstOrNull?.id;
    }
    return AlertDialog(
      title: const Text('دين أو مستحق جديد'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: direction,
                decoration: const InputDecoration(labelText: 'الاتجاه'),
                items: const [
                  DropdownMenuItem(value: 'payable', child: Text('عليّ')),
                  DropdownMenuItem(value: 'receivable', child: Text('ليّ')),
                ],
                onChanged: (v) => setState(() {
                  direction = v!;
                  nature = direction == 'payable' ? 'loan' : 'invoice';
                  category = null;
                }),
              ),
              DropdownButtonFormField<String>(
                initialValue: nature,
                decoration: const InputDecoration(labelText: 'النوع'),
                items:
                    (direction == 'payable'
                            ? const {
                                'loan': 'قرض',
                                'credit_purchase': 'شراء آجل',
                                'other': 'آخر',
                              }
                            : const {
                                'invoice': 'فاتورة مستحقة',
                                'money_lent': 'سلفة للغير',
                                'other': 'آخر',
                              })
                        .entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() {
                  nature = v!;
                  category = null;
                }),
              ),
              DropdownButtonFormField<int>(
                initialValue: party,
                decoration: const InputDecoration(labelText: 'الطرف'),
                items: widget.parties
                    .map(
                      (e) => DropdownMenuItem(value: e.id, child: Text(e.name)),
                    )
                    .toList(),
                onChanged: (v) => party = v!,
              ),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'العملة'),
                items: widget.currencies
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.code, child: Text(e.code)),
                    )
                    .toList(),
                onChanged: (v) => currency = v!,
              ),
              if (needsCategory)
                DropdownButtonFormField<int>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'الفئة'),
                  items: cats
                      .map(
                        (e) =>
                            DropdownMenuItem(value: e.id, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => category = v),
                ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'القيمة'),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'ملاحظة'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            if (amount.text.trim().isEmpty ||
                (needsCategory && category == null)) {
              return;
            }
            Navigator.pop(
              context,
              _DebtInput(
                party,
                direction,
                nature,
                currency,
                amount.text,
                category,
                note.text.trim().isEmpty ? null : note.text.trim(),
              ),
            );
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

class _DebtInput {
  const _DebtInput(
    this.partyId,
    this.direction,
    this.nature,
    this.currency,
    this.amount,
    this.categoryId,
    this.note,
  );
  final int partyId;
  final String direction, nature, currency, amount;
  final int? categoryId;
  final String? note;
}

String natureLabel(String v) =>
    const {
      'loan': 'قرض',
      'credit_purchase': 'شراء آجل',
      'invoice': 'فاتورة',
      'money_lent': 'سلفة',
      'other': 'آخر',
    }[v] ??
    v;
String statusLabel(String v) =>
    const {'open': 'مفتوح', 'partial': 'مدفوع جزئيًا', 'settled': 'مغلق'}[v] ??
    v;
