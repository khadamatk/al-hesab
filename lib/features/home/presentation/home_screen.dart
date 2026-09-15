import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../budgets/data/budget_repository.dart';
import '../../budgets/presentation/budgets_page.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../ledger/presentation/money_movement_page.dart';
import '../../obligations/data/obligation_repository.dart';
import '../../reports/data/reports_repository.dart';
import '../../reports/presentation/reports_page.dart';
import '../../security/presentation/data_security_page.dart';
import '../../setup/data/finance_setup_repository.dart';
import 'dashboard_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _movementsKey = GlobalKey<MoneyMovementPageState>();
  FinanceSetupRepository? _repo;
  LedgerRepository? _ledger;
  ObligationRepository? _obligations;
  BudgetRepository? _budgets;
  ReportsRepository? _reports;
  AppDatabase? _database;
  List<WorkspaceItem> _spaces = const [];
  int? _spaceId;
  int _page = 0;
  bool _balancesHidden = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final database = await ref.read(appDatabaseProvider).open();
      final repo = FinanceSetupRepository(database);
      final spaces = await repo.listWorkspaces();
      if (!mounted) return;
      setState(() {
        _repo = repo;
        _ledger = LedgerRepository(database);
        _obligations = ObligationRepository(database);
        _budgets = BudgetRepository(database);
        _reports = ReportsRepository(database);
        _database = ref.read(appDatabaseProvider);
        _spaces = spaces.where((e) => !e.isArchived).toList();
        _spaceId ??= _spaces.firstOrNull?.id;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    appBar: AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.ink,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppTheme.gold,
              size: 25,
              semanticLabel: 'شعار عَ الحساب',
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 400 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.2) ...[
            const SizedBox(width: 10),
            Text('عَ الحساب', style: Theme.of(context).textTheme.titleLarge),
          ],
        ],
      ),
      actions: [
        if (_spaces.isNotEmpty)
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(21),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _spaceId,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                style: Theme.of(context).textTheme.labelLarge,
                items: _spaces
                    .map(
                      (e) => DropdownMenuItem(value: e.id, child: Text(e.name)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _spaceId = v),
              ),
            ),
          ),
        PopupMenuButton<int>(
          tooltip: 'الإعدادات',
          icon: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tune_rounded, size: 20),
          ),
          onSelected: (value) {
            if (value == 99) {
              _addWorkspace();
            } else if (value == 98) {
              _showAbout();
            } else {
              setState(() => _page = value);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 99, child: Text('مساحة عمل جديدة')),
            PopupMenuDivider(),
            PopupMenuItem(value: 2, child: Text('الحسابات والأرصدة')),
            PopupMenuItem(value: 5, child: Text('الديون والمستحقات')),
            PopupMenuItem(value: 6, child: Text('قنوات الدفع')),
            PopupMenuItem(value: 7, child: Text('الفئات')),
            PopupMenuItem(value: 8, child: Text('الأطراف')),
            PopupMenuItem(value: 9, child: Text('العملات')),
            PopupMenuItem(value: 10, child: Text('البيانات والأمان')),
            PopupMenuDivider(),
            PopupMenuItem(value: 98, child: Text('عن التطبيق والحقوق')),
          ],
        ),
      ],
    ),
    body: _error != null
        ? Center(
            child: TextButton(
              onPressed: _load,
              child: const Text('تعذر التحميل — حاول مجددًا'),
            ),
          )
        : _repo == null
        ? const Center(child: CircularProgressIndicator())
        : _spaceId == null
        ? const Center(child: Text('أضف مساحة عمل للبدء'))
        : IndexedStack(
            index: _page,
            children: [
              DashboardPage(
                workspaceId: _spaceId!,
                reports: _reports!,
                budgets: _budgets!,
                ledger: _ledger!,
                balancesHidden: _balancesHidden,
                onToggleBalances: () =>
                    setState(() => _balancesHidden = !_balancesHidden),
                onOpenMovements: () => setState(() => _page = 1),
                onOpenBudgets: () => setState(() => _page = 3),
                onOpenReports: () => setState(() => _page = 4),
                onOpenObligations: () => setState(() => _page = 5),
              ),
              MoneyMovementPage(
                key: _movementsKey,
                setup: _repo!,
                ledger: _ledger!,
                workspaceId: _spaceId!,
              ),
              AccountsPage(repository: _repo!, workspaceId: _spaceId!),
              BudgetsPage(
                repository: _budgets!,
                setup: _repo!,
                workspaceId: _spaceId!,
              ),
              ReportsPage(repository: _reports!, workspaceId: _spaceId!),
              ObligationsPage(
                setup: _repo!,
                repository: _obligations!,
                workspaceId: _spaceId!,
              ),
              NamedPage(
                repository: _repo!,
                workspaceId: _spaceId!,
                kind: SetupKind.channels,
              ),
              NamedPage(
                repository: _repo!,
                workspaceId: _spaceId!,
                kind: SetupKind.categories,
              ),
              NamedPage(
                repository: _repo!,
                workspaceId: _spaceId!,
                kind: SetupKind.counterparties,
              ),
              CurrenciesPage(repository: _repo!),
              DataSecurityPage(database: _database!, onRestored: _load),
            ],
          ),
    bottomNavigationBar: _FloatingNavigation(
      index: switch (_page) {
        1 => 1,
        3 => 2,
        4 => 3,
        _ => 0,
      },
      onChanged: (v) => setState(() => _page = const [0, 1, 3, 4][v]),
    ),
    floatingActionButton: _repo == null || _spaceId == null
        ? null
        : FloatingActionButton(
            onPressed: _showQuickAdd,
            tooltip: 'إضافة سريعة',
            backgroundColor: AppTheme.gold,
            foregroundColor: AppTheme.ink,
            shape: const CircleBorder(),
            child: const Icon(Icons.add_rounded, size: 32),
          ),
    floatingActionButtonLocation: const _QuickFabLocation(),
  );

  Future<void> _showQuickAdd() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إضافة سريعة',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'اختار نوع الحركة وابدأ مباشرة',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  _QuickAddTile('expense', 'مصروف', Icons.north_east_rounded),
                  _QuickAddTile('income', 'دخل', Icons.south_west_rounded),
                  _QuickAddTile('transfer', 'تحويل', Icons.swap_horiz_rounded),
                  _QuickAddTile('atm', 'سحب ATM', Icons.local_atm_outlined),
                  _QuickAddTile(
                    'debt',
                    'دين / مستحق',
                    Icons.handshake_outlined,
                  ),
                  _QuickAddTile(
                    'opening_balance',
                    'رصيد افتتاحي',
                    Icons.flag_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'debt') {
      setState(() => _page = 5);
      return;
    }
    setState(() => _page = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _movementsKey.currentState?.add(initialType: action);
    });
  }

  Future<void> _addWorkspace() async {
    final v = await nameTypeDialog(context, 'مساحة عمل جديدة', const {
      'personal': 'شخصي',
      'freelance': 'فريلانس',
      'business': 'شركة',
      'other': 'أخرى',
    });
    if (v == null || _repo == null) return;
    try {
      _spaceId = await _repo!.createWorkspace(name: v.$1, type: v.$2);
      await _load();
    } on DatabaseException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('الاسم مستخدم بالفعل')));
      }
    }
  }

  Future<void> _showAbout() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppTheme.ink,
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppTheme.gold,
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          Text('عَ الحساب', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('الإصدار 1.5.0', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          const Text(
            'تطوير وإنتاج خدماتك للبرمجيات',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '© 2026 خدماتك للبرمجيات\nالكود مفتوح المصدر بترخيص Apache 2.0\nالاسم والعلامة التجارية محفوظان',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'تطبيق لإدارة الحسابات والمصروفات محليًا على جهازك.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _showPrivacyPolicy(context),
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('سياسة الخصوصية'),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('تم'),
        ),
      ],
    ),
  );

  Future<void> _showPrivacyPolicy(
    BuildContext dialogContext,
  ) => showDialog<void>(
    context: dialogContext,
    builder: (context) => AlertDialog(
      title: const Text('سياسة الخصوصية'),
      content: const SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Text(
            'عَ الحساب تطبيق يعمل محليًا ولا ينشئ حساب مستخدم ولا يرسل بياناتك المالية إلى خدماتك للبرمجيات أو أي طرف ثالث.\n\n'
            'تُحفظ الحسابات والحركات والفئات والديون والنسخ الاحتياطية داخل مساحة التطبيق على جهازك. لا يحتوي الإصدار الحالي على إعلانات أو تحليلات أو تتبع، ولا يطلب صلاحيات الإنترنت أو جهات الاتصال أو الموقع أو الصور.\n\n'
            'أنت مسؤول عن حماية جهازك والاحتفاظ بنسخة احتياطية آمنة قبل حذف التطبيق أو بياناته. حذف التطبيق قد يؤدي إلى حذف البيانات المحلية نهائيًا.\n\n'
            'الناشر والمطور: خدماتك للبرمجيات\nآخر تحديث: 15 سبتمبر 2026',
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('فهمت'),
        ),
      ],
    ),
  );
}

