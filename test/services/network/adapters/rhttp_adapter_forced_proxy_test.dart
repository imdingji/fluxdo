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
