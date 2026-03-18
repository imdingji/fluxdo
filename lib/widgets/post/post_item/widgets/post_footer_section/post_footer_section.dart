import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../l10n/s.dart';
import '../../../../../constants.dart';
import '../../../../../models/topic.dart';
import '../../../../../modules/ldc_reward/ldc_reward.dart';
import '../../../../../providers/discourse_providers.dart';
import '../../../../../providers/preferences_provider.dart';
import 'package:dio/dio.dart';
import '../../../../../services/app_error_handler.dart';
import '../../../../../services/discourse/discourse_service.dart';
import '../../../../../services/toast_service.dart';
import '../../../post_links.dart';
import '../post_action_bar.dart';
import '../../../../bookmark/bookmark_edit_sheet.dart';
import '../post_flag_sheet.dart';
import '../post_reaction_picker.dart';
import '../post_reaction_users_sheet.dart';
import '../post_replies_list.dart';
import '../post_solution_banner.dart';
import '../../../../post/post_replies_sheet.dart';

part 'actions/bookmark_actions.dart';
part 'actions/manage_actions.dart';
part 'actions/menu_actions.dart';
part 'actions/reaction_actions.dart';
part 'actions/reply_actions.dart';

class PostFooterSection extends ConsumerStatefulWidget {
  final Post post;
  final int topicId;
  final bool topicHasAcceptedAnswer;
  final int? acceptedAnswerPostNumber;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onShareAsImage;
  final void Function(int postId)? onRefreshPost;
  final void Function(int postNumber)? onJumpToPost;
  final void Function(int postId, bool accepted)? onSolutionChanged;
  final ValueChanged<bool>? onAcceptedAnswerChanged;
  final bool useReplyDialog;
  /// 隐藏回复列表按钮（弹框内使用时不需要展示）
  final bool hideRepliesButton;
  /// 查看帖子详情回调（菜单中的"查看帖子详情"或"跳转"）
  final VoidCallback? onShowPostDetail;
  /// 自定义帖子详情菜单项文本（默认"帖子详情"，弹框中可用"跳转"）
  final String? postDetailLabel;
  /// 菜单注册回调（允许外部触发相同的菜单）
  final ValueChanged<VoidCallback>? onMenuRegistered;

  const PostFooterSection({
    super.key,
    required this.post,
    required this.topicId,
    required this.topicHasAcceptedAnswer,
    required this.acceptedAnswerPostNumber,
    required this.padding,
    required this.onReply,
    required this.onEdit,
    required this.onShareAsImage,
    required this.onRefreshPost,
    required this.onJumpToPost,
    required this.onSolutionChanged,
    this.onAcceptedAnswerChanged,
    this.useReplyDialog = false,
    this.hideRepliesButton = false,
    this.onShowPostDetail,
    this.postDetailLabel,
    this.onMenuRegistered,
  });

  @override
  ConsumerState<PostFooterSection> createState() => _PostFooterSectionState();
}

class _PostFooterSectionState extends ConsumerState<PostFooterSection> {
  final DiscourseService _service = DiscourseService();
  final GlobalKey _likeButtonKey = GlobalKey();
  bool _isLiking = false;
  bool _isBookmarked = false;
  int? _bookmarkId;
  String? _bookmarkName;
  DateTime? _bookmarkReminderAt;
  bool _isBookmarking = false;
  late List<PostReaction> _reactions;
  PostReaction? _currentUserReaction;
  final List<Post> _replies = [];
  final ValueNotifier<bool> _isLoadingRepliesNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _showRepliesNotifier = ValueNotifier<bool>(false);
  bool _isAcceptedAnswer = false;
  bool _isTogglingAnswer = false;
  bool _isDeleting = false;

  bool get _canLoadMoreReplies => _replies.length < widget.post.replyCount;

  @override
  void initState() {
    super.initState();
    _syncState();
    widget.onMenuRegistered?.call(_triggerMoreMenu);
  }

  void _triggerMoreMenu() {
    if (!mounted) return;
    _showMoreMenu(context, Theme.of(context));
  }

  @override
  void didUpdateWidget(PostFooterSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post != widget.post) {
      _syncState();
    }
    // 重新注册菜单回调（rebuild 时 local 变量可能已更新）
    widget.onMenuRegistered?.call(_triggerMoreMenu);
  }

  @override
  void dispose() {
    _isLoadingRepliesNotifier.dispose();
    _showRepliesNotifier.dispose();
    super.dispose();
  }

  void _syncState() {
    _reactions = List.from(widget.post.reactions ?? []);
    _currentUserReaction = widget.post.currentUserReaction;
    _isBookmarked = widget.post.bookmarked;
    _bookmarkId = widget.post.bookmarkId;
    _bookmarkName = widget.post.bookmarkName;
    _bookmarkReminderAt = widget.post.bookmarkReminderAt;
    _isAcceptedAnswer = widget.post.acceptedAnswer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = ref.read(currentUserProvider).value;
    final isOwnPost = currentUser != null && currentUser.username == widget.post.username;
    final isGuest = currentUser == null;

    // 预热打赏凭证，避免首次打开更多菜单时因 AsyncLoading 导致打赏选项不显示
    ref.watch(ldcRewardCredentialsProvider);

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostLinks(linkCounts: widget.post.linkCounts),
          if (widget.post.postNumber == 1 &&
              widget.topicHasAcceptedAnswer &&
              widget.acceptedAnswerPostNumber != null)
            PostSolutionBanner(
              acceptedAnswerPostNumber: widget.acceptedAnswerPostNumber,
              onJumpToPost: widget.onJumpToPost,
            ),
          const SizedBox(height: 12),
          PostActionBar(
            post: widget.post,
            isGuest: isGuest,
            isOwnPost: isOwnPost,
            isLiking: _isLiking,
            reactions: _reactions,
            currentUserReaction: _currentUserReaction,
            likeButtonKey: _likeButtonKey,
            replies: _replies,
            isLoadingRepliesNotifier: _isLoadingRepliesNotifier,
            showRepliesNotifier: _showRepliesNotifier,
            hideRepliesButton: widget.hideRepliesButton,
            onToggleLike: _toggleLike,
            onShowReactionPicker: () => _showReactionPicker(context, theme),
            onShowReactionUsers: (reactionId) =>
                _showReactionUsers(context, reactionId: reactionId),
            onReply: widget.onReply,
            onShowMoreMenu: () => _showMoreMenu(context, theme),
            onToggleReplies: _toggleReplies,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _showRepliesNotifier,
            builder: (context, showReplies, _) {
              if (!showReplies) return const SizedBox.shrink();
              return PostRepliesList(
                replies: _replies,
                replyCount: widget.post.replyCount,
                canLoadMore: _canLoadMoreReplies,
                isLoadingRepliesNotifier: _isLoadingRepliesNotifier,
                showRepliesNotifier: _showRepliesNotifier,
                onLoadMore: _loadReplies,
                onJumpToPost: widget.onJumpToPost,
                contentFontScale: ref.watch(preferencesProvider).contentFontScale,
              );
            },
          ),
        ],
      ),
    );
  }
}
