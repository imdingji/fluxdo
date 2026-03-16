import 'dart:io';

import 'package:flutter/material.dart';

import '../../network_adapter_settings_page.dart';

/// 高级设置卡片（仅保留网络适配器入口）
class AdvancedSettingsCard extends StatelessWidget {
  const AdvancedSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) return const SizedBox.shrink();

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: const Icon(Icons.settings_ethernet),
        title: const Text('网络适配器'),
        subtitle: const Text('管理 Cronet 和备用适配器设置'),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NetworkAdapterSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}
