import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/auth/custom_auth_service.dart';
import '../../core/theme/theme_provider.dart';
import '../../ui/digital_librarian.dart';
import '../subscription/widgets/subscription_overview.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    final user = ref.read(legacyUserProvider);
    if (user == null ||
        _passwordController.text.isEmpty ||
        _confirmationController.text != 'DELETE') {
      return;
    }

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref
          .read(customAuthServiceProvider)
          .deleteAccount(user.uid, _passwordController.text);
      await ref.read(customAuthStateProvider.notifier).signOut();
      if (mounted) context.go('/login');
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(legacyUserProvider);
    final canDelete = !_deleting &&
        _passwordController.text.isNotEmpty &&
        _confirmationController.text == 'DELETE';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: const NoteClawHeader(
          compact: true,
          eyebrow: 'Account & settings',
        ),
      ),
      bottomNavigationBar: const MemoryNavigationBar(
        selected: MemoryDestination.settings,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            LucideIcons.user,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your NoteClaw account',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                user?.email ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SubscriptionOverviewCard(),
                  const SizedBox(height: 18),
                  DigitalLibrarianPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(LucideIcons.github, size: 19),
                          title: const Text(
                            'GitHub connection',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Repositories, sources and code review',
                          ),
                          trailing:
                              const Icon(LucideIcons.chevronRight, size: 17),
                          onTap: () => context.push('/github'),
                        ),
                        Divider(height: 1, color: scheme.outlineVariant),
                        ListTile(
                          leading:
                              const Icon(LucideIcons.shieldCheck, size: 19),
                          title: const Text(
                            'Agent access',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'MCP tokens and topic permissions',
                          ),
                          trailing:
                              const Icon(LucideIcons.chevronRight, size: 17),
                          onTap: () => context.go('/agents'),
                        ),
                        Divider(height: 1, color: scheme.outlineVariant),
                        SwitchListTile(
                          secondary: const Icon(LucideIcons.moon, size: 19),
                          title: const Text(
                            'Digital Librarian theme',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Use the dark command-center appearance',
                          ),
                          value: ref.watch(themeModeProvider) == ThemeMode.dark,
                          onChanged: (enabled) {
                            final notifier =
                                ref.read(themeModeProvider.notifier);
                            if (enabled) {
                              notifier.setDark();
                            } else {
                              notifier.setLight();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: scheme.error.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.alertTriangle,
                              color: scheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Delete account',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'This permanently deletes the account, API tokens, '
                          'agent sessions, topic notebooks, memories, and sources. '
                          'It cannot be undone.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Current password',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmationController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Type DELETE to confirm',
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: TextStyle(color: scheme.error, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: canDelete ? _deleteAccount : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError,
                            ),
                            icon: _deleting
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.trash2, size: 17),
                            label: const Text('Delete my account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
