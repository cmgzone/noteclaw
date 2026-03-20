// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_service.dart';
import '../../core/extensions/color_compat.dart';

/// Model for API token data
/// Requirements: 2.1
class ApiToken {
  final String id;
  final String name;
  final String tokenPrefix;
  final String tokenSuffix;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final bool isRevoked;

  const ApiToken({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.tokenSuffix,
    this.expiresAt,
    this.lastUsedAt,
    required this.createdAt,
    this.isRevoked = false,
  });

  factory ApiToken.fromJson(Map<String, dynamic> json) {
    return ApiToken(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed Token',
      tokenPrefix: json['token_prefix'] as String? ??
          json['tokenPrefix'] as String? ??
          'nclaw_***',
      tokenSuffix: json['token_suffix'] as String? ??
          json['tokenSuffix'] as String? ??
          '****',
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : json['expiresAt'] != null
              ? DateTime.parse(json['expiresAt'] as String)
              : null,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.parse(json['last_used_at'] as String)
          : json['lastUsedAt'] != null
              ? DateTime.parse(json['lastUsedAt'] as String)
              : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : DateTime.now(),
      isRevoked: json['revoked_at'] != null || json['revokedAt'] != null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'token_prefix': tokenPrefix,
      'token_suffix': tokenSuffix,
      'expires_at': expiresAt?.toIso8601String(),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'revoked_at': isRevoked ? DateTime.now().toIso8601String() : null,
    };
  }

  String get displayToken => '$tokenPrefix...$tokenSuffix';

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

/// State for API tokens management
class ApiTokensState {
  final List<ApiToken> tokens;
  final bool isLoading;
  final String? error;

  const ApiTokensState({
    this.tokens = const [],
    this.isLoading = false,
    this.error,
  });

