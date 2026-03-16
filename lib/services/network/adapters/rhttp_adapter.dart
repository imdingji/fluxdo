import 'package:dio/dio.dart';
import 'package:dio_compatibility_layer/dio_compatibility_layer.dart';
import 'package:flutter/foundation.dart';
import 'package:rhttp/rhttp.dart' as rhttp;

import '../doh/network_settings_service.dart';
import '../proxy/proxy_settings_service.dart';
import '../rhttp/rhttp_settings_service.dart';

/// 基于 rhttp (Rust reqwest) 的 Dio 适配器
///
/// 支持 HTTP/2 多路复用、DOH DNS 解析（通过 DnsSettings.dynamic）、
/// 原生 HTTP/SOCKS5 代理、以及通过本地 Rust 代理中转 SS 连接。
class RhttpAdapter implements HttpClientAdapter {
  RhttpAdapter(this._networkSettings, this._proxySettings);

  final NetworkSettingsService _networkSettings;
  final ProxySettingsService _proxySettings;

  ConversionLayerAdapter? _delegate;
  rhttp.RhttpCompatibleClient? _client;
  int _settingsVersion = -1;
  int _proxyVersion = -1;
  int _rhttpVersion = -1;
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

  ConversionLayerAdapter _ensureDelegate() {
    final settingsVersion = _networkSettings.version;
    final proxyVersion = _proxySettings.version;
    final rhttpVersion = RhttpSettingsService.instance.version;

    final shouldRebuild = _delegate == null ||
        _settingsVersion != settingsVersion ||
        _proxyVersion != proxyVersion ||
        _rhttpVersion != rhttpVersion;

    if (!shouldRebuild) {
      return _delegate!;
    }

    _client?.close();
    _client = _createClient();
    _delegate = ConversionLayerAdapter(_client!);

    _settingsVersion = settingsVersion;
    _proxyVersion = proxyVersion;
    _rhttpVersion = rhttpVersion;
    debugPrint('[DIO] RhttpAdapter 重建完成');
    return _delegate!;
  }

  rhttp.RhttpCompatibleClient _createClient() {
    final ns = _networkSettings.current;
    final ps = _proxySettings.current;
    final resolver = _networkSettings.resolver;

    // ECH 配置（从 NetworkSettingsService 缓存获取）
    final echConfig = _networkSettings.echConfigCache;

    return rhttp.RhttpCompatibleClient.createSync(
      settings: rhttp.ClientSettings(
        httpVersionPref: rhttp.HttpVersionPref.http2,

        // DNS：DOH 启用时用 DohResolver，否则系统 DNS（null = 系统默认）
        dnsSettings: ns.dohEnabled
            ? rhttp.DnsSettings.dynamic(
                resolver: (host) async {
                  final addrs = await resolver.resolveAll(host);
                  return addrs.map((a) => a.address).toList();
                },
              )
            : null,

        // TLS：ECH 配置可用时启用 ECH
        tlsSettings: echConfig != null
            ? rhttp.TlsSettings(echConfigList: echConfig)
            : null,

        // 代理配置
        proxySettings: _buildProxySettings(ns, ps),

        // Cookie/重定向交给 Dio 拦截器
        cookieSettings: const rhttp.CookieSettings(storeCookies: false),
        redirectSettings: const rhttp.RedirectSettings.none(),

        timeoutSettings: const rhttp.TimeoutSettings(
          connectTimeout: Duration(seconds: 30),
          timeout: Duration(seconds: 30),
          keepAliveTimeout: Duration(seconds: 60),
        ),
      ),
    );
  }

  rhttp.ProxySettings _buildProxySettings(
    NetworkSettings ns,
    ProxySettings ps,
  ) {
    if (!ps.isValid) return const rhttp.ProxySettings.noProxy();

    if (ps.isShadowsocks) {
      // SS：经本地 Rust 代理（tunnel 模式）
      final port = ns.proxyPort;
      if (port == null) return const rhttp.ProxySettings.noProxy();
      return rhttp.ProxySettings.proxy('http://127.0.0.1:$port');
    }

    // HTTP/SOCKS5：reqwest 原生支持
    final scheme =
        ps.protocol == UpstreamProxyProtocol.socks5 ? 'socks5' : 'http';
    if (ps.username != null && ps.username!.isNotEmpty) {
      return rhttp.ProxySettings.proxy(
        '$scheme://${ps.username}:${ps.password ?? ""}@${ps.host}:${ps.port}',
      );
    }
    return rhttp.ProxySettings.proxy('$scheme://${ps.host}:${ps.port}');
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    _client?.close();
    _client = null;
    _delegate = null;
  }
}
