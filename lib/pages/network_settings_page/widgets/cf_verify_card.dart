import 'package:flutter/material.dart';

import '../../../services/cf_challenge_service.dart';
import '../../../services/toast_service.dart';

/// Cloudflare 验证独立卡片
class CfVerifyCard extends StatelessWidget {
  const CfVerifyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: const Icon(Icons.security),
        title: const Text('Cloudflare 验证'),
        subtitle: const Text('手动触发过盾验证'),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showManualVerify(context),
      ),
    );
  }

  Future<void> _showManualVerify(BuildContext context) async {
    final result = await CfChallengeService().showManualVerify(context, true);

    if (!context.mounted) return;

    if (result == true) {
      ToastService.showSuccess('验证成功');
    } else if (result == false) {
      ToastService.showError('验证未通过');
    } else {
      if (CfChallengeService().isInCooldown) {
        ToastService.showInfo('验证太频繁，请稍后再试');
      }
    }
  }
}
