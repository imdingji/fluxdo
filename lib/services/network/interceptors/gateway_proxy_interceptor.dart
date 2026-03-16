import 'package:dio/dio.dart';

import '../doh/network_settings_service.dart';

/// Gateway 反向代理拦截器
///
/// ECH 场景下，Rust 代理以 gateway 模式运行：
/// 接受明文 HTTP → 通过 TLS+ECH 转发到真实服务器。
/// 此拦截器将 HTTPS 请求改写为 HTTP 指向 localhost gateway，
/// 消除 MITM 双重 TLS 开销。
class GatewayProxyInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final service = NetworkSettingsService.instance;
    if (!service.isGatewayMode) {
      handler.next(options);
      return;
    }

    final port = service.current.proxyPort;
    if (port == null) {
      handler.next(options);
      return;
    }

    final uri = options.uri;
    if (uri.scheme != 'https') {
      handler.next(options);
      return;
    }

    // 保留原始 Host 头
    options.headers['Host'] ??= uri.host;

    // 改写为明文 HTTP 指向 localhost gateway
    final gatewayUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: uri.path,
      query: uri.query.isEmpty ? null : uri.query,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
    options.baseUrl = '';
    options.path = gatewayUri.toString();

    handler.next(options);
  }
}