class AccountsPage extends StatefulWidget {
  const AccountsPage({
    super.key,
    required this.repository,
    required this.workspaceId,
  });
  final FinanceSetupRepository repository;
  final int workspaceId;
  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _FloatingNavigation extends StatelessWidget {
  const _FloatingNavigation({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const items = <(IconData, String)>[
    (Icons.home_rounded, 'الرئيسية'),
    (Icons.swap_vert_rounded, 'حركة'),
    (Icons.donut_large_rounded, 'ميزانية'),
    (Icons.bar_chart_rounded, 'التقارير'),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
    child: Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final selected = i == index;
          return Expanded(
            child: Semantics(
              selected: selected,
              label: items[i].$2,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        items[i].$1,
                        color: selected ? AppTheme.ink : Colors.white70,
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$2,
                        maxLines: 1,
                        style: TextStyle(
                          color: selected ? AppTheme.ink : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class _QuickAddTile extends StatelessWidget {
  const _QuickAddTile(this.value, this.label, this.icon);
  final String value, label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.pop(context, value),
    borderRadius: BorderRadius.circular(24),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: value == 'expense'
            ? AppTheme.gold
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.ink, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
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

class _QuickFabLocation extends FloatingActionButtonLocation {
  const _QuickFabLocation();
  @override
  Offset getOffset(ScaffoldPrelayoutGeometry geometry) {
    final x =
        (geometry.scaffoldSize.width -
            geometry.floatingActionButtonSize.width) /
        2;
    final y =
        geometry.scaffoldSize.height -
        geometry.bottomSheetSize.height -
        geometry.floatingActionButtonSize.height -
        104;
    return Offset(x, y);
  }
}

class _AccountsPageState extends State<AccountsPage> {
  List<AccountItem>? items;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant AccountsPage old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId) load();
  }

  Future<void> load() async {
    final v = await widget.repository.listAccounts(widget.workspaceId);
    if (mounted) setState(() => items = v);
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: 'حساباتك وأرصدتك',
    subtitle: 'البنك والمحفظة والكاش وPayPal في مكان واحد',
    onAdd: add,
    child: items == null
        ? const Center(child: CircularProgressIndicator())
        : items!.isEmpty
        ? const EmptyView('أضف أول حساب، ثم أضف له عملة أو أكثر')
        : ListView(
            children: items!
                .map(
                  (a) => Card(
                    child: ExpansionTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: AppTheme.goldSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(accountIcon(a.type), color: AppTheme.ink),
                      ),
                      title: Text(a.name),
                      subtitle: Text(
                        '${accountType(a.type)}${a.isFavorite ? '  •  مفضل' : ''}',
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: Icon(a.isFavorite ? Icons.star : Icons.more_vert),
                        onSelected: (value) async {
                          if (value == 'pocket') await addPocket(a);
                          if (value == 'rename') await renameAccount(a);
                          if (value == 'favorite') {
                            await widget.repository.setAccountFavorite(
                              a.id,
                              !a.isFavorite,
                            );
                            await load();
                          }
                          if (value == 'up' || value == 'down') {
                            await widget.repository.moveAccount(
                              a.id,
                              a.sortOrder + (value == 'up' ? -1 : 1),
                            );
                            await load();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.edit_outlined),
                              title: Text('تعديل اسم الحساب'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'pocket',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.add_circle_outline),
                              title: Text('إضافة عملة'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'favorite',
                            child: Text(
                              a.isFavorite ? 'إلغاء التفضيل' : 'جعله مفضلاً',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'up',
                            child: Text('تحريك لأعلى'),
                          ),
                          const PopupMenuItem(
                            value: 'down',
                            child: Text('تحريك لأسفل'),
                          ),
                        ],
                      ),
                      children: a.pockets.isEmpty
                          ? const [ListTile(title: Text('لا توجد أرصدة بعد'))]
                          : a.pockets
                                .map(
                                  (p) => ListTile(
                                    leading: const Icon(Icons.savings_outlined),
                                    title: Row(
                                      children: [
                                        Text(p.currencyCode),
                                        if (p.isDefault) ...[
                                          const SizedBox(width: 8),
                                          const Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            avatar: Icon(
                                              Icons.star_rounded,
                                              size: 16,
                                            ),
                                            label: Text('الافتراضية'),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(
                                      (p.balanceMinor / 100).toStringAsFixed(2),
                                      textDirection: TextDirection.ltr,
                                    ),
                                    trailing: IconButton(
                                      tooltip: p.isDefault
                                          ? 'العملة الافتراضية'
                                          : 'اجعلها العملة الافتراضية',
                                      onPressed: p.isDefault
                                          ? null
                                          : () async {
                                              await widget.repository
                                                  .setDefaultPocket(p.id);
                                              await load();
                                            },
                                      icon: Icon(
                                        p.isDefault
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                        color: p.isDefault
                                            ? AppTheme.gold
                                            : null,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                    ),
                  ),
                )
                .toList(),
          ),
  );
  Future<void> add() async {
    final v = await nameTypeDialog(context, 'حساب جديد', const {
      'cash': 'كاش',
      'bank': 'حساب بنكي',
      'mobile_wallet': 'محفظة موبايل',
      'paypal': 'PayPal',
      'other': 'آخر',
    });
    if (v == null) return;
    await widget.repository.createAccount(
      workspaceId: widget.workspaceId,
      name: v.$1,
      type: v.$2,
    );
    await load();
  }

  Future<void> addPocket(AccountItem account) async {
    final currencies = (await widget.repository.listCurrencies())
        .where((e) => e.isActive)
        .toList();
    if (!mounted || currencies.isEmpty) return;
    String selected = currencies.first.code;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('عملة ${account.name}'),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            items: currencies
                .map(
                  (e) => DropdownMenuItem(
                    value: e.code,
                    child: Text('${e.code} — ${e.symbol}'),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => selected = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await widget.repository.createPocket(
          accountId: account.id,
          currencyCode: selected,
        );
        await load();
      } on DatabaseException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('العملة موجودة بالفعل في الحساب')),
          );
        }
      }
    }
  }

  Future<void> renameAccount(AccountItem account) async {
    final controller = TextEditingController(text: account.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل اسم الحساب'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'اسم الحساب'),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name == account.name) return;
    try {
      await widget.repository.renameAccount(account.id, name);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تعديل اسم الحساب')));
      }
    } on DatabaseException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يوجد حساب آخر بنفس الاسم')),
        );
      }
    }
  }
}

enum SetupKind { channels, categories, counterparties }

class NamedPage extends StatefulWidget {
  const NamedPage({
    super.key,
    required this.repository,
    required this.workspaceId,
    required this.kind,
  });
  final FinanceSetupRepository repository;
  final int workspaceId;
  final SetupKind kind;
  @override
  State<NamedPage> createState() => _NamedPageState();
}

class _NamedPageState extends State<NamedPage> {
  List<NamedSetupItem>? items;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant NamedPage old) {
    super.didUpdateWidget(old);
    if (old.workspaceId != widget.workspaceId) load();
  }

  Future<void> load() async {
    final future = switch (widget.kind) {
      SetupKind.channels => widget.repository.listChannels(widget.workspaceId),
      SetupKind.categories => widget.repository.listCategories(
        widget.workspaceId,
      ),
      SetupKind.counterparties => widget.repository.listCounterparties(
        widget.workspaceId,
      ),
    };
    final v = await future;
    if (mounted) setState(() => items = v);
  }

  String get title => switch (widget.kind) {
    SetupKind.channels => 'قنوات الدفع',
    SetupKind.categories => 'فئات الدخل والمصروف',
    SetupKind.counterparties => 'العملاء والموردون والأطراف',
  };
  @override
  Widget build(BuildContext context) => PageShell(
    title: title,
    subtitle: widget.kind == SetupKind.channels
        ? 'اربط InstaPay بالحساب البنكي الذي يحرك رصيده'
        : null,
    onAdd: add,
    child: items == null
        ? const Center(child: CircularProgressIndicator())
        : items!.isEmpty
        ? const EmptyView('لا توجد عناصر بعد')
        : ListView(
            children: items!
                .map(
                  (e) => Card(
                    child: ListTile(
                      leading: Icon(
                        widget.kind == SetupKind.channels
                            ? Icons.hub_outlined
                            : widget.kind == SetupKind.categories
                            ? Icons.label_outline
                            : Icons.person_outline,
                      ),
                      title: Text(e.displayName),
                      subtitle: Text(
                        '${typeLabel(e.type)}${e.details == null ? '' : ' • ${e.details}'}',
                      ),
                      onTap: widget.kind == SetupKind.categories
                          ? () => editCategory(e)
                          : null,
                    ),
                  ),
                )
                .toList(),
          ),
  );
  Future<void> add() async {
    if (widget.kind == SetupKind.categories) {
      await addCategory();
      return;
    }
    final types = switch (widget.kind) {
      SetupKind.channels => const {
        'instapay': 'InstaPay',
        'atm': 'ماكينة ATM',
        'bank_transfer': 'تحويل بنكي',
        'paypal': 'PayPal',
        'manual': 'يدوي',
        'other': 'أخرى',
      },
      SetupKind.categories => const {'expense': 'مصروف', 'income': 'دخل'},
      SetupKind.counterparties => const {
        'client': 'عميل',
        'vendor': 'مورد',
        'lender': 'دائن',
        'borrower': 'مدين',
        'other': 'آخر',
      },
    };
    final v = await nameTypeDialog(context, 'إضافة إلى $title', types);
    if (v == null) return;
    if (widget.kind == SetupKind.channels) {
      final id = await widget.repository.createChannel(
        workspaceId: widget.workspaceId,
        name: v.$1,
        type: v.$2,
      );
      if (v.$2 == 'instapay') {
        final banks = (await widget.repository.listAccounts(
          widget.workspaceId,
        )).where((e) => e.type == 'bank').toList();
        if (mounted && banks.isNotEmpty) {
          final bank = await showDialog<int>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('اربط InstaPay بأي بنك؟'),
              children: banks
                  .map(
                    (e) => SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, e.id),
                      child: Text(e.name),
                    ),
                  )
                  .toList(),
            ),
          );
          if (bank != null) {
            await widget.repository.linkChannelToAccount(
              channelId: id,
              accountId: bank,
            );
          }
        }
      }
    } else {
      await widget.repository.createCounterparty(
        workspaceId: widget.workspaceId,
        name: v.$1,
        type: v.$2,
      );
    }
    await load();
  }

  Future<void> addCategory() async {
    final input = await _categoryDialog();
    if (input == null) return;
    await widget.repository.createCategory(
      workspaceId: widget.workspaceId,
      name: input.$1,
      kind: input.$2,
      parentId: input.$3,
    );
    await load();
  }

  Future<void> editCategory(NamedSetupItem item) async {
    final input = await _categoryDialog(existing: item);
    if (input == null) return;
    await widget.repository.updateCategory(
      id: item.id,
      name: input.$1,
      parentId: input.$3,
    );
    await load();
  }

  Future<(String, String, int?)?> _categoryDialog({
    NamedSetupItem? existing,
  }) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    var kind = existing?.type ?? 'expense';
    int? parent = existing?.parentId;
    final result = await showDialog<(String, String, int?)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final roots = (items ?? [])
              .where(
                (e) =>
                    e.type == kind &&
                    e.parentId == null &&
                    e.id != existing?.id,
              )
              .toList();
          if (!roots.any((e) => e.id == parent)) parent = null;
          return AlertDialog(
            title: Text(existing == null ? 'فئة جديدة' : 'تعديل الفئة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'اسم الفئة'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'النوع'),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('مصروف')),
                    DropdownMenuItem(value: 'income', child: Text('دخل')),
                  ],
                  onChanged: existing == null
                      ? (v) => setDialogState(() {
                          kind = v!;
                          parent = null;
                        })
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: parent,
                  decoration: const InputDecoration(
                    labelText: 'الفئة الرئيسية (اختياري)',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('فئة رئيسية'),
                    ),
                    ...roots.map(
                      (e) => DropdownMenuItem<int?>(
                        value: e.id,
                        child: Text(e.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => parent = v),
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
                  final name = controller.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(context, (name, kind, parent));
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }
}

class CurrenciesPage extends StatefulWidget {
  const CurrenciesPage({super.key, required this.repository});
  final FinanceSetupRepository repository;
  @override
  State<CurrenciesPage> createState() => _CurrenciesPageState();
}

class _CurrenciesPageState extends State<CurrenciesPage> {
  List<CurrencyItem>? items;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final v = await widget.repository.listCurrencies();
    if (mounted) setState(() => items = v);
  }

  @override
  Widget build(BuildContext context) => PageShell(
    title: 'العملات',
    subtitle: 'فعّل العملات التي تتعامل بها',
    onAdd: add,
    child: items == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: items!
                .map(
                  (e) => Card(
                    child: SwitchListTile(
                      value: e.isActive,
                      onChanged: (v) async {
                        await widget.repository.setCurrencyActive(e.code, v);
                        await load();
                      },
                      title: Text(e.code, textDirection: TextDirection.ltr),
                      subtitle: Text(e.symbol),
                      secondary: const Icon(Icons.currency_exchange),
                    ),
                  ),
                )
                .toList(),
          ),
  );
  Future<void> add() async {
    final code = TextEditingController(), symbol = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('عملة جديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'الكود، مثال EUR'),
            ),
            TextField(
              controller: symbol,
              decoration: const InputDecoration(labelText: 'الرمز، مثال €'),
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
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repository.createCurrency(
        code: code.text,
        symbol: symbol.text,
      );
      await load();
    }
  }
}

class PageShell extends StatelessWidget {
  const PageShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.onAdd,
    required this.child,
  });
  final String title;
  final String? subtitle;
  final VoidCallback onAdd;
  final Widget child;
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
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('إضافة'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(child: child),
      ],
    ),
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, textAlign: TextAlign.center));
}

