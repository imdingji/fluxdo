import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/network/doh/network_settings_service.dart';
import '../../services/network/proxy/proxy_settings_service.dart';
import '../../services/network/rhttp/rhttp_settings_service.dart';
import '../../services/network/vpn_auto_toggle_service.dart';
import 'widgets/rhttp_engine_card.dart';
import 'widgets/http_proxy_card.dart';
import 'widgets/doh_settings_card.dart';
import 'widgets/vpn_auto_toggle_card.dart';
import 'widgets/cf_verify_card.dart';
import 'widgets/advanced_settings_card.dart';
import 'widgets/debug_tools_card.dart';

/// 网络设置页面
class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  final NetworkSettingsService _service = NetworkSettingsService.instance;
  final ProxySettingsService _proxyService = ProxySettingsService.instance;
  final RhttpSettingsService _rhttpService = RhttpSettingsService.instance;
  final VpnAutoToggleService _vpnService = VpnAutoToggleService.instance;
  bool _isDeveloperMode = false;

  @override
  void initState() {
    super.initState();
    _loadDeveloperMode();
  }

  Future<void> _loadDeveloperMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isDeveloperMode = prefs.getBool('developer_mode') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _service.notifier,
        _service.isApplying,
        _proxyService.notifier,
        _rhttpService.notifier,
        _vpnService.enabledNotifier,
        _vpnService.vpnActiveNotifier,
      ]),
      builder: (context, _) {
        final settings = _service.notifier.value;
        final proxySettings = _proxyService.notifier.value;
        final isApplying = _service.isApplying.value;
        final isDohSuppressed = _vpnService.enabled && _vpnService.isDohSuppressed;
        final isProxySuppressed = _vpnService.enabled && _vpnService.isProxySuppressed;

        return Scaffold(
          appBar: AppBar(
            title: const Text('网络设置'),
            actions: [
              if (isApplying)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 网络引擎
              _buildSectionHeader(theme, '网络引擎'),
              const SizedBox(height: 12),
              const RhttpEngineCard(),
              const SizedBox(height: 24),

              // 网络代理
              _buildSectionHeader(theme, '网络代理'),
              const SizedBox(height: 12),
              DohSettingsCard(
                settings: settings,
                isApplying: isApplying,
                isSuppressedByVpn: isDohSuppressed,
              ),
              const SizedBox(height: 12),
              HttpProxyCard(
                proxySettings: proxySettings,
                dohEnabled: settings.dohEnabled,
                isSuppressedByVpn: isProxySuppressed,
              ),
              const SizedBox(height: 24),

              // 辅助功能
              _buildSectionHeader(theme, '辅助功能'),
              const SizedBox(height: 12),
              const VpnAutoToggleCard(),
              const SizedBox(height: 12),
              const CfVerifyCard(),
              const SizedBox(height: 24),

              // 高级
              _buildSectionHeader(theme, '高级'),
              const SizedBox(height: 12),
              const AdvancedSettingsCard(),
              const SizedBox(height: 24),

              // 调试
              _buildSectionHeader(theme, '调试'),
              const SizedBox(height: 12),
              DebugToolsCard(isDeveloperMode: _isDeveloperMode),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
