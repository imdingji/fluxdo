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

      expect(
        NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, null, false),
        isFalse,
      );
      expect(
        NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, 9000, false),
        isTrue,
      );
    });

    test('keeps existing local gateway behavior outside forced mode', () {
      const settings = ProxySettings(
        enabled: true,
        protocol: UpstreamProxyProtocol.http,
        host: 'proxy.example.com',
        port: 8080,
      );

      expect(
        NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, null, true),
        isFalse,
      );
      expect(
        NetworkHttpAdapter.shouldUseLocalGatewayFor(settings, 9000, true),
        isTrue,
      );
    });
  });
}
