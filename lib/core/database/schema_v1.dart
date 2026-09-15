import 'package:sqflite/sqflite.dart';

abstract final class SchemaV1 {
  static const statements = <String>[
    '''
      CREATE TABLE app_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE workspaces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE,
        type TEXT NOT NULL CHECK (type IN ('personal','freelance','business','other')),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (name COLLATE NOCASE)
      )
    ''',
    '''
      CREATE TABLE currencies (
        code TEXT PRIMARY KEY COLLATE NOCASE,
        symbol TEXT NOT NULL,
        decimal_digits INTEGER NOT NULL DEFAULT 2 CHECK (decimal_digits BETWEEN 0 AND 3),
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
        name TEXT NOT NULL COLLATE NOCASE,
        type TEXT NOT NULL CHECK (type IN ('cash','bank','mobile_wallet','paypal','other')),
        institution TEXT,
        identifier_hint TEXT,
        allow_negative INTEGER NOT NULL DEFAULT 0 CHECK (allow_negative IN (0,1)),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (workspace_id, name COLLATE NOCASE)
      )
    ''',
    '''
      CREATE TABLE account_pockets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE RESTRICT,
        currency_code TEXT NOT NULL REFERENCES currencies(code) ON UPDATE CASCADE ON DELETE RESTRICT,
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (account_id, currency_code)
      )
    ''',
    '''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
        name TEXT NOT NULL COLLATE NOCASE,
        kind TEXT NOT NULL CHECK (kind IN ('income','expense')),
        icon TEXT,
        color_hex TEXT,
        is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0,1)),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (workspace_id, kind, name COLLATE NOCASE)
      )
    ''',
    '''
      CREATE TABLE counterparties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
        name TEXT NOT NULL COLLATE NOCASE,
        type TEXT NOT NULL DEFAULT 'other' CHECK (type IN ('client','vendor','lender','borrower','other')),
        contact_note TEXT,
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (workspace_id, name COLLATE NOCASE)
      )
    ''',
    '''
      CREATE TABLE payment_channels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
        name TEXT NOT NULL COLLATE NOCASE,
        type TEXT NOT NULL CHECK (type IN ('instapay','atm','bank_transfer','paypal','manual','other')),
        is_archived INTEGER NOT NULL DEFAULT 0 CHECK (is_archived IN (0,1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE (workspace_id, name COLLATE NOCASE)
      )
    ''',
    '''
      CREATE TABLE channel_accounts (
        channel_id INTEGER NOT NULL REFERENCES payment_channels(id) ON DELETE CASCADE,
        account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
        PRIMARY KEY (channel_id, account_id)
      )
    ''',
    '''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
        type TEXT NOT NULL CHECK (type IN ('income','expense','transfer','opening_balance','adjustment','obligation_funding','obligation_settlement')),
        category_id INTEGER REFERENCES categories(id) ON DELETE RESTRICT,
        counterparty_id INTEGER REFERENCES counterparties(id) ON DELETE SET NULL,
        channel_id INTEGER REFERENCES payment_channels(id) ON DELETE SET NULL,
        related_transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL,
        occurred_on TEXT NOT NULL CHECK (occurred_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        note TEXT,
        status TEXT NOT NULL DEFAULT 'posted' CHECK (status IN ('posted','voided')),
        void_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK ((status = 'posted' AND void_reason IS NULL) OR (status = 'voided' AND length(trim(void_reason)) > 0))
      )
    ''',
    '''
      CREATE TABLE ledger_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
        pocket_id INTEGER NOT NULL REFERENCES account_pockets(id) ON DELETE RESTRICT,
        role TEXT NOT NULL CHECK (role IN ('source','destination','single')),
        amount_minor INTEGER NOT NULL CHECK (amount_minor != 0),
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE transaction_fx_details (
        transaction_id INTEGER PRIMARY KEY REFERENCES transactions(id) ON DELETE CASCADE,
        source_currency_code TEXT NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
        source_amount_minor INTEGER NOT NULL CHECK (source_amount_minor > 0),
        destination_currency_code TEXT NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
        destination_amount_minor INTEGER NOT NULL CHECK (destination_amount_minor > 0),
        created_at TEXT NOT NULL,
        CHECK (source_currency_code COLLATE NOCASE != destination_currency_code COLLATE NOCASE)
      )
    ''',
    '''
      CREATE TABLE obligations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
        counterparty_id INTEGER NOT NULL REFERENCES counterparties(id) ON DELETE RESTRICT,
        direction TEXT NOT NULL CHECK (direction IN ('payable','receivable')),
        nature TEXT NOT NULL CHECK (nature IN ('loan','credit_purchase','invoice','money_lent','other')),
        currency_code TEXT NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
        category_id INTEGER REFERENCES categories(id) ON DELETE RESTRICT,
        principal_minor INTEGER NOT NULL CHECK (principal_minor > 0),
        opened_on TEXT NOT NULL CHECK (opened_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        due_on TEXT CHECK (due_on IS NULL OR due_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
        note TEXT,
        status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','partial','settled','cancelled')),
        cancel_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        CHECK (due_on IS NULL OR due_on >= opened_on),
        CHECK ((status != 'cancelled' AND cancel_reason IS NULL) OR (status = 'cancelled' AND length(trim(cancel_reason)) > 0)),
        CHECK ((nature IN ('loan','credit_purchase') AND direction = 'payable') OR (nature IN ('invoice','money_lent') AND direction = 'receivable') OR nature = 'other')
      )
    ''',
    '''
      CREATE TABLE obligation_fundings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        obligation_id INTEGER NOT NULL REFERENCES obligations(id) ON DELETE RESTRICT,
        transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE obligation_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        obligation_id INTEGER NOT NULL REFERENCES obligations(id) ON DELETE RESTRICT,
        transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE RESTRICT,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        created_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE budgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workspace_id INTEGER NOT NULL REFERENCES workspaces(id) ON DELETE RESTRICT,
        currency_code TEXT NOT NULL REFERENCES currencies(code) ON DELETE RESTRICT,
        category_id INTEGER REFERENCES categories(id) ON DELETE RESTRICT,
        monthly_limit_minor INTEGER NOT NULL CHECK (monthly_limit_minor > 0),
        alert_threshold_percent INTEGER NOT NULL DEFAULT 80 CHECK (alert_threshold_percent BETWEEN 1 AND 99),
        month TEXT NOT NULL CHECK (month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''',
    '''
      CREATE TABLE budget_alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        budget_id INTEGER NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
        level TEXT NOT NULL CHECK (level IN ('threshold','exceeded')),
        triggered_at TEXT NOT NULL,
        UNIQUE (budget_id, level)
      )
    ''',
    'CREATE INDEX idx_accounts_workspace ON accounts(workspace_id)',
    'CREATE INDEX idx_pockets_account ON account_pockets(account_id)',
    'CREATE INDEX idx_transactions_workspace_date ON transactions(workspace_id, occurred_on)',
    'CREATE INDEX idx_transactions_category_date ON transactions(category_id, occurred_on)',
    'CREATE INDEX idx_transactions_counterparty ON transactions(counterparty_id)',
    'CREATE INDEX idx_transactions_channel ON transactions(channel_id)',
    'CREATE INDEX idx_entries_pocket_transaction ON ledger_entries(pocket_id, transaction_id)',
    'CREATE INDEX idx_obligations_status ON obligations(workspace_id, direction, status, due_on)',
    'CREATE INDEX idx_obligations_counterparty ON obligations(counterparty_id)',
    'CREATE INDEX idx_obligation_fundings_obligation ON obligation_fundings(obligation_id)',
    '''
      CREATE UNIQUE INDEX uq_category_budget
      ON budgets(workspace_id, currency_code, category_id, month)
      WHERE category_id IS NOT NULL
    ''',
    '''
      CREATE UNIQUE INDEX uq_general_budget
      ON budgets(workspace_id, currency_code, month)
      WHERE category_id IS NULL
    ''',
    '''
      CREATE TRIGGER trg_channel_account_same_workspace
      BEFORE INSERT ON channel_accounts
      BEGIN
        SELECT CASE WHEN (
          SELECT workspace_id FROM payment_channels WHERE id = NEW.channel_id
        ) != (
          SELECT workspace_id FROM accounts WHERE id = NEW.account_id
        ) THEN RAISE(ABORT, 'channel and account must belong to the same workspace') END;
      END
    ''',
    '''
      CREATE TRIGGER trg_transaction_references_same_workspace
      BEFORE INSERT ON transactions
      BEGIN
        SELECT CASE WHEN NEW.category_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM categories WHERE id = NEW.category_id AND workspace_id = NEW.workspace_id
        ) THEN RAISE(ABORT, 'category must belong to transaction workspace') END;
        SELECT CASE WHEN NEW.counterparty_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM counterparties WHERE id = NEW.counterparty_id AND workspace_id = NEW.workspace_id
        ) THEN RAISE(ABORT, 'counterparty must belong to transaction workspace') END;
        SELECT CASE WHEN NEW.channel_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM payment_channels WHERE id = NEW.channel_id AND workspace_id = NEW.workspace_id
        ) THEN RAISE(ABORT, 'channel must belong to transaction workspace') END;
        SELECT CASE WHEN NEW.type = 'income' AND NOT EXISTS (
          SELECT 1 FROM categories WHERE id = NEW.category_id AND kind = 'income'
        ) THEN RAISE(ABORT, 'income requires an income category') END;
        SELECT CASE WHEN NEW.type = 'expense' AND NOT EXISTS (
          SELECT 1 FROM categories WHERE id = NEW.category_id AND kind = 'expense'
        ) THEN RAISE(ABORT, 'expense requires an expense category') END;
      END
    ''',
    '''
      CREATE TRIGGER trg_entry_same_workspace
      BEFORE INSERT ON ledger_entries
      BEGIN
        SELECT CASE WHEN (
          SELECT workspace_id FROM transactions WHERE id = NEW.transaction_id
        ) != (
          SELECT a.workspace_id FROM account_pockets p JOIN accounts a ON a.id = p.account_id WHERE p.id = NEW.pocket_id
        ) THEN RAISE(ABORT, 'entry pocket must belong to transaction workspace') END;
      END
    ''',
    '''
      CREATE TRIGGER trg_no_posted_transaction_delete
      BEFORE DELETE ON transactions WHEN OLD.status = 'posted'
      BEGIN
        SELECT RAISE(ABORT, 'posted transactions must be voided, not deleted');
      END
    ''',
    '''
      CREATE TRIGGER trg_no_posted_entry_update
      BEFORE UPDATE ON ledger_entries WHEN EXISTS (
        SELECT 1 FROM transactions WHERE id = OLD.transaction_id AND status = 'posted'
      )
      BEGIN
        SELECT RAISE(ABORT, 'posted ledger entries are immutable');
      END
    ''',
    '''
      CREATE TRIGGER trg_no_posted_entry_delete
      BEFORE DELETE ON ledger_entries WHEN EXISTS (
        SELECT 1 FROM transactions WHERE id = OLD.transaction_id AND status = 'posted'
      )
      BEGIN
        SELECT RAISE(ABORT, 'posted ledger entries are immutable');
      END
    ''',
    '''
      CREATE TRIGGER trg_obligation_category_rules
      BEFORE INSERT ON obligations
      BEGIN
        SELECT CASE WHEN NEW.category_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM categories WHERE id = NEW.category_id AND workspace_id = NEW.workspace_id
        ) THEN RAISE(ABORT, 'obligation category must belong to workspace') END;
        SELECT CASE WHEN NEW.nature = 'invoice' AND NOT EXISTS (
          SELECT 1 FROM categories WHERE id = NEW.category_id AND kind = 'income'
        ) THEN RAISE(ABORT, 'invoice requires an income category') END;
        SELECT CASE WHEN NEW.nature = 'credit_purchase' AND NOT EXISTS (
          SELECT 1 FROM categories WHERE id = NEW.category_id AND kind = 'expense'
        ) THEN RAISE(ABORT, 'credit purchase requires an expense category') END;
        SELECT CASE WHEN NEW.nature IN ('loan','money_lent') AND NEW.category_id IS NOT NULL
          THEN RAISE(ABORT, 'loan principal cannot have an income or expense category') END;
      END
    ''',
    '''
      CREATE TRIGGER trg_obligation_funding_limit
      BEFORE INSERT ON obligation_fundings
      BEGIN
        SELECT CASE WHEN NEW.amount_minor + COALESCE((
          SELECT SUM(f.amount_minor)
          FROM obligation_fundings f
          JOIN transactions t ON t.id = f.transaction_id
          WHERE f.obligation_id = NEW.obligation_id AND t.status = 'posted'
        ), 0) > (
          SELECT principal_minor FROM obligations WHERE id = NEW.obligation_id
        ) THEN RAISE(ABORT, 'funding exceeds obligation principal') END;
        SELECT CASE WHEN (
          SELECT workspace_id FROM transactions WHERE id = NEW.transaction_id
        ) != (
          SELECT workspace_id FROM obligations WHERE id = NEW.obligation_id
        ) THEN RAISE(ABORT, 'funding transaction must belong to obligation workspace') END;
      END
    ''',
    '''
      CREATE TRIGGER trg_obligation_payment_limit
      BEFORE INSERT ON obligation_payments
      BEGIN
        SELECT CASE WHEN NEW.amount_minor + COALESCE((
          SELECT SUM(p.amount_minor)
          FROM obligation_payments p
          JOIN transactions t ON t.id = p.transaction_id
          WHERE p.obligation_id = NEW.obligation_id AND t.status = 'posted'
        ), 0) > (
          SELECT principal_minor FROM obligations WHERE id = NEW.obligation_id
        ) THEN RAISE(ABORT, 'payment exceeds obligation remainder') END;
        SELECT CASE WHEN (
          SELECT workspace_id FROM transactions WHERE id = NEW.transaction_id
        ) != (
          SELECT workspace_id FROM obligations WHERE id = NEW.obligation_id
        ) THEN RAISE(ABORT, 'payment transaction must belong to obligation workspace') END;
      END
    ''',
    '''
      CREATE TRIGGER trg_budget_category_rules
      BEFORE INSERT ON budgets WHEN NEW.category_id IS NOT NULL
      BEGIN
        SELECT CASE WHEN NOT EXISTS (
          SELECT 1 FROM categories
          WHERE id = NEW.category_id AND workspace_id = NEW.workspace_id AND kind = 'expense'
        ) THEN RAISE(ABORT, 'budget category must be an expense category in the same workspace') END;
      END
    ''',
  ];

