import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../doh/network_settings_service.dart';
import '../proxy/proxy_settings_service.dart';

/// rhttp 引擎使用模式
enum RhttpMode {
  /// 始终使用 rhttp
  always,

  /// 仅在启用代理/DOH 时使用
  proxyOnly,
}

/// rhttp 引擎设置
class RhttpSettings {
  const RhttpSettings({
    this.enabled = false,
    this.mode = RhttpMode.always,
  });

  final bool enabled;
  final RhttpMode mode;

  RhttpSettings copyWith({
    bool? enabled,
    RhttpMode? mode,
  }) {
    return RhttpSettings(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
    );
  }
}

/// rhttp 引擎设置管理服务
class RhttpSettingsService {
  RhttpSettingsService._internal();

  static final RhttpSettingsService instance = RhttpSettingsService._internal();

  static const _enabledKey = 'rhttp_enabled';
  static const _modeKey = 'rhttp_mode';

  final ValueNotifier<RhttpSettings> notifier = ValueNotifier(
    const RhttpSettings(),
  );

  SharedPreferences? _prefs;
  int _version = 0;

  int get version => _version;
  RhttpSettings get current => notifier.value;

  Future<void> initialize(SharedPreferences prefs) async {
    if (_prefs != null) return;
    _prefs = prefs;
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final modeIndex = prefs.getInt(_modeKey) ?? 0;
    final mode = modeIndex < RhttpMode.values.length
        ? RhttpMode.values[modeIndex]
        : RhttpMode.always;
    notifier.value = RhttpSettings(enabled: enabled, mode: mode);
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = _prefs;
    if (prefs == null) return;
    notifier.value = notifier.value.copyWith(enabled: enabled);
    await prefs.setBool(_enabledKey, enabled);
    _touch();
  }

  Future<void> setMode(RhttpMode mode) async {
    final prefs = _prefs;
    if (prefs == null) return;
    notifier.value = notifier.value.copyWith(mode: mode);
    await prefs.setInt(_modeKey, mode.index);
    _touch();
  }

  /// 强制禁用（Rhttp.init() 失败时调用）
  Future<void> forceDisable() async {
    await setEnabled(false);
    debugPrint('[rhttp] 已强制禁用（初始化失败）');
  }

  /// 综合判断当前是否应该使用 rhttp
  bool shouldUseRhttp(NetworkSettings ns, ProxySettings ps) {
    if (!current.enabled) return false;
    // rhttp fork 已支持 ECH（通过 TlsSettings.echConfigList），不再排除
    // proxyOnly 模式：仅代理/DOH 启用时使用
    if (current.mode == RhttpMode.proxyOnly) {
      return ns.dohEnabled || ps.isValid;
    }
    return true; // always 模式
  }

  void _touch() {
    _version++;
    notifier.value = notifier.value.copyWith();
  }
}