  ApiTokensState copyWith({
    List<ApiToken>? tokens,
    bool? isLoading,
    String? error,
  }) {
    return ApiTokensState(
      tokens: tokens ?? this.tokens,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  int get activeCount =>
      tokens.where((t) => !t.isRevoked && !t.isExpired).length;
  bool get canCreateMore => activeCount < 10;
}

int _parseIntValue(dynamic value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class McpStats {
  final int totalTokens;
  final int activeTokens;
  final int totalUsage;
  final int recentUsage;
  final int verifiedSources;
  final int agentSessions;

  const McpStats({
    required this.totalTokens,
    required this.activeTokens,
    required this.totalUsage,
    required this.recentUsage,
    required this.verifiedSources,
    required this.agentSessions,
  });

  factory McpStats.fromJson(Map<String, dynamic> json) {
    return McpStats(
      totalTokens: _parseIntValue(json['totalTokens']),
      activeTokens: _parseIntValue(json['activeTokens']),
      totalUsage: _parseIntValue(json['totalUsage']),
      recentUsage: _parseIntValue(json['recentUsage']),
      verifiedSources: _parseIntValue(json['verifiedSources']),
      agentSessions: _parseIntValue(json['agentSessions']),
    );
  }
}

class McpUsageEntry {
  final String id;
  final String endpoint;
  final String tokenName;
  final String tokenPrefix;
  final DateTime createdAt;
  final String? ipAddress;
  final String? userAgent;

  const McpUsageEntry({
    required this.id,
    required this.endpoint,
    required this.tokenName,
    required this.tokenPrefix,
    required this.createdAt,
    this.ipAddress,
    this.userAgent,
  });

  factory McpUsageEntry.fromJson(Map<String, dynamic> json) {
    return McpUsageEntry(
      id: json['id'] as String? ?? '',
      endpoint: json['endpoint'] as String? ?? 'Unknown endpoint',
      tokenName: json['tokenName'] as String? ?? 'Unnamed token',
      tokenPrefix: json['tokenPrefix'] as String? ?? 'nclaw_***',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      ipAddress: json['ipAddress'] as String?,
      userAgent: json['userAgent'] as String?,
    );
  }
}

class McpInsightsState {
  final McpStats? stats;
  final List<McpUsageEntry> usage;
  final bool isLoading;
  final String? error;

  const McpInsightsState({
    this.stats,
    this.usage = const [],
    this.isLoading = false,
    this.error,
  });

  McpInsightsState copyWith({
    McpStats? stats,
    List<McpUsageEntry>? usage,
    bool? isLoading,
    String? error,
  }) {
    return McpInsightsState(
      stats: stats ?? this.stats,
      usage: usage ?? this.usage,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class McpInsightsNotifier extends StateNotifier<McpInsightsState> {
  final Ref ref;

  McpInsightsNotifier(this.ref) : super(const McpInsightsState()) {
    loadInsights();
  }

  Future<void> loadInsights() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final apiService = ref.read(apiServiceProvider);
      final statsResponse = await apiService.getMcpStats();
      final usageResponse = await apiService.getMcpUsage(limit: 12);

      final statsJson = statsResponse['stats'] is Map<String, dynamic>
          ? statsResponse['stats'] as Map<String, dynamic>
          : statsResponse['stats'] is Map
              ? Map<String, dynamic>.from(statsResponse['stats'] as Map)
              : <String, dynamic>{};

      state = state.copyWith(
        stats: McpStats.fromJson(statsJson),
        usage: usageResponse.map(McpUsageEntry.fromJson).toList(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    await loadInsights();
  }
}

final mcpInsightsProvider =
    StateNotifierProvider<McpInsightsNotifier, McpInsightsState>(
  (ref) => McpInsightsNotifier(ref),
);

/// Provider for managing API tokens
/// Requirements: 1.1, 2.1, 2.2
class ApiTokensNotifier extends StateNotifier<ApiTokensState> {
  final Ref ref;

  ApiTokensNotifier(this.ref) : super(const ApiTokensState()) {
    loadTokens();
  }

  /// Load all API tokens from the API
  Future<void> loadTokens() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final apiService = ref.read(apiServiceProvider);
      final tokensData = await apiService.listApiTokens();

      final tokens = tokensData
          .map((t) => ApiToken.fromJson(t))
          .where((t) => !t.isRevoked)
          .toList();

      state = state.copyWith(
        tokens: tokens,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Generate a new API token
  /// Requirements: 1.1, 1.4, 1.5
  Future<String?> generateToken(String name, DateTime? expiresAt) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final result = await apiService.generateApiToken(
        name: name,
        expiresAt: expiresAt,
      );

      // Reload tokens list
      await loadTokens();
      await ref.read(mcpInsightsProvider.notifier).refresh();

      // Return the full token (only shown once!)
      return result['token'] as String?;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  /// Revoke an API token
  /// Requirements: 2.2, 2.3
  Future<bool> revokeToken(String tokenId) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.revokeApiToken(tokenId);

      // Remove from local state
      final updatedTokens = state.tokens.where((t) => t.id != tokenId).toList();
      state = state.copyWith(tokens: updatedTokens);
      await ref.read(mcpInsightsProvider.notifier).refresh();

      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Refresh tokens
  Future<void> refresh() async {
    await loadTokens();
  }
}

/// Provider for API tokens
final apiTokensProvider =
    StateNotifierProvider<ApiTokensNotifier, ApiTokensState>(
  (ref) => ApiTokensNotifier(ref),
);

/// API Tokens Section widget for Agent Connections screen
/// Requirements: 5.1
class ApiTokensSection extends ConsumerWidget {
  const ApiTokensSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(apiTokensProvider);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.key,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'API Tokens',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${state.activeCount}/10 tokens active',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: state.canCreateMore
                      ? () => _showGenerateTokenDialog(context, ref)
                      : null,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('New Token'),
                  style: FilledButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          // Content
          _buildTokenStateContent(context, ref, state, scheme),
          const McpUsageDashboard(),
          const McpConfigInstructions(),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildTokenStateContent(
    BuildContext context,
    WidgetRef ref,
    ApiTokensState state,
    ColorScheme scheme,
  ) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return _buildErrorState(context, ref, state.error!);
    }

    if (state.tokens.isEmpty) {
      return _buildEmptyState(context, scheme);
    }

    return _buildTokensList(context, ref, state, scheme);
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(LucideIcons.alertCircle, size: 40, color: scheme.error),
          const SizedBox(height: 12),
          Text(
            'Failed to load tokens',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(fontSize: 12, color: scheme.secondaryText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => ref.read(apiTokensProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            LucideIcons.keyRound,
            size: 40,
            color: scheme.secondaryText,
          ),
          const SizedBox(height: 12),
          Text(
            'No API Tokens',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Create a token to authenticate coding agents via MCP',
            style: TextStyle(fontSize: 12, color: scheme.secondaryText),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: const [
              _McpTagChip(
                icon: LucideIcons.download,
                label: 'GitHub Install',
              ),
              _McpTagChip(
                icon: LucideIcons.terminal,
                label: 'Node 20+',
              ),
              _McpTagChip(
                icon: Icons.analytics_outlined,
                label: 'Usage Dashboard',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokensList(
    BuildContext context,
    WidgetRef ref,
    ApiTokensState state,
    ColorScheme scheme,
  ) {
    return Column(
      children: [
        ...state.tokens.asMap().entries.map((entry) {
          final index = entry.key;
          final token = entry.value;
          return TokenListItem(
            token: token,
            onRevoke: () => _showRevokeDialog(context, ref, token),
          ).animate().fadeIn(delay: Duration(milliseconds: index * 50));
        }),
      ],
    );
  }

  void _showGenerateTokenDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => TokenGenerationDialog(
        onGenerate: (name, expiresAt) async {
          final token = await ref
              .read(apiTokensProvider.notifier)
              .generateToken(name, expiresAt);
          return token;
        },
      ),
    );
  }

  void _showRevokeDialog(BuildContext context, WidgetRef ref, ApiToken token) {
    showDialog(
      context: context,
      builder: (context) => RevokeTokenDialog(
        token: token,
        onRevoke: () async {
          final success =
              await ref.read(apiTokensProvider.notifier).revokeToken(token.id);
          return success;
        },
      ),
    );
  }
}

/// Dialog for generating a new API token
/// Requirements: 5.2, 5.3
class TokenGenerationDialog extends StatefulWidget {
  final Future<String?> Function(String name, DateTime? expiresAt) onGenerate;

  const TokenGenerationDialog({
    super.key,
    required this.onGenerate,
  });

  @override
  State<TokenGenerationDialog> createState() => _TokenGenerationDialogState();
}

class _TokenGenerationDialogState extends State<TokenGenerationDialog> {
  final _nameController = TextEditingController();
  DateTime? _expiresAt;
  bool _isGenerating = false;
  String? _generatedToken;
  bool _tokenCopied = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generateToken() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a token name')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    final token = await widget.onGenerate(
      _nameController.text.trim(),
      _expiresAt,
    );

    setState(() {
      _isGenerating = false;
      _generatedToken = token;
    });
  }

  void _copyToken() {
    if (_generatedToken != null) {
      Clipboard.setData(ClipboardData(text: _generatedToken!));
      setState(() => _tokenCopied = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Token copied to clipboard'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_generatedToken != null) {
      return _buildTokenDisplayDialog(context, scheme);
    }

    return AlertDialog(
      icon: Icon(LucideIcons.keyRound, size: 48, color: scheme.primary),
      title: const Text('Generate API Token'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Token Name',
                hintText: 'e.g., Claude Desktop, Cursor IDE',
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            Text(
              'Expiration (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _ExpirationChip(
                  label: 'Never',
                  isSelected: _expiresAt == null,
                  onTap: () => setState(() => _expiresAt = null),
                ),
                _ExpirationChip(
                  label: '30 days',
                  isSelected: _expiresAt != null &&
                      _expiresAt!.difference(DateTime.now()).inDays <= 30,
                  onTap: () => setState(() => _expiresAt =
                      DateTime.now().add(const Duration(days: 30))),
                ),
                _ExpirationChip(
                  label: '90 days',
                  isSelected: _expiresAt != null &&
                      _expiresAt!.difference(DateTime.now()).inDays > 30 &&
                      _expiresAt!.difference(DateTime.now()).inDays <= 90,
                  onTap: () => setState(() => _expiresAt =
                      DateTime.now().add(const Duration(days: 90))),
                ),
                _ExpirationChip(
                  label: '1 year',
                  isSelected: _expiresAt != null &&
                      _expiresAt!.difference(DateTime.now()).inDays > 90,
                  onTap: () => setState(() => _expiresAt =
                      DateTime.now().add(const Duration(days: 365))),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isGenerating ? null : _generateToken,
          child: _isGenerating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate'),
        ),
      ],
    );
  }

  Widget _buildTokenDisplayDialog(BuildContext context, ColorScheme scheme) {
    return AlertDialog(
      icon: Icon(
        _tokenCopied ? LucideIcons.checkCircle : LucideIcons.alertTriangle,
        size: 48,
        color: _tokenCopied ? Colors.green : const Color(0xFFF59E0B),
      ),
      title: Text(_tokenCopied ? 'Token Copied!' : 'Copy Your Token'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertTriangle,
                    size: 20,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This token will only be shown once. Copy it now!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Token display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      _generatedToken!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _copyToken,
                    icon: Icon(
                      _tokenCopied ? LucideIcons.check : LucideIcons.copy,
                      size: 18,
                      color: _tokenCopied ? Colors.green : scheme.primary,
                    ),
                    tooltip: 'Copy token',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_tokenCopied ? 'Done' : 'Close'),
        ),
      ],
    );
  }
}

class _ExpirationChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExpirationChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.1)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? scheme.primary : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Widget for displaying a single API token in the list
/// Requirements: 2.1
class TokenListItem extends StatelessWidget {
  final ApiToken token;
  final VoidCallback onRevoke;

  const TokenListItem({
    super.key,
    required this.token,
    required this.onRevoke,
  });

  String _formatDate(DateTime date) {
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    }
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Token icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: token.isExpired
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                  : scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              token.isExpired ? LucideIcons.clock : LucideIcons.key,
              size: 16,
              color: token.isExpired ? const Color(0xFFF59E0B) : scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          // Token info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        token.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (token.isExpired)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Expired',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // Token preview
                Text(
                  token.displayToken,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: scheme.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                // Dates
                Row(
                  children: [
                    Icon(
                      LucideIcons.calendar,
                      size: 12,
                      color: scheme.hintText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Created ${_formatDate(token.createdAt)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.hintText,
                      ),
                    ),
                    if (token.lastUsedAt != null) ...[
                      const SizedBox(width: 12),
                      Icon(
                        LucideIcons.activity,
                        size: 12,
                        color: scheme.hintText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Used ${_formatTimeAgo(token.lastUsedAt!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.hintText,
                        ),
                      ),
                    ],
                  ],
                ),
                if (token.expiresAt != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.clock,
                        size: 12,
                        color: token.isExpired
                            ? const Color(0xFFF59E0B)
                            : scheme.hintText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        token.isExpired
                            ? 'Expired ${_formatDate(token.expiresAt!)}'
                            : 'Expires ${_formatDate(token.expiresAt!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: token.isExpired
                              ? const Color(0xFFF59E0B)
                              : scheme.hintText,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // Revoke button
          IconButton(
            onPressed: onRevoke,
            icon: Icon(
              LucideIcons.trash2,
              size: 18,
              color: scheme.error,
            ),
            tooltip: 'Revoke token',
          ),
        ],
      ),
    );
  }
}

/// Dialog for confirming token revocation
/// Requirements: 5.5
class RevokeTokenDialog extends StatefulWidget {
  final ApiToken token;
  final Future<bool> Function() onRevoke;

  const RevokeTokenDialog({
    super.key,
    required this.token,
    required this.onRevoke,
  });

  @override
  State<RevokeTokenDialog> createState() => _RevokeTokenDialogState();
}

class _RevokeTokenDialogState extends State<RevokeTokenDialog> {
  bool _isRevoking = false;

  Future<void> _revoke() async {
    setState(() => _isRevoking = true);

    final success = await widget.onRevoke();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Token "${widget.token.name}" revoked'
                : 'Failed to revoke token',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(LucideIcons.alertTriangle, size: 48, color: scheme.error),
      title: const Text('Revoke Token?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Are you sure you want to revoke "${widget.token.name}"?',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.error.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.alertCircle,
                  size: 20,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This action cannot be undone. Any agents using this token will lose access immediately.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isRevoking ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isRevoking ? null : _revoke,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
          ),
          child: _isRevoking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Revoke'),
        ),
      ],
    );
  }
}

class McpUsageDashboard extends ConsumerWidget {
  const McpUsageDashboard({super.key});

  String _formatCompactNumber(int value) {
    return NumberFormat.compact().format(value);
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    }
    return 'Just now';
  }

  String _formatEndpointLabel(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) {
      return 'Unknown endpoint';
    }

    final segments = trimmed.split('/').where((segment) => segment.isNotEmpty);
    final lastSegment = segments.isEmpty ? trimmed : segments.last;
    return lastSegment.replaceAll('_', ' ').replaceAll('-', ' ');
  }