Future<(String, String)?> nameTypeDialog(
  BuildContext context,
  String title,
  Map<String, String> types,
) async {
  final name = TextEditingController();
  String selected = types.keys.first;
  return showDialog<(String, String)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'النوع'),
              items: types.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => selected = v!),
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
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(context, (name.text.trim(), selected));
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    ),
  );
}

IconData accountIcon(String type) => switch (type) {
  'cash' => Icons.payments_outlined,
  'bank' => Icons.account_balance_outlined,
  'mobile_wallet' => Icons.phone_android,
  'paypal' => Icons.public,
  _ => Icons.wallet_outlined,
};
String accountType(String type) =>
    const {
      'cash': 'كاش',
      'bank': 'حساب بنكي',
      'mobile_wallet': 'محفظة موبايل',
      'paypal': 'PayPal',
      'other': 'حساب آخر',
    }[type] ??
    type;
String typeLabel(String type) =>
    const {
      'income': 'دخل',
      'expense': 'مصروف',
      'instapay': 'InstaPay',
      'atm': 'ATM',
      'bank_transfer': 'تحويل بنكي',
      'paypal': 'PayPal',
      'manual': 'يدوي',
      'client': 'عميل',
      'vendor': 'مورد',
      'lender': 'دائن',
      'borrower': 'مدين',
      'other': 'آخر',
    }[type] ??
    type;
