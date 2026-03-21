import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:ui';

import 'source_conversation_provider.dart';
import 'source.dart';
import '../chat/github_action_detector.dart';
import '../github/github_issue_dialog.dart';

/// A bottom sheet widget for viewing and sending messages in a source conversation
/// with a third-party coding agent.
///
/// Requirements: 3.1, 3.2, 3.3, 4.2, 4.4, 4.5
class SourceChatSheet extends ConsumerStatefulWidget {
  const SourceChatSheet({
    super.key,
    required this.source,
    this.agentName,
  });

  final Source source;
  final String? agentName;

  @override
  ConsumerState<SourceChatSheet> createState() => _SourceChatSheetState();
}

class _SourceChatSheetState extends ConsumerState<SourceChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  List<_PendingImageAttachment> _pendingImageAttachments = [];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  /// Build GitHub context for the message (Requirements: 4.2)
  Map<String, dynamic>? _buildGitHubContext() {
    if (!widget.source.isGitHubSource) return null;

    return {
      'owner': widget.source.githubOwner,
      'repo': widget.source.githubRepo,
      'path': widget.source.githubPath,
      'branch': widget.source.githubBranch,
      'currentContent': widget.source.content,
      'language': widget.source.language,
    };
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty && _pendingImageAttachments.isEmpty) return;

    final imageAttachments = _pendingImageAttachments
        .map((item) => item.toPayload())
        .toList(growable: false);

    _messageController.clear();
    setState(() => _pendingImageAttachments = []);

    // Include GitHub context for GitHub sources (Requirements: 4.2)
    final githubContext = _buildGitHubContext();

    final success = await ref
        .read(sourceConversationProvider(widget.source.id).notifier)
        .sendMessage(
          message,
          githubContext: githubContext,
          imageAttachments: imageAttachments,
        );

    if (success) {
      _scrollToBottom();
    }
  }

  /// Handle creating an issue from agent suggestion (Requirements: 4.5)
  void _handleCreateIssue(IssueSuggestion suggestion) {
    showGitHubIssueDialog(
      context,
      ref,
      title: suggestion.title,
      body: suggestion.body,
      owner: widget.source.githubOwner,
      repo: widget.source.githubRepo,
    );
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingImageAttachments = [
        ..._pendingImageAttachments,
        _PendingImageAttachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          fileName: picked.name,
          mimeType: _resolveMimeType(picked.name),
          bytes: bytes,
        ),
      ].take(4).toList();
    });
  }

  String _resolveMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final conversationState =
        ref.watch(sourceConversationProvider(widget.source.id));

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              _buildHeader(context, scheme, text),

              // Divider
              Divider(
                height: 1,
                color: scheme.outline.withValues(alpha: 0.1),
              ),

              // Messages list
              Expanded(
                child: conversationState.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : conversationState.error != null
                        ? _buildErrorState(
                            context, scheme, conversationState.error!)
                        : conversationState.messages.isEmpty
                            ? _buildEmptyState(context, scheme, text)
                            : _buildMessagesList(
                                context, scheme, conversationState),
              ),

              // Input area
              _buildInputArea(context, scheme, conversationState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, ColorScheme scheme, TextTheme text) {
    final agentName = widget.agentName ?? 'Coding Agent';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: [
          // Agent icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withValues(alpha: 0.2),
                  scheme.tertiary.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              LucideIcons.terminal,
              color: scheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat with $agentName',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.source.title,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Refresh button
          IconButton(
            onPressed: () {
              ref
                  .read(sourceConversationProvider(widget.source.id).notifier)
                  .refresh();
            },
            icon: Icon(
              LucideIcons.refreshCw,
              size: 18,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
            tooltip: 'Refresh',
          ),

          // Close button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
      BuildContext context, ColorScheme scheme, TextTheme text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.messageSquare,
                size: 40,
                color: scheme.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Start a conversation',
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask questions about this code or request modifications from the agent.',
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildErrorState(
      BuildContext context, ColorScheme scheme, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: scheme.error.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load conversation',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                ref
                    .read(sourceConversationProvider(widget.source.id).notifier)
                    .refresh();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(
    BuildContext context,
    ColorScheme scheme,
    SourceConversationState state,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[index];
        return _MessageBubble(
          message: message,
          agentName: widget.agentName,
          isGitHubSource: widget.source.isGitHubSource,
          onCreateIssue: _handleCreateIssue,
        ).animate().fadeIn(
              duration: 200.ms,
              delay: Duration(milliseconds: index * 50),
            );
      },
    );
  }

  Widget _buildInputArea(
    BuildContext context,
    ColorScheme scheme,
    SourceConversationState state,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImageAttachments.isNotEmpty) ...[
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingImageAttachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _pendingImageAttachments[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          item.bytes,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _pendingImageAttachments =
                                  _pendingImageAttachments
                                      .where((e) => e.id != item.id)
                                      .toList();
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Material(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: state.isSending ? null : _pickImage,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(LucideIcons.image, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Ask about this code...',
                      hintStyle: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Material(
                  color: state.isSending
                      ? scheme.primary.withValues(alpha: 0.5)
                      : scheme.primary,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: state.isSending ? null : _sendMessage,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: state.isSending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: scheme.onPrimary,
                              ),
                            )
                          : Icon(
                              LucideIcons.send,
                              size: 20,
                              color: scheme.onPrimary,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Message bubble widget for displaying individual messages
/// Requirements: 3.3, 4.5
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.agentName,
    this.onCreateIssue,
    this.isGitHubSource = false,
  });

  final SourceMessage message;
  final String? agentName;
  final void Function(IssueSuggestion)? onCreateIssue;
  final bool isGitHubSource;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isUser = message.isUser;

    // Detect issue suggestions in agent messages (Requirements: 4.5)
    final issueSuggestion = !isUser
        ? GitHubActionDetector.detectIssueSuggestion(message.content)
        : null;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender label
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isUser) ...[
                    Icon(
                      LucideIcons.bot,
                      size: 12,
                      color: scheme.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    isUser ? 'You' : (agentName ?? 'Agent'),
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(message.timestamp),
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

            // Message content
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildMessageContent(context, scheme, text, isUser),
            ),
            if (message.imageAttachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _MessageImageAttachments(
                  attachments: message.imageAttachments,
                  isUser: isUser,
                ),
              ),

            // Code update indicator
            if (message.hasCodeUpdate)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.code2,
                        size: 12,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Code updated',
                        style: text.labelSmall?.copyWith(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Create Issue action button for agent suggestions (Requirements: 4.5)
            if (issueSuggestion != null &&
                isGitHubSource &&
                onCreateIssue != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _IssueActionButton(
                  suggestion: issueSuggestion,
                  onTap: () => onCreateIssue!(issueSuggestion),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    ColorScheme scheme,
    TextTheme text,
    bool isUser,
  ) {
    final content = message.content;

    // Check if content contains code blocks
    if (_containsCodeBlock(content)) {
      return _buildMarkdownContent(context, scheme, text, isUser);
    }

    // Plain text
    return SelectableText(
      content,
      style: text.bodyMedium?.copyWith(
        color: isUser ? scheme.onPrimary : scheme.onSurface,
        height: 1.4,
      ),
    );
  }

  bool _containsCodeBlock(String content) {
    return content.contains('```') || content.contains('`');
  }

  Widget _buildMarkdownContent(
    BuildContext context,
    ColorScheme scheme,
    TextTheme text,
    bool isUser,
  ) {
    return MarkdownBody(
      data: message.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: text.bodyMedium?.copyWith(
          color: isUser ? scheme.onPrimary : scheme.onSurface,
          height: 1.4,
        ),
        code: text.bodySmall?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: isUser
              ? scheme.onPrimary.withValues(alpha: 0.1)
              : scheme.surfaceContainerHighest,
          color: isUser ? scheme.onPrimary : scheme.primary,
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF282C34),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
      ),
      builders: {
        'code': _CodeBlockBuilder(scheme: scheme),
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${time.day}/${time.month}';
    }
  }
}

class _PendingImageAttachment {
  final String id;
  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  _PendingImageAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  Map<String, dynamic> toPayload() {
    return {
      'id': id,
      'name': fileName,
      'mimeType': mimeType,
      'base64Data': base64Encode(bytes),
      'sizeBytes': bytes.length,
    };
  }
}

class _MessageImageAttachments extends StatelessWidget {
  final List<Map<String, dynamic>> attachments;
  final bool isUser;

  const _MessageImageAttachments({
    required this.attachments,
    required this.isUser,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: attachments.take(4).map((attachment) {
        final base64Data = attachment['base64Data']?.toString() ?? '';
        if (base64Data.isEmpty) {
          return Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isUser
                  ? scheme.primary.withValues(alpha: 0.12)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.image_not_supported_outlined, size: 18),
          );
        }
        try {
          final bytes = base64Decode(base64Data);
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {
          return Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isUser
                  ? scheme.primary.withValues(alpha: 0.12)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.broken_image_outlined, size: 18),
          );
        }
      }).toList(),
    );
  }
}

/// Action button for creating GitHub issues from agent suggestions
/// Requirements: 4.5
class _IssueActionButton extends StatelessWidget {
  const _IssueActionButton({
    required this.suggestion,
    required this.onTap,
  });

  final IssueSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.green.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.green.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.gitPullRequestDraft,
                size: 14,
                color: Colors.green.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                'Create Issue',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (suggestion.isExplicit) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Suggested',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom code block builder for syntax highlighting
/// Requirements: 3.3
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget? visitElementAfter(element, preferredStyle) {
    final code = element.textContent;
    final language = _detectLanguage(element.attributes['class']);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF282C34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Language header with copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                Builder(
                  builder: (context) => InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Code copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.copy,
                        size: 14,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code content with basic styling
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
                color: Color(0xFFABB2BF), // Light gray for code
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _detectLanguage(String? className) {
    if (className == null) return 'plaintext';

    // Extract language from class like "language-dart"
    final match = RegExp(r'language-(\w+)').firstMatch(className);
    if (match != null) {
      return match.group(1) ?? 'plaintext';
    }

    return 'plaintext';
  }
}

/// Helper function to show the source chat sheet
/// Requirements: 3.1
void showSourceChatSheet(
  BuildContext context, {
  required Source source,
  String? agentName,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SourceChatSheet(
      source: source,
      agentName: agentName,
    ),
  );
}
