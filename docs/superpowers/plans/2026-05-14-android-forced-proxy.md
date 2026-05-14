# Android Forced Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Android application-level forced proxy mode so every FluxDO network path either uses the user-configured HTTP CONNECT / SOCKS5 proxy through the local gateway or fails without direct connection.

**Architecture:** Extend the existing proxy settings and local Rust gateway path instead of adding Android `VpnService`. Forced mode starts `DohProxyService` as a pure upstream proxy gateway with `enableDoh=false`, then guards Dio, rhttp, WebView, image/cache, AI, update, and download paths so they cannot bypass `127.0.0.1:{localProxyPort}`.

**Tech Stack:** Flutter/Dart, Riverpod, Dio, rhttp, flutter_inappwebview `ProxyController`, flutter_cache_manager, SharedPreferences, existing Rust DOH proxy FFI/process wrapper.

---

## File Structure

- Modify `lib/services/network/proxy/proxy_settings_service.dart`: add forced-mode persisted setting, validation helpers, and test reset hook.
- Create `lib/services/network/proxy/forced_proxy_guard.dart`: central fail-closed guard and exception type used by adapters and direct network services.
- Modify `lib/services/network/doh/network_settings_service.dart`: start local gateway for forced proxy, expose forced runtime status, disable local DOH resolution in forced mode, and track WebView proxy override success.
- Modify `lib/services/network/adapters/network_http_adapter.dart`: fail closed before opening `HttpClient`, and force local gateway proxy when forced mode is on.
- Modify `lib/services/network/adapters/rhttp_adapter.dart`: force rhttp through local gateway in forced mode and avoid upstream direct proxy/DNS override.
- Modify `lib/services/network/adapters/platform_adapter.dart`: resolve adapter type and external adapter behavior consistently under forced mode.
- Modify `lib/services/network/adapters/webview_http_adapter.dart`: fail closed when forced mode is on but WebView proxy override is not ready.
- Modify `lib/services/network/cookie/csrf_token_service.dart`: rely on `DiscourseDio.create` or the forced guard consistently.
- Modify `lib/services/dio_http_client.dart` and `lib/services/discourse_cache_manager.dart`: make all cache managers use the Dio-backed client, including external image cache.
- Modify `lib/services/update_service.dart`, `lib/services/apk_download_service.dart`, and `lib/services/sticker_market_service.dart`: remove raw `Dio()` bypasses or explicitly block unproxyable OTA download in forced mode.
- Modify Android/WebView login UI in `lib/pages/webview_login_page.dart`: block loading with a clear error when forced proxy WebView setup failed.
- Modify settings UI in `lib/pages/network_settings_page/widgets/http_proxy_card.dart` and `lib/pages/network_settings_page/widgets/doh_settings_card.dart`: expose forced mode and show runtime status.
- Modify l10n ARB files in `lib/l10n/modules/network/` and regenerate generated localization.
- Add tests under `test/services/network/proxy/`, `test/services/network/adapters/`, and update existing network tests.

## Task 0: Workspace Prep

**Files:**
- Read: `docs/superpowers/specs/2026-05-14-android-forced-proxy-design.md`
- Read: `.gitmodules`
- Read: `core/doh_proxy`

- [ ] **Step 1: Initialize native proxy submodule**

Run:

```powershell
git submodule update --init --recursive
git submodule status
```

Expected: `core/doh_proxy` status no longer starts with `-`.

- [ ] **Step 2: Verify local tooling visibility**

Run:

```powershell
dart --version
git status --short --branch
```

Expected: Dart prints a version. Git may show the current branch ahead by documentation commits, but no unrelated source files should be modified.

- [ ] **Step 3: Inspect Rust proxy upstream fields**

Run:

```powershell
rg "upstream|socks|CONNECT|enable_doh|gateway" core/doh_proxy -n
```

Expected: Rust code contains upstream protocol/host/port handling used by `DohProxyService.start(...)`. If the Rust proxy cannot forward HTTP CONNECT or SOCKS5 with credentials, stop after this task and write a Rust-specific follow-up plan before Dart integration.

## Task 1: Forced Proxy Settings Model

**Files:**
- Modify: `lib/services/network/proxy/proxy_settings_service.dart`
- Create: `test/services/network/proxy/proxy_settings_service_test.dart`

- [ ] **Step 1: Write failing settings tests**

Create `test/services/network/proxy/proxy_settings_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluxdo/services/network/proxy/proxy_settings_service.dart';

void main() {
  group('ProxySettings forced mode', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ProxySettingsService.instance.resetForTesting();
    });

    test('disabled by default', () async {
      final prefs = await SharedPreferences.getInstance();
      await ProxySettingsService.instance.initialize(prefs);

      expect(ProxySettingsService.instance.current.forcedEnabled, isFalse);
      expect(ProxySettingsService.instance.current.isForcedValid, isFalse);
    });

    test('requires enabled server configuration', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ProxySettingsService.instance;
      await service.initialize(prefs);

      await service.setForcedEnabled(true);

      expect(service.current.forcedEnabled, isTrue);
      expect(service.current.isForcedValid, isFalse);
      expect(service.validateForcedMode(), '强制代理需要先配置有效的 HTTP 或 SOCKS5 代理');
    });

    test('HTTP proxy with credentials can be forced', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ProxySettingsService.instance;
      await service.initialize(prefs);

      await service.setServer(
        protocol: UpstreamProxyProtocol.http,
        host: 'proxy.example.com',
        port: 8080,
        username: 'user',
        password: 'pass',
      );
      await service.setEnabled(true);
      await service.setForcedEnabled(true);

      expect(service.current.isForcedValid, isTrue);
      expect(service.current.forcedProxyUri, 'http://user:pass@proxy.example.com:8080');
      expect(prefs.getBool('forced_proxy_enabled'), isTrue);
    });

    test('SOCKS5 proxy without credentials can be forced', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ProxySettingsService.instance;
      await service.initialize(prefs);

      await service.setServer(
        protocol: UpstreamProxyProtocol.socks5,
        host: '127.0.0.1',
        port: 1080,
      );
      await service.setEnabled(true);
      await service.setForcedEnabled(true);

      expect(service.current.isForcedValid, isTrue);
      expect(service.current.forcedProxyUri, 'socks5://127.0.0.1:1080');
    });

    test('Shadowsocks is not valid for forced mode', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ProxySettingsService.instance;
      await service.initialize(prefs);

      await service.setServer(
        protocol: UpstreamProxyProtocol.shadowsocks,
        host: 'example.com',
        port: 8388,
        password: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=',
        cipher: '2022-blake3-aes-256-gcm',
      );
      await service.setEnabled(true);
      await service.setForcedEnabled(true);

      expect(service.current.isValid, isTrue);
      expect(service.current.isForcedValid, isFalse);
      expect(service.validateForcedMode(), '强制代理仅支持 HTTP 和 SOCKS5');
    });
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/proxy/proxy_settings_service_test.dart
```

