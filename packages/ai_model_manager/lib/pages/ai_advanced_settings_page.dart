import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/ai_l10n.dart';
import '../providers/ai_provider_providers.dart';

class AiAdvancedSettingsPage extends ConsumerWidget {
  const AiAdvancedSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final useAppNetwork = ref.watch(aiUseAppNetworkProvider);
    final hasAdapterFactory = ref.watch(aiDioAdapterFactoryProvider) != null;
    final partialEnabled = ref.watch(aiPartialImagesProvider);
    final forcedProxyEnabled =
        isForcedProxyEnabledForAi(ref.watch(aiSharedPreferencesProvider));

    return Scaffold(
      appBar: AppBar(title: Text(AiL10n.current.advancedSettings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(AiL10n.current.useAppNetwork),
                  subtitle: Text(
                    forcedProxyEnabled
                        ? '强制代理模式下必须使用应用网络栈'
                        : AiL10n.current.useAppNetworkSubtitle,
                  ),
                  value: (useAppNetwork || forcedProxyEnabled) &&
                      hasAdapterFactory,
                  onChanged: hasAdapterFactory && !forcedProxyEnabled
                      ? (value) async {
                          final prefs =
                              ref.read(aiSharedPreferencesProvider);
                          await prefs.setBool('ai_use_app_network', value);
                          ref
                              .read(aiUseAppNetworkProvider.notifier)
                              .state = value;
                        }
                      : null,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                SwitchListTile(
                  title: Text(AiL10n.current.partialImagesTitle),
                  subtitle: Text(AiL10n.current.partialImagesSubtitle),
                  value: partialEnabled,
                  onChanged: (value) async {
                    final prefs = ref.read(aiSharedPreferencesProvider);
                    await prefs.setBool('ai_partial_images', value);
                    ref.read(aiPartialImagesProvider.notifier).state =
                        value;
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
