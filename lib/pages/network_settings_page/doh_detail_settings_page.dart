import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/network/doh/doh_resolver.dart';
import '../../services/network/doh/network_settings_service.dart';
import '../../services/toast_service.dart';

/// DOH 详细设置页面（服务器列表、IPv6、服务端 IP、ECH）
class DohDetailSettingsPage extends StatefulWidget {
  const DohDetailSettingsPage({super.key});

  @override
  State<DohDetailSettingsPage> createState() => _DohDetailSettingsPageState();
}

class _DohDetailSettingsPageState extends State<DohDetailSettingsPage> {
  final NetworkSettingsService _service = NetworkSettingsService.instance;
  final Map<String, int?> _latencies = {};
  final Set<String> _testingServers = {};
  bool _testingAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _service.notifier,
      builder: (context, _) {
        final settings = _service.current;

        return Scaffold(
          appBar: AppBar(title: const Text('DOH 详细设置')),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // IPv6 开关
              Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('IPv6 优先'),
                      subtitle: const Text('优先尝试 IPv6，失败自动回落 IPv4'),
                      secondary: const Icon(Icons.language),
                      value: settings.preferIPv6,
                      onChanged: (value) => _service.setPreferIPv6(value),
                    ),
                    Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                    // Server IP
                    ListTile(
                      leading: const Icon(Icons.dns),
                      title: const Text('服务端 IP'),
                      subtitle: Text(
                        settings.serverIp != null && settings.serverIp!.isNotEmpty
                            ? settings.serverIp!
                            : '未设置',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: settings.serverIp != null && settings.serverIp!.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              tooltip: '清除',
                              onPressed: () => _service.setServerIp(null),
                            )
                          : null,
                      onTap: () => _showServerIpDialog(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 服务器列表
              _buildSectionHeader(theme, '服务器'),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // 工具栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(
                        children: [
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _testingAll ? null : _testAllServers,
                            icon: _testingAll
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.speed, size: 16),
                            label: Text(_testingAll ? '测速中' : '全部测速'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showAddServerDialog,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('添加'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 服务器列表
                    _buildServerList(theme, settings),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ECH 服务器选择
              _buildSectionHeader(theme, 'ECH'),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _buildEchServerSelector(theme, settings),
              ),
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

  Widget _buildServerList(ThemeData theme, NetworkSettings settings) {
    final servers = _service.servers;

    return RadioGroup<String>(
      groupValue: settings.selectedServerUrl,
      onChanged: (value) {
        if (value != null) _service.setSelectedServer(value);
      },
      child: Column(
        children: [
          for (int i = 0; i < servers.length; i++) ...[
            _buildServerTile(theme, servers[i], settings),
            if (i != servers.length - 1)
              Divider(
                height: 1,
                indent: 56,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
          ],
          if (servers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无服务器'),
            ),
        ],
      ),
    );
  }

  Widget _buildServerTile(ThemeData theme, DohServer server, NetworkSettings settings) {
    final selected = server.url == settings.selectedServerUrl;
    final isTesting = _testingServers.contains(server.url);
    final latency = _latencies[server.url];

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 8, right: 12),
      leading: Radio<String>(
        value: server.url,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              server.name,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (server.isCustom)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '自定义',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        server.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTesting)
            const SizedBox(
              width: 48,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (latency != null)
            SizedBox(
              width: 48,
              child: Text(
                '${latency}ms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _getLatencyColor(latency),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            )
          else
            SizedBox(
              width: 48,
              child: IconButton(
                icon: const Icon(Icons.speed, size: 20),
                tooltip: '测速',
                onPressed: () => _testServer(server),
                visualDensity: VisualDensity.compact,
              ),
            ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: theme.colorScheme.onSurfaceVariant),
            tooltip: '更多',
            padding: EdgeInsets.zero,
            onSelected: (value) {
              switch (value) {
                case 'copy':
                  Clipboard.setData(ClipboardData(text: server.url));
                  ToastService.showInfo('已复制 DoH 地址');
                case 'edit':
                  _showEditServerDialog(server);
                case 'delete':
                  _confirmDeleteServer(server);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy, size: 20),
                  title: Text('复制地址'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (server.isCustom) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit, size: 20),
                    title: Text('编辑'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                    title: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      selected: selected,
      onTap: () => _service.setSelectedServer(server.url),
    );
  }

  Color _getLatencyColor(int latency) {
    if (latency < 100) return Colors.green;
    if (latency < 300) return Colors.orange;
    return Colors.red;
  }

  Future<void> _testServer(DohServer server) async {
    if (_testingServers.contains(server.url)) return;

    setState(() => _testingServers.add(server.url));

    final resolver = DohResolver(
      serverUrl: server.url,
      bootstrapIps: server.bootstrapIps,
      enableFallback: false,
    );
    try {
      final ms = await resolver.testLatency(_service.testHost);
      if (mounted) {
        setState(() {
          _latencies[server.url] = ms;
          _testingServers.remove(server.url);
        });
      }
    } finally {
      resolver.dispose();
    }
  }

  Future<void> _testAllServers() async {
    if (_testingAll) return;
    setState(() => _testingAll = true);

    final servers = _service.servers;
    final futures = <Future<void>>[];

    for (final server in servers) {
      futures.add(_testServer(server));
    }

    await Future.wait(futures);

    if (mounted) {
      setState(() => _testingAll = false);
    }
  }

  Widget _buildEchServerSelector(ThemeData theme, NetworkSettings settings) {
    final servers = _service.servers;
    final currentEch = settings.echServerUrl;
    String echLabel = '与 DNS 相同';
    if (currentEch != null) {
      for (final s in servers) {
        if (s.url == currentEch) {
          echLabel = s.name;
          break;
        }
      }
    }

    return ListTile(
      leading: const Icon(Icons.security),
      title: const Text('ECH 服务器'),
      subtitle: Text(
        echLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showEchServerDialog(servers, currentEch),
    );
  }

  Future<void> _showEchServerDialog(List<DohServer> servers, String? currentEch) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择 ECH 服务器'),
          children: [
            RadioListTile<String?>(
              title: const Text('与 DNS 相同'),
              subtitle: Text(
                '使用 DNS 解析服务器查询 ECH 配置',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: null,
              groupValue: currentEch,
              onChanged: (value) => Navigator.pop(context, '__null__'),
            ),
            for (final server in servers)
              RadioListTile<String>(
                title: Text(server.name),
                subtitle: Text(
                  server.url,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                value: server.url,
                groupValue: currentEch,
                onChanged: (value) => Navigator.pop(context, value),
              ),
          ],
        );
      },
    );

    if (result != null) {
      if (result == '__null__') {
        await _service.setEchServer(null);
      } else {
        await _service.setEchServer(result);
      }
    }
  }

  Future<void> _showAddServerDialog() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final bootstrapIpsController = TextEditingController();

    final result = await showDialog<DohServer>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('添加服务器'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：My DNS',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'DoH 地址',
                  hintText: 'https://dns.example.com/dns-query',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bootstrapIpsController,
                decoration: const InputDecoration(
                  labelText: 'Bootstrap IP（可选）',
                  hintText: '用逗号分隔，如 1.1.1.1, 1.0.0.1',
                  helperText: '直接用 IP 连接 DoH 服务器，绕过 DNS 解析',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                if (name.isEmpty || url.isEmpty) {
                  ToastService.showInfo('请填写完整信息');
                  return;
                }
                if (!url.startsWith('https://')) {
                  ToastService.showError('地址必须以 https:// 开头');
                  return;
                }
                final bootstrapIps = _parseBootstrapIps(bootstrapIpsController.text);
                Navigator.pop(
                  context,
                  DohServer(
                    name: name,
                    url: url,
                    isCustom: true,
                    bootstrapIps: bootstrapIps,
                  ),
                );
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _service.addCustomServer(result);
    }
  }

  Future<void> _showEditServerDialog(DohServer server) async {
    final nameController = TextEditingController(text: server.name);
    final urlController = TextEditingController(text: server.url);
    final bootstrapIpsController = TextEditingController(
      text: server.bootstrapIps.join(', '),
    );

    final result = await showDialog<DohServer>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('编辑服务器'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如：My DNS',
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'DoH 地址',
                  hintText: 'https://dns.example.com/dns-query',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bootstrapIpsController,
                decoration: const InputDecoration(
                  labelText: 'Bootstrap IP（可选）',
                  hintText: '用逗号分隔，如 1.1.1.1, 1.0.0.1',
                  helperText: '直接用 IP 连接 DoH 服务器，绕过 DNS 解析',
                  helperMaxLines: 2,
                ),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final url = urlController.text.trim();
                if (name.isEmpty || url.isEmpty) {
                  ToastService.showInfo('请填写完整信息');
                  return;
                }
                if (!url.startsWith('https://')) {
                  ToastService.showError('地址必须以 https:// 开头');
                  return;
                }
                final bootstrapIps = _parseBootstrapIps(bootstrapIpsController.text);
                Navigator.pop(
                  context,
                  DohServer(
                    name: name,
                    url: url,
                    isCustom: true,
                    bootstrapIps: bootstrapIps,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _service.updateCustomServer(server, result);
    }
  }

  Future<void> _showServerIpDialog() async {
    final settings = _service.current;
    final controller = TextEditingController(
      text: settings.serverIp ?? '',
    );

    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('服务端 IP'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '指定连接 IP，跳过 DNS 解析',
              labelText: 'IP 地址',
            ),
            keyboardType: TextInputType.text,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            if (settings.serverIp != null && settings.serverIp!.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('清除'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _service.setServerIp(result.isEmpty ? null : result);
    }
  }

  Future<void> _confirmDeleteServer(DohServer server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除服务器'),
        content: Text('确定要删除 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.removeCustomServer(server);
    }
  }

  List<String> _parseBootstrapIps(String text) {
    return text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