Expected: FAIL because `forcedEnabled`, `isForcedValid`, `forcedProxyUri`, `validateForcedMode`, and `resetForTesting` do not exist.

- [ ] **Step 3: Implement forced settings fields**

In `lib/services/network/proxy/proxy_settings_service.dart`, update `ProxySettings`:

```dart
class ProxySettings {
  const ProxySettings({
    this.enabled = false,
    this.forcedEnabled = false,
    this.protocol = UpstreamProxyProtocol.http,
    this.host = '',
    this.port = 0,
    this.username,
    this.password,
    this.cipher = '',
  });

  final bool enabled;
  final bool forcedEnabled;
  final UpstreamProxyProtocol protocol;
  final String host;
  final int port;
  final String? username;
  final String? password;
  final String cipher;

  bool get hasServer => host.isNotEmpty && port > 0;

  bool get supportsForcedMode =>
      protocol == UpstreamProxyProtocol.http ||
      protocol == UpstreamProxyProtocol.socks5;

  bool get isForcedValid => forcedEnabled && enabled && isValid && supportsForcedMode;

  String? get forcedProxyUri {
    if (!isForcedValid) return null;
    final scheme = protocol == UpstreamProxyProtocol.socks5 ? 'socks5' : 'http';
    final user = username?.trim();
    if (user != null && user.isNotEmpty) {
      final encodedUser = Uri.encodeComponent(user);
      final encodedPass = Uri.encodeComponent(password ?? '');
      return '$scheme://$encodedUser:$encodedPass@$host:$port';
    }
    return '$scheme://$host:$port';
  }

  ProxySettings copyWith({
    bool? enabled,
    bool? forcedEnabled,
    UpstreamProxyProtocol? protocol,
    String? host,
    int? port,
    String? username,
    String? password,
    String? cipher,
  }) {
    return ProxySettings(
      enabled: enabled ?? this.enabled,
      forcedEnabled: forcedEnabled ?? this.forcedEnabled,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      cipher: cipher ?? this.cipher,
    );
  }
}
```

Add service key, initialization, setter, validation, and test reset:

```dart
static const _forcedEnabledKey = 'forced_proxy_enabled';

Future<void> initialize(SharedPreferences prefs) async {
  if (_prefs != null) return;
  _prefs = prefs;

  final enabled = prefs.getBool(_enabledKey) ?? false;
  final forcedEnabled = prefs.getBool(_forcedEnabledKey) ?? false;
  final protocol = UpstreamProxyProtocol.fromStorage(
    prefs.getString(_protocolKey),
  );
  final host = prefs.getString(_hostKey) ?? '';
  final port = prefs.getInt(_portKey) ?? 0;
  final username = prefs.getString(_usernameKey);
  final password = prefs.getString(_passwordKey);
  final cipher = prefs.getString(_cipherKey) ?? '';

  notifier.value = ProxySettings(
    enabled: enabled,
    forcedEnabled: forcedEnabled,
    protocol: protocol,
    host: host,
    port: port,
    username: username,
    password: password,
    cipher: cipher,
  );
}

Future<void> setForcedEnabled(bool enabled) async {
  final prefs = _prefs;
  if (prefs == null) return;
  notifier.value = notifier.value.copyWith(forcedEnabled: enabled);
  await prefs.setBool(_forcedEnabledKey, enabled);
  _resetTestResult();
  _touch();
}

String? validateForcedMode() {
  final settings = current;
  if (!settings.forcedEnabled) return null;
  if (!settings.supportsForcedMode) {
    return '强制代理仅支持 HTTP 和 SOCKS5';
  }
  if (!settings.enabled || !settings.hasServer || settings.port <= 0) {
    return '强制代理需要先配置有效的 HTTP 或 SOCKS5 代理';
  }
  if (!settings.isValid) {
    return '强制代理配置无效';
  }
  return null;
}

@visibleForTesting
void resetForTesting() {
  _prefs = null;
  _version = 0;
  _activeTest = null;
  notifier.value = const ProxySettings();
  testResultNotifier.value = null;
  isTesting.value = false;
}
```

Update existing `setServer` so the new value preserves `forcedEnabled`:

```dart
notifier.value = ProxySettings(
  enabled: notifier.value.enabled,
  forcedEnabled: notifier.value.forcedEnabled,
  protocol: protocol,
  host: host,
  port: port,
  username: protocol == UpstreamProxyProtocol.shadowsocks ? null : username,
  password: password,
  cipher: protocol == UpstreamProxyProtocol.shadowsocks
      ? normalizeShadowsocksCipher(cipher)
      : '',
);
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/proxy/proxy_settings_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```powershell
git add lib/services/network/proxy/proxy_settings_service.dart test/services/network/proxy/proxy_settings_service_test.dart
git commit -m "feat: add forced proxy settings"
```

Expected: commit succeeds.

## Task 2: Central Fail-Closed Guard

**Files:**
- Create: `lib/services/network/proxy/forced_proxy_guard.dart`
- Create: `test/services/network/proxy/forced_proxy_guard_test.dart`

- [ ] **Step 1: Write failing guard tests**

Create `test/services/network/proxy/forced_proxy_guard_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/proxy/forced_proxy_guard.dart';