  static Future<void> create(Database db, DateTime now) async {
    for (final statement in statements) {
      await db.execute(statement);
    }
    await seed(db, now);
  }

  static Future<void> seed(Database db, DateTime now) async {
    final timestamp = now.toUtc().toIso8601String();
    await db.insert('app_metadata', {
      'key': 'schema_version',
      'value': '1',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('app_metadata', {
      'key': 'schema_initialized',
      'value': 'true',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    for (final currency in const [
      ('EGP', 'ج.م', 2),
      ('USD', r'$', 2),
      ('MAD', 'د.م', 2),
    ]) {
      await db.insert('currencies', {
        'code': currency.$1,
        'symbol': currency.$2,
        'decimal_digits': currency.$3,
        'created_at': timestamp,
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (final workspace in const [
      ('شخصي', 'personal'),
      ('فريلانس', 'freelance'),
      ('الشركة', 'business'),
    ]) {
      await db.insert('workspaces', {
        'name': workspace.$1,
        'type': workspace.$2,
        'created_at': timestamp,
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final workspaces = await db.query('workspaces', columns: ['id']);
    for (final workspace in workspaces) {
      final workspaceId = workspace['id']! as int;
      for (final category in const [
        ('أخرى', 'expense'),
        ('طعام', 'expense'),
        ('مواصلات', 'expense'),
        ('فواتير', 'expense'),
        ('رسوم وعمولات', 'expense'),
        ('دخل آخر', 'income'),
        ('راتب', 'income'),
        ('دخل مشروع', 'income'),
      ]) {
        await db.insert('categories', {
          'workspace_id': workspaceId,
          'name': category.$1,
          'kind': category.$2,
          'is_system': category.$1 == 'أخرى' || category.$1 == 'دخل آخر'
              ? 1
              : 0,
          'created_at': timestamp,
          'updated_at': timestamp,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }
}
