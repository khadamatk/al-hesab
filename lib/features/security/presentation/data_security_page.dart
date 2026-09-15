import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/widgets/app_empty_state.dart';

class DataSecurityPage extends StatefulWidget {
  const DataSecurityPage({
    super.key,
    required this.database,
    required this.onRestored,
  });
  final AppDatabase database;
  final Future<void> Function() onRestored;
  @override
  State<DataSecurityPage> createState() => _DataSecurityPageState();
}

class _DataSecurityPageState extends State<DataSecurityPage> {
  List<LocalBackup>? backups;
  bool busy = false;
  bool lockEnabled = false;
  @override
  void initState() {
    super.initState();
    lockEnabled = AppLockSettings.enabled.value;
    AppLockSettings.enabled.addListener(_syncLock);
    load();
  }

  void _syncLock() {
    if (mounted) setState(() => lockEnabled = AppLockSettings.enabled.value);
  }

  @override
  void dispose() {
    AppLockSettings.enabled.removeListener(_syncLock);
    super.dispose();
  }

  Future<void> load() async {
    final value = await widget.database.listBackups();
    if (mounted) setState(() => backups = value);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
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
                    'البيانات والأمان',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'نسخ محلية مفحوصة قبل الاستعادة',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: busy ? null : create,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.backup_outlined),
              label: const Text('نسخة جديدة'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: SwitchListTile(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('قفل التطبيق'),
            subtitle: const Text(
              'استخدم البصمة أو الوجه أو رمز قفل الجهاز، واقفل التطبيق عند خروجه للخلفية.',
            ),
            value: lockEnabled,
            onChanged: busy ? null : _setAppLock,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: .55),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'النسخ محفوظة داخل مساحة التطبيق على الجهاز. قبل الاستعادة نفحص سلامة SQLite وإصدار قاعدة البيانات، وننشئ رجوعًا مؤقتًا تلقائيًا إذا فشلت العملية.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('النسخ المتاحة', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Expanded(
          child: backups == null
              ? const Center(child: CircularProgressIndicator())
              : backups!.isEmpty
              ? AppEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'لسه مفيش نسخة احتياطية',
                  message:
                      'اعمل نسخة الآن قبل إدخال بيانات مهمة أو قبل أي تحديث كبير.',
                  actionLabel: 'إنشاء نسخة',
                  onAction: busy ? null : create,
                )
              : ListView(
                  children: backups!
                      .map(
                        (backup) => Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              child: const Icon(Icons.storage_outlined),
                            ),
                            title: Text(_date(backup.createdAt)),
                            subtitle: Text(
                              '${_size(backup.sizeBytes)} • قاعدة بيانات محلية',
                            ),
                            trailing: FilledButton.tonalIcon(
                              onPressed: busy ? null : () => restore(backup),
                              icon: const Icon(Icons.restore, size: 18),
                              label: const Text('استعادة'),
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

  Future<void> create() async {
    setState(() => busy = true);
    try {
      await widget.database.createBackup();
      await load();
      if (mounted) _message('تم إنشاء النسخة الاحتياطية بنجاح');
    } catch (_) {
      if (mounted) _message('تعذر إنشاء النسخة الاحتياطية');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _setAppLock(bool value) async {
    setState(() => busy = true);
    try {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        if (mounted) _message('الجهاز لا يدعم بصمة أو رمز قفل آمن');
        return;
      }
      final verified = await auth.authenticate(
        localizedReason: value
            ? 'أكد هويتك لتفعيل قفل عَ الحساب'
            : 'أكد هويتك لإلغاء قفل عَ الحساب',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (!verified) return;
      await AppLockSettings.setEnabled(value);
      if (mounted) _message(value ? 'تم تفعيل قفل التطبيق' : 'تم إلغاء القفل');
    } catch (_) {
      if (mounted) _message('تعذر استخدام قفل الجهاز');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore(LocalBackup backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restore),
        title: const Text('استعادة هذه النسخة؟'),
        content: Text(
          'سيتم استبدال البيانات الحالية بحالة ${_date(backup.createdAt)}. لو فشلت الاستعادة سنرجع البيانات الحالية تلقائيًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      await widget.database.restoreBackup(backup.path);
      await widget.onRestored();
      await load();
      if (mounted) _message('تمت استعادة البيانات بنجاح');
    } catch (_) {
      if (mounted) {
        _message(
          'النسخة غير صالحة أو تعذر استعادتها؛ بياناتك الحالية لم تتغير',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  static String _date(DateTime date) =>
      DateFormat('yyyy-MM-dd • HH:mm', 'ar').format(date.toLocal());
  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