  List<MapEntry<String, int>> _topEndpoints(List<McpUsageEntry> usage) {
    final counts = <String, int>{};
    for (final entry in usage) {
      final label = _formatEndpointLabel(entry.endpoint);
      counts[label] = (counts[label] ?? 0) + 1;
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(3).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(mcpInsightsProvider);
    final stats = state.stats;
    final topEndpoints = _topEndpoints(state.usage);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MCP Usage Dashboard',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Track tokens, calls, and recent agent activity.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: state.isLoading
                    ? null
                    : () => ref.read(mcpInsightsProvider.notifier).refresh(),
                icon: state.isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    : Icon(
                        LucideIcons.refreshCw,
                        size: 18,
                        color: scheme.primary,
                      ),
                tooltip: 'Refresh usage',
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading && stats == null && state.usage.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.error != null && stats == null && state.usage.isEmpty)
            _McpDashboardMessage(
              icon: LucideIcons.alertCircle,
              title: 'Unable to load MCP analytics',
              message: state.error!,
              actionLabel: 'Retry',
              onAction: () => ref.read(mcpInsightsProvider.notifier).refresh(),
              accentColor: scheme.error,
            )
          else ...[
            if (stats != null)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _McpStatCard(
                    icon: LucideIcons.keyRound,
                    label: 'Active Tokens',
                    value: _formatCompactNumber(stats.activeTokens),
                    tone: scheme.primary,
                  ),
                  _McpStatCard(
                    icon: LucideIcons.sparkles,
                    label: 'Total MCP Calls',
                    value: _formatCompactNumber(stats.totalUsage),
                    tone: const Color(0xFF8B5CF6),
                  ),
                  _McpStatCard(
                    icon: LucideIcons.clock3,
                    label: 'Last 24 Hours',
                    value: _formatCompactNumber(stats.recentUsage),
                    tone: const Color(0xFFF59E0B),
                  ),
                  _McpStatCard(
                    icon: Icons.verified_rounded,
                    label: 'Verified Sources',
                    value: _formatCompactNumber(stats.verifiedSources),
                    tone: const Color(0xFF10B981),
                  ),
                  _McpStatCard(
                    icon: LucideIcons.bot,
                    label: 'Agent Sessions',
                    value: _formatCompactNumber(stats.agentSessions),
                    tone: const Color(0xFF06B6D4),
                  ),
                ],
              ),
            if (topEndpoints.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Top MCP activity',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: topEndpoints
                    .map(
                      (entry) => _McpTagChip(
                        icon: LucideIcons.activity,
                        label:
                            '${entry.key} (${_formatCompactNumber(entry.value)})',
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent MCP Activity',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Text(
                  '${state.usage.length} recent calls',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.secondaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (state.usage.isEmpty)
              _McpDashboardMessage(
                icon: Icons.timeline_outlined,
                title: 'No MCP usage yet',
                message:
                    'Once your agent starts using NoteClaw tools, every call will appear here.',
                accentColor: scheme.primary,
              )
            else
              Column(
                children: state.usage
                    .take(6)
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _McpActivityTile(
                          title: _formatEndpointLabel(entry.endpoint),
                          subtitle:
                              '${entry.tokenName} - ${_formatRelativeTime(entry.createdAt)}',
                          rawEndpoint: entry.endpoint,
                          tokenPrefix: entry.tokenPrefix,
                        ),
                      ),
                    )
                    .toList(),
              ),
            if (state.error != null) ...[
              const SizedBox(height: 4),
              _McpDashboardMessage(
                icon: LucideIcons.alertTriangle,
                title: 'Showing last synced analytics',
                message: state.error!,
                accentColor: const Color(0xFFF59E0B),
                actionLabel: 'Retry',
                onAction: () => ref.read(mcpInsightsProvider.notifier).refresh(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _McpStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color tone;

  const _McpStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 136, maxWidth: 168),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: tone.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: tone),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: scheme.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpActivityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String rawEndpoint;
  final String tokenPrefix;

  const _McpActivityTile({
    required this.title,
    required this.subtitle,
    required this.rawEndpoint,
    required this.tokenPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.route_outlined,
              size: 16,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  rawEndpoint,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.hintText,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              tokenPrefix,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _McpDashboardMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _McpDashboardMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.accentColor,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _McpTagChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _McpTagChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget displaying MCP configuration instructions
/// Requirements: 5.4
class McpConfigInstructions extends StatefulWidget {
  const McpConfigInstructions({super.key});

  @override
  State<McpConfigInstructions> createState() => _McpConfigInstructionsState();
}

class _McpConfigInstructionsState extends State<McpConfigInstructions> {
  bool _isExpanded = false;

  static const String _windowsInstallCommand =
      'irm https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.ps1 | iex';

  static const String _macLinuxInstallCommand =
      'curl -fsSL https://raw.githubusercontent.com/cmgzone/noteclaw/HEAD/scripts/install-mcp.sh | bash';

  static const String _mcpConfigExample = '''{
  "mcpServers": {
    "noteclaw": {
      "command": "node",
      "args": ["C:\\\\Users\\\\YOUR_NAME\\\\.noteclaw-mcp\\\\index.js"],
      "env": {
        "BACKEND_URL": "https://noteclaw.onrender.com",
        "CODING_AGENT_API_KEY": "nclaw_your_personal_api_token_here"
      },
      "disabled": false,
      "autoApprove": [
        "verify_code",
        "analyze_code",
        "get_followup_messages"
      ]
    }
  }
}''';

  void _copyText(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildSnippetCard({
    required BuildContext context,
    required String title,
    required String code,
    required String description,
    required String copyLabel,
    required IconData icon,
    required String badge,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              _McpTagChip(
                icon: Icons.label_outline,
                label: badge,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: scheme.secondaryText,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    code,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _copyText(code, copyLabel),
                  icon: Icon(
                    LucideIcons.copy,
                    size: 16,
                    color: scheme.primary,
                  ),
                  tooltip: 'Copy $copyLabel',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 18,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'How to use with MCP',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          if (_isExpanded) ...[
            Divider(
              height: 1,
              color: scheme.primary.withValues(alpha: 0.2),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _McpTagChip(
                        icon: Icons.cloud_download_outlined,
                        label: 'GitHub Release',
                      ),
                      _McpTagChip(
                        icon: Icons.code_rounded,
                        label: 'Node 20+',
                      ),
                      _McpTagChip(
                        icon: Icons.copy_all_rounded,
                        label: 'Copy Install',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Install the latest tagged MCP release from GitHub, then paste the config into your agent connection file.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSnippetCard(
                    context: context,
                    title: 'Windows PowerShell',
                    code: _windowsInstallCommand,
                    description:
                        'Downloads the latest NoteClaw MCP GitHub Release into %USERPROFILE%\\.noteclaw-mcp.',
                    copyLabel: 'Windows install command',
                    icon: Icons.desktop_windows_rounded,
                    badge: 'PowerShell',
                  ),
                  const SizedBox(height: 12),
                  _buildSnippetCard(
                    context: context,
                    title: 'macOS / Linux',
                    code: _macLinuxInstallCommand,
                    description:
                        'Downloads the same tagged release into ~/.noteclaw-mcp for shell-based MCP clients.',
                    copyLabel: 'macOS/Linux install command',
                    icon: Icons.code_rounded,
                    badge: 'bash',
                  ),
                  const SizedBox(height: 12),
                  _buildSnippetCard(
                    context: context,
                    title: 'MCP Config Example',
                    code: _mcpConfigExample,
                    description:
                        'After install, point your agent to the local NoteClaw MCP server and replace the API token placeholder.',
                    copyLabel: 'MCP config',
                    icon: Icons.settings_outlined,
                    badge: 'JSON',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Install Notes',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Windows install path: %USERPROFILE%\\.noteclaw-mcp\\index.js',
                          style:
                              TextStyle(fontSize: 11, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'macOS/Linux install path: ~/.noteclaw-mcp/index.js',
                          style:
                              TextStyle(fontSize: 11, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The scripts install from GitHub Releases only. Users do not need npm or npx, but they still need Node.js 20+ to run index.js.',
                          style:
                              TextStyle(fontSize: 11, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use the MCP Usage Dashboard above to monitor active tokens, recent MCP calls, and follow-up activity after you connect.',
                          style:
                              TextStyle(fontSize: 11, color: scheme.onSurface),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'If a connection fails, verify BACKEND_URL and make sure your copied CODING_AGENT_API_KEY has not expired.',
                          style:
                              TextStyle(fontSize: 11, color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Steps
                  const _InstructionStep(
                    number: '1',
                    text: 'Generate a new API token above',
                  ),
                  const _InstructionStep(
                    number: '2',
                    text:
                        'Copy the install script for the user operating system and run it once',
                  ),
                  const _InstructionStep(
                    number: '3',
                    text:
                        'Replace "nclaw_your_personal_api_token_here" in the config block with the generated token',
                  ),
                  const _InstructionStep(
                    number: '4',
                    text:
                        'Paste the config into Claude/Kiro/Cursor, restart the client, then watch usage in the dashboard above',
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String number;
  final String text;

  const _InstructionStep({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: scheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: scheme.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
