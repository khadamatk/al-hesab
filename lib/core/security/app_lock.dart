import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLockSettings {
  AppLockSettings._();

  static const _key = 'app_lock_enabled';
  static final enabled = ValueNotifier<bool>(false);
  static final _preferences = SharedPreferencesAsync();

  static Future<void> load() async {
    try {
      enabled.value = await _preferences.getBool(_key) ?? false;
    } catch (_) {
      enabled.value = false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    await _preferences.setBool(_key, value);
    enabled.value = value;
  }
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final auth = LocalAuthentication();
  bool loading = true;
  bool unlocked = false;
  bool authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLockSettings.enabled.addListener(_settingChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    await AppLockSettings.load();
    if (!mounted) return;
    setState(() {
      loading = false;
      unlocked = !AppLockSettings.enabled.value;
    });
    if (!unlocked) await _unlock();
  }

  void _settingChanged() {
    if (!mounted) return;
    setState(() => unlocked = !AppLockSettings.enabled.value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && AppLockSettings.enabled.value) {
      setState(() => unlocked = false);
    }
    if (state == AppLifecycleState.resumed &&
        AppLockSettings.enabled.value &&
        !unlocked) {
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (authenticating) return;
    setState(() => authenticating = true);
    try {
      final supported = await auth.isDeviceSupported();
      final success =
          supported &&
          await auth.authenticate(
            localizedReason: 'افتح عَ الحساب بالبصمة أو رمز قفل الجهاز',
            biometricOnly: false,
            persistAcrossBackgrounding: true,
          );
      if (mounted) setState(() => unlocked = success);
    } catch (_) {
      if (mounted) setState(() => unlocked = false);
    } finally {
      if (mounted) setState(() => authenticating = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppLockSettings.enabled.removeListener(_settingChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const ColoredBox(color: Color(0xFFF8F4EA));
    if (unlocked) return widget.child;
    return ColoredBox(
      color: const Color(0xFFF8F4EA),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 64),
              const SizedBox(height: 18),
              const Text(
                'عَ الحساب مقفول',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('بياناتك المالية مخفية لحد ما تفتح التطبيق.'),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: authenticating ? null : _unlock,
                icon: const Icon(Icons.fingerprint_rounded),
                label: Text(authenticating ? 'جاري التحقق...' : 'فتح التطبيق'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
