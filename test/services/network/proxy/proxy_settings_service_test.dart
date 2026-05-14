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
      expect(
        service.validateForcedMode(),
        '强制代理需要先配置有效的 HTTP 或 SOCKS5 代理',
      );
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
      expect(
        service.current.forcedProxyUri,
        'http://user:pass@proxy.example.com:8080',
      );
      expect(prefs.getBool('forced_proxy_enabled'), isTrue);
    });

    test('enabling forced mode also enables AI app network preference', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ProxySettingsService.instance;
      await service.initialize(prefs);

      await service.setForcedEnabled(true);

      expect(prefs.getBool('ai_use_app_network'), isTrue);
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
