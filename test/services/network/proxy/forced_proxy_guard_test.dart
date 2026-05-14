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