void main() {
  group('ForcedProxyGuard', () {
    test('allows requests when forced mode is disabled', () {
      expect(
        () => ForcedProxyGuard.ensureReady(
          forcedEnabled: false,
          forcedConfigValid: false,
          localGatewayReady: false,
          webViewRequired: false,
          webViewProxyReady: false,
        ),
        returnsNormally,
      );
    });

    test('blocks invalid forced configuration', () {
      expect(
        () => ForcedProxyGuard.ensureReady(
          forcedEnabled: true,
          forcedConfigValid: false,
          localGatewayReady: false,
          webViewRequired: false,
          webViewProxyReady: false,
        ),
        throwsA(
          isA<ForcedProxyException>().having(
            (e) => e.reason,
            'reason',
            ForcedProxyFailureReason.notConfigured,
          ),
        ),
      );
    });

    test('blocks missing local gateway', () {
      expect(
        () => ForcedProxyGuard.ensureReady(
          forcedEnabled: true,
          forcedConfigValid: true,
          localGatewayReady: false,
          webViewRequired: false,
          webViewProxyReady: false,
        ),
        throwsA(
          isA<ForcedProxyException>().having(
            (e) => e.message,
            'message',
            '强制代理网关未就绪',
          ),
        ),
      );
    });

    test('blocks WebView when proxy override failed', () {
      expect(
        () => ForcedProxyGuard.ensureReady(
          forcedEnabled: true,
          forcedConfigValid: true,
          localGatewayReady: true,
          webViewRequired: true,
          webViewProxyReady: false,
        ),
        throwsA(
          isA<ForcedProxyException>().having(
            (e) => e.reason,
            'reason',
            ForcedProxyFailureReason.webViewProxyNotReady,
          ),
        ),
      );
    });

    test('allows ready forced proxy', () {
      expect(
        () => ForcedProxyGuard.ensureReady(
          forcedEnabled: true,
          forcedConfigValid: true,
          localGatewayReady: true,
          webViewRequired: true,
          webViewProxyReady: true,
        ),
        returnsNormally,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/proxy/forced_proxy_guard_test.dart
```

Expected: FAIL because `forced_proxy_guard.dart` does not exist.

- [ ] **Step 3: Implement guard**

Create `lib/services/network/proxy/forced_proxy_guard.dart`:

```dart
enum ForcedProxyFailureReason {
  notConfigured,
  gatewayNotReady,
  webViewProxyNotReady,
}

class ForcedProxyException implements Exception {
  const ForcedProxyException(this.reason, this.message);

  final ForcedProxyFailureReason reason;
  final String message;

  @override
  String toString() => message;
}

class ForcedProxyGuard {
  const ForcedProxyGuard._();

  static void ensureReady({
    required bool forcedEnabled,
    required bool forcedConfigValid,
    required bool localGatewayReady,
    required bool webViewRequired,
    required bool webViewProxyReady,
  }) {
    if (!forcedEnabled) return;
    if (!forcedConfigValid) {
      throw const ForcedProxyException(
        ForcedProxyFailureReason.notConfigured,
        '强制代理未配置',
      );
    }
    if (!localGatewayReady) {
      throw const ForcedProxyException(
        ForcedProxyFailureReason.gatewayNotReady,
        '强制代理网关未就绪',
      );
    }
    if (webViewRequired && !webViewProxyReady) {
      throw const ForcedProxyException(
        ForcedProxyFailureReason.webViewProxyNotReady,
        'WebView 无法使用强制代理，已阻止直连',
      );
    }
  }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/proxy/forced_proxy_guard_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```powershell
git add lib/services/network/proxy/forced_proxy_guard.dart test/services/network/proxy/forced_proxy_guard_test.dart
git commit -m "feat: add forced proxy guard"
```

Expected: commit succeeds.

## Task 3: Local Gateway Runtime State

**Files:**
- Modify: `lib/services/network/doh/network_settings_service.dart`
- Test: `test/services/network/proxy/forced_proxy_guard_test.dart`

- [ ] **Step 1: Add runtime expectations to guard tests**

Append this test to `test/services/network/proxy/forced_proxy_guard_test.dart`:

```dart
test('runtime state labels are stable', () {
  expect(ForcedProxyRuntimeStatus.disabled.name, 'disabled');
  expect(ForcedProxyRuntimeStatus.starting.name, 'starting');
  expect(ForcedProxyRuntimeStatus.ready.name, 'ready');
  expect(ForcedProxyRuntimeStatus.invalidConfig.name, 'invalidConfig');
  expect(ForcedProxyRuntimeStatus.gatewayFailed.name, 'gatewayFailed');
  expect(ForcedProxyRuntimeStatus.webViewFailed.name, 'webViewFailed');
});
```

Update the import:

```dart
import 'package:fluxdo/services/network/doh/network_settings_service.dart';
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/proxy/forced_proxy_guard_test.dart
```

Expected: FAIL because `ForcedProxyRuntimeStatus` does not exist.

- [ ] **Step 3: Add forced runtime status to NetworkSettingsService**

In `lib/services/network/doh/network_settings_service.dart`, add near the model classes:

```dart
enum ForcedProxyRuntimeStatus {
  disabled,
  starting,
  ready,
  invalidConfig,
  gatewayFailed,
  webViewFailed,
}
```

Add fields and getters to `NetworkSettingsService`:

```dart
final ValueNotifier<ForcedProxyRuntimeStatus> forcedProxyStatus =
    ValueNotifier(ForcedProxyRuntimeStatus.disabled);

bool get isForcedProxyEnabled => _proxyService.current.forcedEnabled;

bool get isForcedProxyReady =>
    _proxyService.current.isForcedValid &&
    _rustProxyService.isRunning &&
    current.proxyPort != null &&
    forcedProxyStatus.value == ForcedProxyRuntimeStatus.ready;

bool get isWebViewProxyReadyForForcedMode =>
    !isForcedProxyEnabled || _webViewProxySet;

void _setForcedProxyStatus(ForcedProxyRuntimeStatus status) {
  if (forcedProxyStatus.value == status) return;
  forcedProxyStatus.value = status;
  _touch();
}
```

Update `shouldRunLocalProxy`:

```dart
bool get shouldRunLocalProxy =>
    current.dohEnabled ||
    _proxyService.current.isValid ||
    _proxyService.current.forcedEnabled;
```

At the start of `_applyProxyState()`, after the initial loading frame:

```dart
final forcedValidation = _proxyService.validateForcedMode();
if (_proxyService.current.forcedEnabled) {
  _setForcedProxyStatus(
    forcedValidation == null
        ? ForcedProxyRuntimeStatus.starting
        : ForcedProxyRuntimeStatus.invalidConfig,
  );
  if (forcedValidation != null) {
    await _rustProxyService.stop();
    await _clearWebViewProxy();
    _setPendingStart(false);
    return;
  }
} else {
  _setForcedProxyStatus(ForcedProxyRuntimeStatus.disabled);
}
```

When calculating proxy start arguments, force pure upstream mode:

```dart
final forced = _proxyService.current.forcedEnabled;
final useGateway = !forced && current.dohEnabled && current.gatewayEnabled;
final enableDohForProxy = !forced && current.dohEnabled;
```

Pass these values into `_rustProxyService.start(...)`:

```dart
enableDoh: enableDohForProxy,
gatewayMode: useGateway,
dohServer: enableDohForProxy ? current.selectedServerUrl : null,
dohServerEch: enableDohForProxy ? current.echServerUrl : null,
serverIp: forced ? null : current.serverIp,
```

After failed start:

```dart
if (_proxyService.current.forcedEnabled) {
  _setForcedProxyStatus(ForcedProxyRuntimeStatus.gatewayFailed);
}
```

After `_applyWebViewProxy()`:

```dart
final webViewReady = await _applyWebViewProxy();
if (_proxyService.current.forcedEnabled) {
  _setForcedProxyStatus(
    webViewReady
        ? ForcedProxyRuntimeStatus.ready
        : ForcedProxyRuntimeStatus.webViewFailed,
  );
}
```

Change `_applyWebViewProxy()` and `_clearWebViewProxy()` signatures:

```dart
Future<bool> _applyWebViewProxy() async {
  if (!shouldRunLocalProxy) return !_proxyService.current.forcedEnabled;
  final port = _activeProxyPort;
  if (port == null) return false;
  ...
  _webViewProxySet = true;
  return true;
  ...
  return false;
}

Future<void> _clearWebViewProxy() async {
  if (!_webViewProxySet) return;
  ...
  _webViewProxySet = false;
}
```

- [ ] **Step 4: Disable local DNS overrides in forced mode**

At the start of `resolveHostForRequest(...)`, after `normalizedHost` is computed:

```dart
if (_proxyService.current.forcedEnabled) {
  return const ResolvedHostConfig.empty();
}
```

- [ ] **Step 5: Run focused tests**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/proxy/forced_proxy_guard_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```powershell
git add lib/services/network/doh/network_settings_service.dart test/services/network/proxy/forced_proxy_guard_test.dart
git commit -m "feat: track forced proxy gateway state"
```

Expected: commit succeeds.

## Task 4: Adapter Fail-Closed Behavior

**Files:**
- Modify: `lib/services/network/adapters/network_http_adapter.dart`
- Modify: `lib/services/network/adapters/rhttp_adapter.dart`
- Modify: `lib/services/network/adapters/platform_adapter.dart`
- Create: `test/services/network/adapters/rhttp_adapter_forced_proxy_test.dart`
- Create: `test/services/network/adapters/network_http_adapter_forced_proxy_test.dart`

- [ ] **Step 1: Add adapter helper tests**

Create `test/services/network/adapters/rhttp_adapter_forced_proxy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/adapters/rhttp_adapter.dart';
import 'package:fluxdo/services/network/proxy/proxy_settings_service.dart';

void main() {
  group('RhttpAdapter forced proxy URI', () {
    test('uses local gateway in forced mode', () {
      const settings = ProxySettings(
        enabled: true,
        forcedEnabled: true,
        protocol: UpstreamProxyProtocol.socks5,
        host: 'proxy.example.com',
        port: 1080,
      );

      expect(
        RhttpAdapter.resolveForcedProxyUri(settings, 8123),
        'http://127.0.0.1:8123',
      );
    });

    test('returns null when gateway port is missing', () {
      const settings = ProxySettings(
        enabled: true,
        forcedEnabled: true,
        protocol: UpstreamProxyProtocol.http,
        host: 'proxy.example.com',
        port: 8080,
      );

      expect(RhttpAdapter.resolveForcedProxyUri(settings, null), isNull);
    });
  });
}
```

Create `test/services/network/adapters/network_http_adapter_forced_proxy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/adapters/network_http_adapter.dart';
import 'package:fluxdo/services/network/proxy/proxy_settings_service.dart';

void main() {
  group('NetworkHttpAdapter forced proxy decision', () {
    test('requires local gateway for forced mode', () {
      const settings = ProxySettings(
        enabled: true,
        forcedEnabled: true,
        protocol: UpstreamProxyProtocol.http,
        host: 'proxy.example.com',
        port: 8080,
      );

      expect(NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, null, false), isFalse);
      expect(NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, 9000, false), isTrue);
    });

    test('keeps existing local gateway behavior outside forced mode', () {
      const settings = ProxySettings(
        enabled: true,
        protocol: UpstreamProxyProtocol.http,
        host: 'proxy.example.com',
        port: 8080,
      );

      expect(NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, null, true), isFalse);
      expect(NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, 9000, true), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/adapters/rhttp_adapter_forced_proxy_test.dart test/services/network/adapters/network_http_adapter_forced_proxy_test.dart
```

Expected: FAIL because helper methods do not exist.

- [ ] **Step 3: Implement NetworkHttpAdapter guard and helper**

In `lib/services/network/adapters/network_http_adapter.dart`, import guard:

```dart
import '../proxy/forced_proxy_guard.dart';
```

Add at start of `fetch(...)` after `_closed` check:

```dart
ForcedProxyGuard.ensureReady(
  forcedEnabled: _proxySettings.current.forcedEnabled,
  forcedConfigValid: _proxySettings.current.isForcedValid,
  localGatewayReady: _settings.isForcedProxyReady,
  webViewRequired: false,
  webViewProxyReady: _settings.isWebViewProxyReadyForForcedMode,
);
```

Add visible helper and update `_shouldUseLocalGateway`:

```dart
@visibleForTesting
static bool shouldUseLocalGatewayFor(
  ProxySettings proxySettings,
  int? proxyPort,
  bool dohEnabled,
) {
  if (proxyPort == null) return false;
  if (proxySettings.forcedEnabled) return proxySettings.isForcedValid;
  return dohEnabled || proxySettings.isValid;
}

bool get _shouldUseLocalGateway {
  final settings = _settings.current;
  return shouldUseLocalGatewayFor(
    _proxySettings.current,
    settings.proxyPort,
    settings.dohEnabled,
  );
}
```

- [ ] **Step 4: Implement RhttpAdapter forced local gateway**

In `lib/services/network/adapters/rhttp_adapter.dart`, import guard:

```dart
import '../proxy/forced_proxy_guard.dart';
```

Add before preparing client in `fetch(...)`:

```dart
ForcedProxyGuard.ensureReady(
  forcedEnabled: _proxySettings.current.forcedEnabled,
  forcedConfigValid: _proxySettings.current.isForcedValid,
  localGatewayReady: _networkSettings.isForcedProxyReady,
  webViewRequired: false,
  webViewProxyReady: _networkSettings.isWebViewProxyReadyForForcedMode,
);
```

Add helper:

```dart
@visibleForTesting
static String? resolveForcedProxyUri(ProxySettings settings, int? localPort) {
  if (!settings.forcedEnabled) return null;
  if (!settings.isForcedValid || localPort == null) return null;
  return 'http://127.0.0.1:$localPort';
}
```

Update `_buildProxySettings(...)`:

```dart
final forcedUri = resolveForcedProxyUri(ps, ns.proxyPort);
if (forcedUri != null) {
  return rhttp.ProxySettings.proxy(forcedUri);
}
if (ps.forcedEnabled) {
  return const rhttp.ProxySettings.noProxy();
}
```

Place this before the existing `if (!ps.isValid)` line.

- [ ] **Step 5: Update platform adapter type resolution**

In `lib/services/network/adapters/platform_adapter.dart`, update `_resolveAdapterType(...)` before the rhttp branch:

```dart
if (proxySettings.current.forcedEnabled) {
  return AdapterType.network;
}
```

This ensures the default Dio path prefers the local `NetworkHttpAdapter` gateway in forced mode instead of a direct native/rhttp path.

- [ ] **Step 6: Run adapter tests**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/adapters/rhttp_adapter_forced_proxy_test.dart test/services/network/adapters/network_http_adapter_forced_proxy_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```powershell
git add lib/services/network/adapters/network_http_adapter.dart lib/services/network/adapters/rhttp_adapter.dart lib/services/network/adapters/platform_adapter.dart test/services/network/adapters/rhttp_adapter_forced_proxy_test.dart test/services/network/adapters/network_http_adapter_forced_proxy_test.dart
git commit -m "feat: fail closed network adapters in forced proxy mode"
```

Expected: commit succeeds.

## Task 5: WebView Forced Proxy Guard

**Files:**
- Modify: `lib/services/network/adapters/webview_http_adapter.dart`
- Modify: `lib/pages/webview_login_page.dart`
- Test: `test/services/network/adapters/webview_http_adapter_test.dart`

- [ ] **Step 1: Add WebView adapter guard test**

Append to `test/services/network/adapters/webview_http_adapter_test.dart`:

```dart
group('WebViewHttpAdapter forced proxy guard', () {
  test('throws before fetch when forced WebView proxy is not ready', () {
    expect(
      () => WebViewHttpAdapter.ensureForcedProxyReadyForTesting(
        forcedEnabled: true,
        forcedConfigValid: true,
        localGatewayReady: true,
        webViewProxyReady: false,
      ),
      throwsA(isA<Object>().having(
        (e) => e.toString(),
        'message',
        contains('WebView 无法使用强制代理'),
      )),
    );
  });

  test('allows fetch path when forced WebView proxy is ready', () {
    expect(
      () => WebViewHttpAdapter.ensureForcedProxyReadyForTesting(
        forcedEnabled: true,
        forcedConfigValid: true,
        localGatewayReady: true,
        webViewProxyReady: true,
      ),
      returnsNormally,
    );
  });
});
```

- [ ] **Step 2: Run test and verify failure**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/adapters/webview_http_adapter_test.dart
```

Expected: FAIL because `ensureForcedProxyReadyForTesting` does not exist.

- [ ] **Step 3: Implement WebViewHttpAdapter guard**

In `lib/services/network/adapters/webview_http_adapter.dart`, import services:

```dart
import '../doh/network_settings_service.dart';
import '../proxy/proxy_settings_service.dart';
import '../proxy/forced_proxy_guard.dart';
```

Add helper inside `WebViewHttpAdapter`:

```dart
@visibleForTesting
static void ensureForcedProxyReadyForTesting({
  required bool forcedEnabled,
  required bool forcedConfigValid,
  required bool localGatewayReady,
  required bool webViewProxyReady,
}) {
  ForcedProxyGuard.ensureReady(
    forcedEnabled: forcedEnabled,
    forcedConfigValid: forcedConfigValid,
    localGatewayReady: localGatewayReady,
    webViewRequired: true,
    webViewProxyReady: webViewProxyReady,
  );
}

void _ensureForcedProxyReady() {
  final proxy = ProxySettingsService.instance.current;
  final network = NetworkSettingsService.instance;
  ensureForcedProxyReadyForTesting(
    forcedEnabled: proxy.forcedEnabled,
    forcedConfigValid: proxy.isForcedValid,
    localGatewayReady: network.isForcedProxyReady,
    webViewProxyReady: network.isWebViewProxyReadyForForcedMode,
  );
}
```

Call `_ensureForcedProxyReady();` at the top of `fetch(...)`, before `initialize()`.

- [ ] **Step 4: Block WebView login page when forced proxy is not ready**

In `lib/pages/webview_login_page.dart`, import guard and network settings:

```dart
import '../services/network/doh/network_settings_service.dart';
import '../services/network/proxy/proxy_settings_service.dart';
import '../services/network/proxy/forced_proxy_guard.dart';
```

Add method in `_WebViewLoginPageState`:

```dart
String? _forcedProxyBlockReason() {
  final proxy = ProxySettingsService.instance.current;
  final network = NetworkSettingsService.instance;
  try {
    ForcedProxyGuard.ensureReady(
      forcedEnabled: proxy.forcedEnabled,
      forcedConfigValid: proxy.isForcedValid,
      localGatewayReady: network.isForcedProxyReady,
      webViewRequired: true,
      webViewProxyReady: network.isWebViewProxyReadyForForcedMode,
    );
    return null;
  } on ForcedProxyException catch (e) {
    return e.message;
  }
}
```

At the start of `build(...)`, before returning `Scaffold`, add:

```dart
final forcedProxyBlockReason = _forcedProxyBlockReason();
if (forcedProxyBlockReason != null) {
  return Scaffold(
    appBar: AppBar(title: Text(context.l10n.webviewLogin_title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.vpn_lock_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              forcedProxyBlockReason,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.forcedProxy_webViewBlockedHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] **Step 5: Run tests**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/adapters/webview_http_adapter_test.dart
```

Expected: PASS after l10n key is added in Task 8. If this fails only because `forcedProxy_webViewBlockedHint` is missing, keep the code and complete Task 8 before final full test.

- [ ] **Step 6: Commit after Task 8 l10n is available**

Run after Task 8:

```powershell
git add lib/services/network/adapters/webview_http_adapter.dart lib/pages/webview_login_page.dart test/services/network/adapters/webview_http_adapter_test.dart
git commit -m "feat: block webview direct access in forced proxy mode"
```

Expected: commit succeeds.

## Task 6: Close Direct Network Bypasses

**Files:**
- Modify: `lib/services/network/cookie/csrf_token_service.dart`
- Modify: `lib/services/dio_http_client.dart`
- Modify: `lib/services/discourse_cache_manager.dart`
- Modify: `lib/services/update_service.dart`
- Modify: `lib/services/apk_download_service.dart`
- Modify: `lib/services/sticker_market_service.dart`
- Test: `test/services/network/proxy/forced_proxy_guard_test.dart`

- [ ] **Step 1: Add audit command to the task notes**

Run:

```powershell
rg "Dio\\(|HttpClient\\(|http\\.Client\\(|Image\\.network\\(|CachedNetworkImage\\(|CachedNetworkImageProvider\\(" lib packages -n
```

Expected: Remaining direct network creation sites are known and either use `DiscourseDio.create`, `DioHttpClient`, the AI `DioBackedHttpClient`, or are explicitly blocked in forced mode.

- [ ] **Step 2: Replace CSRF raw Dio with DiscourseDio**

In `lib/services/network/cookie/csrf_token_service.dart`, replace the raw `Dio(...)` construction with:

```dart
final dio = DiscourseDio.create(
  baseUrl: AppConstants.baseUrl,
  connectTimeout: const Duration(seconds: 30),
  receiveTimeout: const Duration(seconds: 30),
  enableRetry: true,
  enableCfChallenge: true,
  defaultHeaders: {
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'X-Requested-With': 'XMLHttpRequest',
  },
);
```

Remove the manual `dio.interceptors.add(AppCookieManager(cookieJarService.cookieJar));` line from `_getMainSiteDio()`. `DiscourseDio.create(...)` already installs `AppCookieManager` after `CookieJarService` is initialized, and keeping both would duplicate cookie handling.

- [ ] **Step 3: Make external image cache use DioHttpClient**

In `lib/services/discourse_cache_manager.dart`, update `ExternalImageCacheManager._()`:

```dart
ExternalImageCacheManager._() : super(
  Config(
    key,
    stalePeriod: const Duration(days: 30),
    maxNrOfCacheObjects: 200,
    repo: JsonCacheInfoRepository(databaseName: key),
    fileService: HttpFileService(httpClient: DioHttpClient()),
  ),
);
```

- [ ] **Step 4: Update UpdateService default Dio**

In `lib/services/update_service.dart`, import `services/network/discourse_dio.dart` and change constructor:

```dart
UpdateService({Dio? dio, SharedPreferences? prefs})
    : _dio = dio ?? DiscourseDio.create(
        baseUrl: '',
        defaultHeaders: {
          'User-Agent': 'FluxDO-App',
          'Accept': 'application/vnd.github.v3+json',
        },
        maxConcurrent: null,
        enableCookies: false,
      ),
      _prefs = prefs;
```

- [ ] **Step 5: Update StickerMarketService Dio**

In `lib/services/sticker_market_service.dart`, import `services/network/discourse_dio.dart` and replace constructor body:

```dart
StickerMarketService(this._prefs) {
  _dio = DiscourseDio.create(
    baseUrl: '',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    maxConcurrent: null,
    enableCookies: false,
  );
}
```

- [ ] **Step 6: Block unproxyable OTA download in forced mode**

In `lib/services/apk_download_service.dart`, import proxy service:

```dart
import 'network/proxy/proxy_settings_service.dart';
```

Update constructor:

```dart
ApkDownloadService({Dio? dio})
    : _dio = dio ?? DiscourseDio.create(
        baseUrl: '',
        maxConcurrent: null,
        enableCookies: false,
      );
```

Add at the start of `downloadAndInstall(...)`:

```dart
if (ProxySettingsService.instance.current.forcedEnabled) {
  yield ApkDownloadProgress(
    status: ApkDownloadStatus.error,
    error: S.current.forcedProxy_otaBlocked,
  );
  return;
}
```

Keep `_fetchSha256Checksum` using `_dio`, so checksum requests are proxied.

- [ ] **Step 7: Run audit again**

Run:

```powershell
rg "Dio\\(|HttpClient\\(|http\\.Client\\(|Image\\.network\\(" lib packages -n
```

Expected: Any remaining result is one of:
- `DiscourseDio.create` internals.
- `DioHttpClient` internals.
- AI package fallback that is not used by app providers when bridged client is injected.
- Third-party plugin code under `packages/flutter_inappwebview_linux`.
- UI `Image.network` instances scheduled for replacement in Task 7.

- [ ] **Step 8: Commit**

Run after Task 8 l10n is available:

```powershell
git add lib/services/network/cookie/csrf_token_service.dart lib/services/dio_http_client.dart lib/services/discourse_cache_manager.dart lib/services/update_service.dart lib/services/apk_download_service.dart lib/services/sticker_market_service.dart
git commit -m "feat: route direct services through forced proxy path"
```

Expected: commit succeeds.

## Task 7: Image and AI Request Coverage

**Files:**
- Modify: `lib/widgets/content/discourse_html_content/builders/chat_transcript_builder.dart`
- Modify: `lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart`
- Modify: `packages/ai_model_manager/lib/providers/ai_chat_providers.dart`
- Test: `packages/ai_model_manager/test/services/dio_http_bridge_test.dart`

- [ ] **Step 1: Replace direct Image.network in app UI**

Run:

```powershell
rg "Image\\.network\\(" lib -n
```

Expected before changes:

```text
lib/widgets/content/discourse_html_content/builders/chat_transcript_builder.dart
lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart
```

In both files, replace direct `Image.network(url, ...)` with an `Image` that uses the existing proxied cache providers:

```dart
Image(
  image: discourseImageProvider(url),
  fit: BoxFit.cover,
  errorBuilder: (context, error, stackTrace) {
    return const Icon(Icons.broken_image_outlined);
  },
)
```

If the image is external to Discourse, use:

```dart
Image(
  image: CachedNetworkImageProvider(
    url,
    cacheManager: ExternalImageCacheManager(),
  ),
  fit: BoxFit.cover,
  errorBuilder: (context, error, stackTrace) {
    return const Icon(Icons.broken_image_outlined);
  },
)
```

Use these imports when replacing direct image loading:

```dart
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../services/discourse_cache_manager.dart';
```

For `lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart`, adjust the relative import to:

```dart
import '../../../services/discourse_cache_manager.dart';
```

- [ ] **Step 2: Ensure AI providers do not fall back to raw http.Client in app path**

In `packages/ai_model_manager/lib/providers/ai_chat_providers.dart`, locate `_requestClient = http.Client();` and replace the app-facing provider path with:

```dart
final adapterFactory = ref.watch(aiDioAdapterFactoryProvider);
_requestClient = DioBackedHttpClient(adapterFactory());
```

Keep direct `http.Client()` only for package-level tests or standalone package usage where no adapter factory is supplied.

- [ ] **Step 3: Add AI bridge regression test**

Append to `packages/ai_model_manager/test/services/dio_http_bridge_test.dart`:

```dart
test('DioBackedHttpClient is reusable for forced proxy adapter injection', () async {
  final adapter = _FakeAdapter(
    statusCode: 200,
    body: '{"ok":true}',
    headers: {
      'content-type': ['application/json'],
    },
  );
  final client = DioBackedHttpClient(adapter);

  final response = await client.get(Uri.parse('https://api.example.com/test'));

  expect(response.statusCode, 200);
  expect(response.body, '{"ok":true}');
});
```

Use the existing `_RecordingAdapter` class in that test file:

```dart
test('DioBackedHttpClient is reusable for forced proxy adapter injection', () async {
  final adapter = _RecordingAdapter((_, __) async {
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  });
  final client = DioBackedHttpClient(adapter);

  final response = await client.get(Uri.parse('https://api.example.com/test'));

  expect(response.statusCode, 200);
  expect(response.body, '{"ok":true}');
});
```

- [ ] **Step 4: Run image audit**

Run:

```powershell
rg "Image\\.network\\(" lib -n
```

Expected: no results in `lib`.

- [ ] **Step 5: Run package bridge tests**

Run:

```powershell
dart run tool/flutterw.dart test packages/ai_model_manager/test/services/dio_http_bridge_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```powershell
git add lib/widgets/content/discourse_html_content/builders/chat_transcript_builder.dart lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart packages/ai_model_manager/lib/providers/ai_chat_providers.dart packages/ai_model_manager/test/services/dio_http_bridge_test.dart
git commit -m "feat: close image and ai direct network paths"
```

Expected: commit succeeds.

## Task 8: Settings UI and Localization

**Files:**
- Modify: `lib/pages/network_settings_page/widgets/http_proxy_card.dart`
- Modify: `lib/pages/network_settings_page/widgets/doh_settings_card.dart`
- Modify: `lib/l10n/modules/network/network_zh.arb`
- Modify: `lib/l10n/modules/network/network_en.arb`
- Modify: `lib/l10n/modules/network/network_zh_HK.arb`
- Modify: `lib/l10n/modules/network/network_zh_TW.arb`
- Generated: `lib/l10n/s.dart` dependencies through `tool/gen_l10n.dart`

- [ ] **Step 1: Add localization keys**

Add these keys to each `network_*.arb` file with translated values.

For `network_zh.arb`:

```json
"forcedProxy_title": "强制代理",
"forcedProxy_subtitle": "所有 FluxDO 流量必须走此代理",
"forcedProxy_enabledDesc": "已启用，直连请求将被阻止",
"forcedProxy_disabledDesc": "关闭时使用普通应用网络策略",
"forcedProxy_gatewayRunning": "本地网关运行中",
"forcedProxy_gatewayStarting": "本地网关启动中",
"forcedProxy_gatewayFailed": "本地网关启动失败",
"forcedProxy_invalidConfig": "代理配置无效",
"forcedProxy_webViewFailed": "WebView 代理接入失败",
"forcedProxy_webViewBlockedHint": "请检查代理配置或关闭强制代理后重试。",
"forcedProxy_otaBlocked": "强制代理模式下暂不支持系统 OTA 下载，已阻止直连。",
"forcedProxy_localGateway": "本地网关 {port}",
"@forcedProxy_localGateway": {
  "placeholders": {
    "port": {
      "type": "int"
    }
  }
},
"forcedProxy_dohPaused": "强制代理模式下暂停本地 DOH 解析，以避免 DNS 泄漏"
```

For `network_en.arb`:

```json
"forcedProxy_title": "Forced proxy",
"forcedProxy_subtitle": "All FluxDO traffic must use this proxy",
"forcedProxy_enabledDesc": "Enabled. Direct requests are blocked.",
"forcedProxy_disabledDesc": "Disabled. The normal app network policy is used.",
"forcedProxy_gatewayRunning": "Local gateway running",
"forcedProxy_gatewayStarting": "Local gateway starting",
"forcedProxy_gatewayFailed": "Local gateway failed to start",
"forcedProxy_invalidConfig": "Invalid proxy configuration",
"forcedProxy_webViewFailed": "WebView proxy setup failed",
"forcedProxy_webViewBlockedHint": "Check the proxy configuration or disable forced proxy and try again.",
"forcedProxy_otaBlocked": "System OTA download is not supported in forced proxy mode. Direct download was blocked.",
"forcedProxy_localGateway": "Local gateway {port}",
"@forcedProxy_localGateway": {
  "placeholders": {
    "port": {
      "type": "int"
    }
  }
},
"forcedProxy_dohPaused": "Local DOH resolution is paused in forced proxy mode to avoid DNS leaks"
```

For `network_zh_HK.arb`, use:

```json
"forcedProxy_title": "強制代理",
"forcedProxy_subtitle": "所有 FluxDO 流量必須走此代理",
"forcedProxy_enabledDesc": "已啓用，直連請求將被阻止",
"forcedProxy_disabledDesc": "關閉時使用普通應用網絡策略",
"forcedProxy_gatewayRunning": "本地網關運行中",
"forcedProxy_gatewayStarting": "本地網關啓動中",
"forcedProxy_gatewayFailed": "本地網關啓動失敗",
"forcedProxy_invalidConfig": "代理配置無效",
"forcedProxy_webViewFailed": "WebView 代理接入失敗",
"forcedProxy_webViewBlockedHint": "請檢查代理配置或關閉強制代理後重試。",
"forcedProxy_otaBlocked": "強制代理模式下暫不支援系統 OTA 下載，已阻止直連。",
"forcedProxy_localGateway": "本地網關 {port}",
"@forcedProxy_localGateway": {
  "placeholders": {
    "port": {
      "type": "int"
    }
  }
},
"forcedProxy_dohPaused": "強制代理模式下暫停本地 DOH 解析，以避免 DNS 泄漏"
```

For `network_zh_TW.arb`, use:

```json
"forcedProxy_title": "強制代理",
"forcedProxy_subtitle": "所有 FluxDO 流量必須走此代理",
"forcedProxy_enabledDesc": "已啟用，直連請求將被阻止",
"forcedProxy_disabledDesc": "關閉時使用普通應用網路策略",
"forcedProxy_gatewayRunning": "本地閘道執行中",
"forcedProxy_gatewayStarting": "本地閘道啟動中",
"forcedProxy_gatewayFailed": "本地閘道啟動失敗",
"forcedProxy_invalidConfig": "代理設定無效",
"forcedProxy_webViewFailed": "WebView 代理接入失敗",
"forcedProxy_webViewBlockedHint": "請檢查代理設定或關閉強制代理後重試。",
"forcedProxy_otaBlocked": "強制代理模式下暫不支援系統 OTA 下載，已阻止直連。",
"forcedProxy_localGateway": "本地閘道 {port}",
"@forcedProxy_localGateway": {
  "placeholders": {
    "port": {
      "type": "int"
    }
  }
},
"forcedProxy_dohPaused": "強制代理模式下暫停本地 DOH 解析，以避免 DNS 洩漏"
```

- [ ] **Step 2: Extend HttpProxyCard UI**

In `lib/pages/network_settings_page/widgets/http_proxy_card.dart`, include `networkService.forcedProxyStatus` in the `AnimatedBuilder` merge list:

```dart
networkService.forcedProxyStatus,
```

Inside `_HttpProxyCardInner`, add parameters:

```dart
final bool forcedEnabled;
final ForcedProxyRuntimeStatus forcedStatus;
final int? localGatewayPort;
```

Add a `SwitchListTile` after the server configuration tile:

```dart
SwitchListTile(
  title: Text(context.l10n.forcedProxy_title),
  subtitle: Text(
    forcedEnabled
        ? context.l10n.forcedProxy_enabledDesc
        : context.l10n.forcedProxy_disabledDesc,
  ),
  secondary: Icon(
    forcedEnabled ? Icons.vpn_lock_rounded : Icons.lock_open_rounded,
    color: forcedEnabled ? theme.colorScheme.error : null,
  ),
  value: forcedEnabled,
  onChanged: (value) async {
    if (value && !proxySettings.hasServer) {
      final saved = await _showProxyConfigDialog(context, proxySettings);
      if (!saved) return;
    }
    await ProxySettingsService.instance.setForcedEnabled(value);
  },
)
```

Add a status row when `forcedEnabled` is true:

```dart
if (forcedEnabled)
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(
      children: [
        Icon(Icons.route_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _forcedStatusText(context, forcedStatus, localGatewayPort),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  ),
```

Add helper:

```dart
String _forcedStatusText(
  BuildContext context,
  ForcedProxyRuntimeStatus status,
  int? port,
) {
  switch (status) {
    case ForcedProxyRuntimeStatus.disabled:
      return context.l10n.forcedProxy_disabledDesc;
    case ForcedProxyRuntimeStatus.starting:
      return context.l10n.forcedProxy_gatewayStarting;
    case ForcedProxyRuntimeStatus.ready:
      return port == null
          ? context.l10n.forcedProxy_gatewayRunning
          : context.l10n.forcedProxy_localGateway(port);
    case ForcedProxyRuntimeStatus.invalidConfig:
      return context.l10n.forcedProxy_invalidConfig;
    case ForcedProxyRuntimeStatus.gatewayFailed:
      return context.l10n.forcedProxy_gatewayFailed;
    case ForcedProxyRuntimeStatus.webViewFailed:
      return context.l10n.forcedProxy_webViewFailed;
  }
}
```

- [ ] **Step 3: Add DOH forced mode hint**

In `lib/pages/network_settings_page/widgets/doh_settings_card.dart`, import `ProxySettingsService` and add this below the DOH switch when forced proxy is enabled:

```dart
if (ProxySettingsService.instance.current.forcedEnabled)
  Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            context.l10n.forcedProxy_dohPaused,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  ),
```

- [ ] **Step 4: Generate localization**

Run:

```powershell
dart run tool/gen_l10n.dart
```

Expected: generated localization succeeds with no missing-key errors.

- [ ] **Step 5: Run analyzer for UI compile errors**

Run:

```powershell
dart run tool/flutterw.dart analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no errors related to new l10n keys or missing imports.

- [ ] **Step 6: Commit**

Run:

```powershell
git add lib/pages/network_settings_page/widgets/http_proxy_card.dart lib/pages/network_settings_page/widgets/doh_settings_card.dart lib/l10n/modules/network/network_zh.arb lib/l10n/modules/network/network_en.arb lib/l10n/modules/network/network_zh_HK.arb lib/l10n/modules/network/network_zh_TW.arb
git commit -m "feat: add forced proxy settings UI"
```

Expected: commit succeeds.

## Task 9: Integration Verification and Final Audit

**Files:**
- Read: all modified files
- Modify: files reported by analyzer or tests during this task

- [ ] **Step 1: Run targeted forced proxy tests**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/proxy/forced_proxy_guard_test.dart test/services/network/proxy/proxy_settings_service_test.dart test/services/network/adapters/rhttp_adapter_forced_proxy_test.dart test/services/network/adapters/network_http_adapter_forced_proxy_test.dart test/services/network/adapters/webview_http_adapter_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run existing related tests**

Run:

```powershell
dart run tool/flutterw.dart test test/services/network/adapters/webview_http_adapter_test.dart test/services/network/cookie/app_cookie_manager_test.dart packages/ai_model_manager/test/services/dio_http_bridge_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run:

```powershell
dart run tool/flutterw.dart test
```

Expected: PASS.

- [ ] **Step 4: Run static analysis**

Run:

```powershell
dart run tool/flutterw.dart analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no analyzer errors.

- [ ] **Step 5: Run direct-network audit**

Run:

```powershell
rg "Dio\\(|HttpClient\\(|http\\.Client\\(|Image\\.network\\(" lib packages -n
```

Expected: every remaining match is reviewed. Add a short note to the final implementation summary for each intentionally remaining match, such as third-party plugin code or package fallback not used by the FluxDO app path.

- [ ] **Step 6: Android manual verification**

Run on an Android emulator or device:

```powershell
dart run tool/flutterw.dart run -d android --dart-define=cronetHttpNoPlay=true
```

Manual checks:
- Configure a working HTTP proxy with username/password, enable forced proxy, open home timeline, topic detail, login WebView, notifications, images, and AI chat.
- Configure an invalid proxy, keep forced proxy enabled, confirm home timeline, login WebView, images, notifications, update check, and AI requests fail without loading direct content.
- Disable forced proxy and confirm normal networking works again.

- [ ] **Step 7: Commit verification fixes**

If any fixes were required:

```powershell
git add lib/services/network/proxy lib/services/network/doh lib/services/network/adapters lib/services/network/cookie lib/services/dio_http_client.dart lib/services/discourse_cache_manager.dart lib/services/update_service.dart lib/services/apk_download_service.dart lib/services/sticker_market_service.dart lib/pages/webview_login_page.dart lib/pages/network_settings_page/widgets lib/widgets/content/discourse_html_content/builders/chat_transcript_builder.dart lib/pages/topic_detail_page/widgets/ai_chat_message_item.dart packages/ai_model_manager/lib/providers/ai_chat_providers.dart test packages/ai_model_manager/test/services/dio_http_bridge_test.dart
git commit -m "fix: complete forced proxy verification"
```

Expected: no uncommitted source changes except intentionally untracked local build artifacts.
