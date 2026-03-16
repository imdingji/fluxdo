import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/network/doh/network_settings_service.dart';
import '../../../services/network/vpn_auto_toggle_service.dart';
import '../../../services/toast_service.dart';
import '../doh_detail_settings_page.dart';

/// DOH 设置卡片（简化版：开关 + 状态 + "更多设置"入口）
class DohSettingsCard extends StatelessWidget {
  const DohSettingsCard({
    super.key,
    required this.settings,
    required this.isApplying,
    this.isSuppressedByVpn = false,
  });

  final NetworkSettings settings;
  final bool isApplying;
  final bool isSuppressedByVpn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = NetworkSettingsService.instance;
    final proxyService = service.proxyService;
    final isRunning = proxyService.isRunning;
    final port = settings.proxyPort;
    final showLoading = isApplying ||
        service.pendingStart ||
        (settings.dohEnabled && !isRunning && !service.lastStartFailed);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: settings.dohEnabled
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: settings.dohEnabled
            ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
      child: Column(
        children: [
          // DOH 开关
          SwitchListTile(
            title: const Text('DNS over HTTPS'),
            subtitle: Text(
              isSuppressedByVpn
                  ? '已被 VPN 自动关闭，VPN 断开后将自动恢复'
                  : settings.dohEnabled
                      ? '已启用加密 DNS 解析'
                      : '使用系统默认 DNS',
            ),
            secondary: Icon(
              settings.dohEnabled ? Icons.shield : Icons.shield_outlined,
              color: settings.dohEnabled ? theme.colorScheme.primary : null,
            ),
            value: settings.dohEnabled,
            onChanged: (value) async {
              await service.setDohEnabled(value);
              if (value && isSuppressedByVpn) {
                VpnAutoToggleService.instance.clearDohSuppression();
              }
            },
          ),

          // 仅在开启 DOH 后显示以下内容
          if (settings.dohEnabled) ...[
            // 状态区域
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
            _buildStatusArea(context, theme, service, proxyService, isRunning, port, showLoading),

            // 启动失败提示
            if (!isRunning && !isApplying && service.lastStartFailed)
              _buildFailureHint(context, theme, service, proxyService),

            // 更多设置入口
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2)),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('更多设置'),
              subtitle: const Text('服务器、IPv6、ECH 等'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DohDetailSettingsPage(),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusArea(
    BuildContext context,
    ThemeData theme,
    NetworkSettingsService service,
    dynamic proxyService,
    bool isRunning,
    int? port,
    bool showLoading,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: showLoading
                ? _buildStatusChip(
                    theme,
                    key: const ValueKey('applying'),
                    customIcon: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    label: service.wasRunningBeforeApply ? '正在重启...' : '正在启动...',
                    color: theme.colorScheme.primary,
                  )
                : _buildStatusChip(
                    theme,
                    key: ValueKey('status_${isRunning}_${service.lastStartFailed}'),
                    icon: isRunning
                        ? Icons.check_circle
                        : service.lastStartFailed
                            ? Icons.error
                            : Icons.hourglass_top,
                    label: isRunning ? '代理运行中' : '代理未启动',
                    color: isRunning ? Colors.green : theme.colorScheme.error,
                  ),
          ),
          const SizedBox(width: 12),
          if (port != null && isRunning)
            _buildStatusChip(
              theme,
              icon: Icons.lan,
              label: '端口 $port',
              color: theme.colorScheme.secondary,
            ),
          if (isRunning) ...[
            const Spacer(),
            IconButton(
              onPressed: isApplying ? null : service.restartProxy,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '重启代理',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFailureHint(
    BuildContext context,
    ThemeData theme,
    NetworkSettingsService service,
    dynamic proxyService,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '代理启动失败，DoH/ECH 无法生效',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              TextButton(
                onPressed: isApplying ? null : service.restartProxy,
                child: const Text('重试'),
              ),
            ],
          ),
          if (proxyService.lastError != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      proxyService.lastError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: proxyService.lastError!));
                      ToastService.showInfo('已复制错误信息');
                    },
                    child: Icon(
                      Icons.copy,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    ThemeData theme, {
    Key? key,
    IconData? icon,
    Widget? customIcon,
    required String label,
    required Color color,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (customIcon != null)
            customIcon
          else if (icon != null)
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
