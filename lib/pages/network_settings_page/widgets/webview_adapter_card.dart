import 'package:flutter/material.dart';

import '../../../l10n/s.dart';
import '../../../services/network/webview/webview_adapter_settings_service.dart';

/// WebView 适配器设置卡片
class WebViewAdapterCard extends StatelessWidget {
  const WebViewAdapterCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = WebViewAdapterSettingsService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: service.notifier,
      builder: (context, enabled, _) {
        return Card(
          clipBehavior: Clip.antiAlias,
          color: enabled
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: enabled
                ? BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  )
                : BorderSide.none,
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: Text(context.l10n.webviewAdapter_title),
                subtitle: Text(
                  enabled
                      ? context.l10n.webviewAdapter_enabledDesc
                      : context.l10n.webviewAdapter_disabledDesc,
                ),
                secondary: Icon(
                  enabled ? Icons.language : Icons.language_outlined,
                  color: enabled ? theme.colorScheme.primary : null,
                ),
                value: enabled,
                onChanged: (value) => service.setEnabled(value),
              ),
              if (enabled) ...[
                Divider(
                  height: 1,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.webviewAdapter_hint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
