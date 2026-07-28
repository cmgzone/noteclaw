import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/api/api_service.dart';

class ApiToken {
  const ApiToken({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.tokenSuffix,
    required this.createdAt,
    this.expiresAt,
    this.lastUsedAt,
    this.isRevoked = false,
    this.boundAgentSessionId,
  });

  final String id;
  final String name;
  final String tokenPrefix;
  final String tokenSuffix;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final bool isRevoked;
  final String? boundAgentSessionId;

  factory ApiToken.fromJson(Map<String, dynamic> json) {
    return ApiToken(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed token',
      tokenPrefix: (json['token_prefix'] ?? json['tokenPrefix'])?.toString() ??
          'nclaw_***',
      tokenSuffix:
          (json['token_suffix'] ?? json['tokenSuffix'])?.toString() ?? '****',
      expiresAt: _parseDate(json['expires_at'] ?? json['expiresAt']),
      lastUsedAt: _parseDate(json['last_used_at'] ?? json['lastUsedAt']),
      createdAt:
          _parseDate(json['created_at'] ?? json['createdAt']) ?? DateTime.now(),
      isRevoked: json['revoked_at'] != null || json['revokedAt'] != null,
      boundAgentSessionId: json['metadata'] is Map
          ? (json['metadata'] as Map)['boundAgentSessionId']?.toString()
          : null,
    );
  }

  String get displayToken => '$tokenPrefix…$tokenSuffix';

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
}

class ApiTokensState {
  const ApiTokensState({
    this.tokens = const [],
    this.isLoading = false,
    this.error,
  });

  final List<ApiToken> tokens;
  final bool isLoading;
  final String? error;

  int get activeCount =>
      tokens.where((token) => !token.isRevoked && !token.isExpired).length;

  bool get canCreateMore => activeCount < 10;
}

class ApiTokensNotifier extends StateNotifier<ApiTokensState> {
  ApiTokensNotifier(this.ref) : super(const ApiTokensState()) {
    refresh();
  }

  final Ref ref;

  Future<void> refresh() async {
    state = ApiTokensState(tokens: state.tokens, isLoading: true);
    try {
      final rows = await ref.read(apiServiceProvider).listApiTokens();
      state = ApiTokensState(
        tokens: rows
            .map(ApiToken.fromJson)
            .where((token) => !token.isRevoked && token.id.isNotEmpty)
            .toList(growable: false),
      );
    } catch (error) {
      state = ApiTokensState(
        tokens: state.tokens,
        error: _friendlyError(error),
      );
    }
  }

  Future<String?> generateToken(String name, DateTime? expiresAt) async {
    try {
      final result = await ref.read(apiServiceProvider).generateApiToken(
            name: name,
            expiresAt: expiresAt,
          );
      await refresh();
      return result['token']?.toString();
    } catch (error) {
      state = ApiTokensState(
        tokens: state.tokens,
        error: _friendlyError(error),
      );
      return null;
    }
  }

  Future<bool> revokeToken(String tokenId) async {
    try {
      await ref.read(apiServiceProvider).revokeApiToken(tokenId);
      state = ApiTokensState(
        tokens: state.tokens
            .where((token) => token.id != tokenId)
            .toList(growable: false),
      );
      return true;
    } catch (error) {
      state = ApiTokensState(
        tokens: state.tokens,
        error: _friendlyError(error),
      );
      return false;
    }
  }
}

final apiTokensProvider =
    StateNotifierProvider<ApiTokensNotifier, ApiTokensState>(
  ApiTokensNotifier.new,
);

class TokenGenerationDialog extends StatefulWidget {
  const TokenGenerationDialog({
    super.key,
    required this.onGenerate,
  });

  final Future<String?> Function(String name, DateTime? expiresAt) onGenerate;

  @override
  State<TokenGenerationDialog> createState() => _TokenGenerationDialogState();
}

class _TokenGenerationDialogState extends State<TokenGenerationDialog> {
  final TextEditingController _nameController = TextEditingController();
  int? _expiryDays;
  String? _generatedToken;
  String? _error;
  bool _isGenerating = false;
  bool _copied = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name for this agent token.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _error = null;
    });
    final expiresAt = _expiryDays == null
        ? null
        : DateTime.now().add(Duration(days: _expiryDays!));
    final token = await widget.onGenerate(name, expiresAt);
    if (!mounted) return;

    setState(() {
      _isGenerating = false;
      _generatedToken = token;
      if (token == null) {
        _error = 'The token could not be created. Try again.';
      }
    });
  }

  Future<void> _copy() async {
    final token = _generatedToken;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final generatedToken = _generatedToken;

    return AlertDialog(
      scrollable: true,
      icon: Icon(
        generatedToken == null ? LucideIcons.keyRound : LucideIcons.checkCircle,
        color:
            generatedToken == null ? scheme.primary : const Color(0xFF14B8A6),
        size: 40,
      ),
      title: Text(
        generatedToken == null ? 'Create MCP token' : 'Copy this token now',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: generatedToken == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _generate(),
                    decoration: const InputDecoration(
                      labelText: 'Token name',
                      hintText: 'e.g. Production agent',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int?>(
                    initialValue: _expiryDays,
                    decoration: const InputDecoration(labelText: 'Expires'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Never')),
                      DropdownMenuItem(value: 30, child: Text('In 30 days')),
                      DropdownMenuItem(value: 90, child: Text('In 90 days')),
                      DropdownMenuItem(value: 365, child: Text('In 1 year')),
                    ],
                    onChanged: (value) => setState(() => _expiryDays = value),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    ),
                  ],
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'This secret is shown once. Store it in the agent’s MCP '
                      'configuration; do not commit it to source control.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      generatedToken,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: generatedToken == null
          ? [
              TextButton(
                onPressed: _isGenerating ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _isGenerating ? null : _generate,
                child: _isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create token'),
              ),
            ]
          : [
              TextButton.icon(
                onPressed: _copy,
                icon: Icon(
                  _copied ? LucideIcons.check : LucideIcons.copy,
                  size: 17,
                ),
                label: Text(_copied ? 'Copied' : 'Copy'),
              ),
              FilledButton(
                onPressed: _copied ? () => Navigator.pop(context) : null,
                child: const Text('Done'),
              ),
            ],
    );
  }
}

class RevokeTokenDialog extends StatefulWidget {
  const RevokeTokenDialog({
    super.key,
    required this.token,
    required this.onRevoke,
  });

  final ApiToken token;
  final Future<bool> Function() onRevoke;

  @override
  State<RevokeTokenDialog> createState() => _RevokeTokenDialogState();
}

class _RevokeTokenDialogState extends State<RevokeTokenDialog> {
  bool _isRevoking = false;
  String? _error;

  Future<void> _revoke() async {
    setState(() {
      _isRevoking = true;
      _error = null;
    });
    final success = await widget.onRevoke();
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _isRevoking = false;
      _error = 'The token could not be revoked. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(LucideIcons.shieldOff, color: scheme.error, size: 38),
      title: const Text('Revoke MCP token?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '“${widget.token.name}” will stop authenticating immediately. '
              'Stored memory is not deleted.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isRevoking ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isRevoking ? null : _revoke,
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          child: _isRevoking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Revoke'),
        ),
      ],
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String _friendlyError(Object error) {
  final message = error.toString();
  return message.startsWith('Exception: ')
      ? message.substring('Exception: '.length)
      : message;
}
