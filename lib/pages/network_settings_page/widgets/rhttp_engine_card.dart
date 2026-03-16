import 'package:flutter/material.dart';

import '../../../services/network/adapters/platform_adapter.dart';
import '../../../services/network/doh/network_settings_service.dart';
import '../../../services/network/proxy/proxy_settings_service.dart';
import '../../../services/network/rhttp/rhttp_settings_service.dart';

/// rhttp 引擎设置卡片
class RhttpEngineCard extends StatelessWidget {
  const RhttpEngineCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rhttpService = RhttpSettingsService.instance;
    final networkService = NetworkSettingsService.instance;
    final proxyService = ProxySettingsService.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([
        rhttpService.notifier,
        networkService.notifier,
        proxyService.notifier,
      ]),
      builder: (context, _) {
        final settings = rhttpService.current;
        final enabled = settings.enabled;
        final ns = networkService.current;
        final ps = proxyService.current;

        // 从当前设置直接推算适配器类型（不依赖全局变量，避免滞后）
        final wouldUseRhttp = rhttpService.shouldUseRhttp(ns, ps);
        final echFallback = enabled && ns.dohEnabled && ns.echServerUrl != null;

        // 推算当前实际适配器类型
        final AdapterType effectiveType;
        if (wouldUseRhttp) {
          effectiveType = AdapterType.rhttp;
        } else if (networkService.shouldRunLocalProxy) {
          effectiveType = AdapterType.network;
        } else {
          effectiveType = AdapterType.native;
        }

        return Card(
          clipBehavior: Clip.antiAlias,
          color: enabled
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: enabled
                ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3))
                : BorderSide.none,
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('rhttp 引擎'),
                subtitle: Text(
                  enabled
                      ? 'HTTP/2 多路复用 · Rust reqwest'
                      : '启用后使用 Rust 网络引擎',
                ),
                secondary: Icon(
                  enabled ? Icons.rocket_launch : Icons.rocket_launch_outlined,
                  color: enabled ? theme.colorScheme.primary : null,
                ),
                value: enabled,
                onChanged: (value) => rhttpService.setEnabled(value),
              ),

              if (enabled) ...[
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),

                // 模式选择
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '使用模式',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<RhttpMode>(
                          segments: const [
                            ButtonSegment(
                              value: RhttpMode.always,
                              label: Text('始终使用'),
                            ),
                            ButtonSegment(
                              value: RhttpMode.proxyOnly,
                              label: Text('仅代理/DOH'),
                            ),
                          ],
                          selected: {settings.mode},
                          onSelectionChanged: (modes) {
                            rhttpService.setMode(modes.first);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // 当前适配器状态
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        wouldUseRhttp ? Icons.check_circle : Icons.info_outline,
                        size: 16,
                        color: wouldUseRhttp
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '当前: ${getAdapterDisplayName(effectiveType)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // ECH 回退提示
                if (echFallback)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ECH 启用时自动回退为代理模式（reqwest 不支持 ECH）',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
