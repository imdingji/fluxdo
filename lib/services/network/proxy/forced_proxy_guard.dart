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
