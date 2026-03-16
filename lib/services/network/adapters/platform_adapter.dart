import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:native_dio_adapter/native_dio_adapter.dart';

import '../doh/network_settings_service.dart';
import '../proxy/proxy_settings_service.dart';
import '../rhttp/rhttp_settings_service.dart';
import 'cronet_fallback_service.dart';
import 'network_http_adapter.dart';
import 'rhttp_adapter.dart';
import 'webview_http_adapter.dart';

/// 当前使用的适配器类型
enum AdapterType {
  webview, // WebView 适配器（Windows）
  native, // Native 适配器（Cronet/Cupertino）
  network, // Network 适配器（通过代理）
  rhttp, // rhttp 引擎（Rust reqwest）
}

/// 全局变量：记录当前使用的适配器类型
AdapterType? _currentAdapterType;

/// 获取当前使用的适配器类型
AdapterType? getCurrentAdapterType() => _currentAdapterType;

/// 获取适配器类型的显示名称
String getAdapterDisplayName(AdapterType type) {
  switch (type) {
    case AdapterType.webview:
      return 'WebView 适配器';
    case AdapterType.native:
      return Platform.isAndroid ? 'Cronet 适配器' : 'Cupertino 适配器';
    case AdapterType.network:
      return 'Network 适配器';
    case AdapterType.rhttp:
      return 'rhttp 引擎';
  }
}

/// 配置平台适配器
void configurePlatformAdapter(Dio dio) {
  final settings = NetworkSettingsService.instance;
  final proxySettings = ProxySettingsService.instance;
  final fallbackService = CronetFallbackService.instance;
  final rhttpSettings = RhttpSettingsService.instance;

  if (Platform.isWindows) {
    // Windows: 始终使用 WebView 适配器
    _configureWebViewAdapter(dio);
    _currentAdapterType = AdapterType.webview;
  } else {
    // Android / iOS / macOS / Linux: 动态适配器，请求时自动切换
    dio.httpClientAdapter = _DynamicAdapter(
      settings,
      proxySettings,
      fallbackService,
      rhttpSettings,
    );
    _currentAdapterType = _resolveAdapterType(
      settings,
      proxySettings,
      fallbackService,
      rhttpSettings,
    );
  }
}

/// 配置 WebView 适配器
void _configureWebViewAdapter(Dio dio) {
  final adapter = WebViewHttpAdapter();
  dio.httpClientAdapter = adapter;
  adapter.initialize().then((_) {
    debugPrint('[DIO] Using WebViewHttpAdapter on Windows');
  }).catchError((e) {
    debugPrint('[DIO] WebViewHttpAdapter init failed: $e');
  });
}

AdapterType _resolveAdapterType(
  NetworkSettingsService settings,
  ProxySettingsService proxySettings,
  CronetFallbackService fallbackService,
  RhttpSettingsService rhttpSettings,
) {
  // rhttp 优先（满足条件时）
  if (rhttpSettings.shouldUseRhttp(settings.current, proxySettings.current)) {
    return AdapterType.rhttp;
  }
  // MITM 代理模式（ECH、Cronet 降级、rhttp 未启用时的 DOH/代理）
  if (settings.shouldRunLocalProxy || fallbackService.hasFallenBack) {
    return AdapterType.network;
  }
  return AdapterType.native;
}

/// 创建当前平台对应的 NativeAdapter
HttpClientAdapter _createNativeAdapter() {
  if (kDebugMode && (Platform.isMacOS || Platform.isIOS)) {
    // 调试模式下使用默认适配器（IOHttpClientAdapter），避免 NativeAdapter 热重启崩溃
    debugPrint('[DIO] Dynamic adapter -> IOHttpClientAdapter (debug mode)');
    return IOHttpClientAdapter();
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // Release 模式: URLSession 默认会自动管理 Cookie（httpShouldSetCookies=true），
    // 会与 AppCookieManager 拦截器冲突。禁用 URLSession 的 Cookie 自动管理。
    final config = URLSessionConfiguration.ephemeralSessionConfiguration();
    config.httpShouldSetCookies = false;
    return NativeAdapter(createCupertinoConfiguration: () => config);
  }
  return NativeAdapter();
}

/// 动态适配器：每次请求时根据设置 version 变化自动切换底层适配器
///
/// Android 上在 rhttp ↔ network ↔ native（Cronet）之间切换；
/// iOS/macOS/Linux 上在 rhttp ↔ network ↔ native（Cupertino/IO）之间切换。
class _DynamicAdapter implements HttpClientAdapter {
  _DynamicAdapter(
    this._settings,
    this._proxySettings,
    this._fallbackService,
    this._rhttpSettings,
  );

  final NetworkSettingsService _settings;
  final ProxySettingsService _proxySettings;
  final CronetFallbackService _fallbackService;
  final RhttpSettingsService _rhttpSettings;

  HttpClientAdapter? _delegate;
  AdapterType? _delegateType;
  int _settingsVersion = -1;
  int _proxyVersion = -1;
  int _rhttpVersion = -1;
  bool _hasFallenBack = false;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (_closed) {
      throw StateError("Can't establish connection after the adapter was closed.");
    }
    final delegate = _ensureDelegate();
    return delegate.fetch(options, requestStream, cancelFuture);
  }

  HttpClientAdapter _ensureDelegate() {
    final desiredType = _resolveAdapterType(
      _settings,
      _proxySettings,
      _fallbackService,
      _rhttpSettings,
    );
    final settingsVersion = _settings.version;
    final proxyVersion = _proxySettings.version;
    final rhttpVersion = _rhttpSettings.version;
    final hasFallenBack = _fallbackService.hasFallenBack;

    final shouldRebuild = _delegate == null ||
        _delegateType != desiredType ||
        _settingsVersion != settingsVersion ||
        _proxyVersion != proxyVersion ||
        _rhttpVersion != rhttpVersion ||
        _hasFallenBack != hasFallenBack;

    if (!shouldRebuild) {
      return _delegate!;
    }

    // 不要强杀旧 delegate，避免进行中的 Cronet 请求触发 native 崩溃。
    _delegate?.close(force: false);
    if (desiredType == AdapterType.rhttp) {
      _delegate = RhttpAdapter(_settings, _proxySettings);
      debugPrint('[DIO] Dynamic adapter -> RhttpAdapter');
    } else if (desiredType == AdapterType.network) {
      _delegate = NetworkHttpAdapter(_settings, _proxySettings);
      debugPrint('[DIO] Dynamic adapter -> NetworkHttpAdapter');
    } else {
      _delegate = _createNativeAdapter();
      debugPrint('[DIO] Dynamic adapter -> NativeAdapter');
    }

    _delegateType = desiredType;
    _settingsVersion = settingsVersion;
    _proxyVersion = proxyVersion;
    _rhttpVersion = rhttpVersion;
    _hasFallenBack = hasFallenBack;
    _currentAdapterType = desiredType;
    return _delegate!;
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    _delegate?.close(force: force);
  }
}
