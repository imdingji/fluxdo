import 'package:flutter/material.dart';
import '../../../l10n/s.dart';

/// 话题详情页底部操作栏
class TopicBottomBar extends StatelessWidget {
  final VoidCallback? onScrollToTop;
  final VoidCallback? onShare;
  final VoidCallback? onShareAsImage;
  final VoidCallback? onExport;
  final VoidCallback? onOpenInBrowser;
  final bool hasSummary;
  final bool isSummaryMode;
  final bool isAuthorOnlyMode;
  final bool isTopLevelMode;
  final bool isLoading;
  final VoidCallback? onShowTopReplies;
  final VoidCallback? onShowAuthorOnly;
  final VoidCallback? onShowTopLevelReplies;
  final VoidCallback? onCancelFilter;

  const TopicBottomBar({
    super.key,
    this.onScrollToTop,
    this.onShare,
    this.onShareAsImage,
    this.onExport,
    this.onOpenInBrowser,
    this.hasSummary = false,
    this.isSummaryMode = false,
    this.isAuthorOnlyMode = false,
    this.isTopLevelMode = false,
    this.isLoading = false,
    this.onShowTopReplies,
    this.onShowAuthorOnly,
    this.onShowTopLevelReplies,
    this.onCancelFilter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: 80,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          // 回到顶部
          IconButton(
            onPressed: onScrollToTop,
            icon: const Icon(Icons.vertical_align_top),
            tooltip: context.l10n.topicDetail_scrollToTop,
          ),
          // 热门回复切换
          if (hasSummary)
            _buildTopRepliesButton(context),
          // 只看题主
          _buildAuthorOnlyButton(context),
          // 只看顶层
          _buildTopLevelButton(context),
          // 分享菜单
          _buildShareMenu(context, theme),
          // 在浏览器打开
          IconButton(
            onPressed: onOpenInBrowser,
            icon: const Icon(Icons.language),
            tooltip: context.l10n.topicDetail_openInBrowser,
          ),
        ],
      ),
    );
  }

  Widget _buildShareMenu(BuildContext context, ThemeData theme) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.share_outlined),
      iconColor: theme.colorScheme.onSurfaceVariant,
      tooltip: context.l10n.common_share,
      onSelected: (value) {
        switch (value) {
          case 'link':
            onShare?.call();
            break;
          case 'image':
            onShareAsImage?.call();
            break;
          case 'export':
            onExport?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'link',
          child: Row(
            children: [
              Icon(
                Icons.link,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(context.l10n.topicDetail_shareLink),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'image',
          child: Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(context.l10n.topicDetail_generateShareImage),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(
                Icons.download_outlined,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(context.l10n.topicDetail_exportArticle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopRepliesButton(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: isLoading ? null : (isSummaryMode ? onCancelFilter : onShowTopReplies),
      icon: Icon(
        isSummaryMode
            ? Icons.local_fire_department
            : Icons.local_fire_department_outlined,
        color: isSummaryMode ? theme.colorScheme.primary : null,
      ),
      style: IconButton.styleFrom(
        backgroundColor: isSummaryMode ? theme.colorScheme.primaryContainer : null,
      ),
      tooltip: isSummaryMode ? context.l10n.topicDetail_viewAll : context.l10n.topicDetail_hotOnly,
    );
  }

  Widget _buildAuthorOnlyButton(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: isLoading ? null : (isAuthorOnlyMode ? onCancelFilter : onShowAuthorOnly),
      icon: Icon(
        isAuthorOnlyMode
            ? Icons.person
            : Icons.person_outline,
        color: isAuthorOnlyMode ? theme.colorScheme.primary : null,
      ),
      style: IconButton.styleFrom(
        backgroundColor: isAuthorOnlyMode ? theme.colorScheme.primaryContainer : null,
      ),
      tooltip: isAuthorOnlyMode ? context.l10n.topicDetail_viewAll : context.l10n.topicDetail_authorOnly,
    );
  }

  Widget _buildTopLevelButton(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: isLoading ? null : (isTopLevelMode ? onCancelFilter : onShowTopLevelReplies),
      icon: Icon(
        isTopLevelMode
            ? Icons.account_tree
            : Icons.account_tree_outlined,
        color: isTopLevelMode ? theme.colorScheme.primary : null,
      ),
      style: IconButton.styleFrom(
        backgroundColor: isTopLevelMode ? theme.colorScheme.primaryContainer : null,
      ),
      tooltip: isTopLevelMode ? context.l10n.topicDetail_viewAll : context.l10n.topicDetail_topLevelOnly,
    );
  }
}
