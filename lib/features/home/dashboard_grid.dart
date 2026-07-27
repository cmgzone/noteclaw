import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../notebook/notebook_provider.dart';
import 'create_notebook_dialog.dart';

class DashboardGrid extends ConsumerWidget {
  const DashboardGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Quick Actions strip ──────────────────────────────────────
            _QuickActionsRow(ref: ref),
            const SizedBox(height: 28),

            // ── Research & AI Agents ─────────────────────────────────────
            const _SectionLabel(label: 'Research & AI'),
            const SizedBox(height: 10),
            _ActionTile(
              icon: LucideIcons.search,
              iconColor: const Color(0xFF7C3AED),
              title: 'Deep Research Agent',
              subtitle: 'Analyze documents, web sources, and synthesize insights',
              onTap: () => context.push('/search'),
            ),
            _ActionTile(
              icon: LucideIcons.terminal,
              iconColor: const Color(0xFFEA580C),
              title: 'Connect AI Agents',
              subtitle: 'Link Codex, Claude, OpenClaw and external MCP agents',
              badge: 'MCP',
              badgeColor: const Color(0xFFEA580C),
              onTap: () => context.push('/agent-connections'),
            ),
            _ActionTile(
              icon: LucideIcons.fileText,
              iconColor: const Color(0xFF059669),
              title: 'Sources Library',
              subtitle: 'Manage imported PDFs, websites, and documents',
              onTap: () => context.push('/sources'),
            ),
            const SizedBox(height: 28),

            // ── Engineering & Dev ────────────────────────────────────────
            const _SectionLabel(label: 'Engineering & Dev'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.code,
                    iconColor: const Color(0xFF0891B2),
                    title: 'Code Review',
                    onTap: () => context.push('/code-review'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.clipboardList,
                    iconColor: const Color(0xFFDB2777),
                    title: 'Projects',
                    onTap: () => context.push('/planning'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.github,
                    iconColor: scheme.onSurfaceVariant,
                    title: 'GitHub',
                    onTap: () => context.push('/github'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Learning & Growth ────────────────────────────────────────
            const _SectionLabel(label: 'Learning & Growth'),
            const SizedBox(height: 10),
            _ActionTile(
              icon: LucideIcons.graduationCap,
              iconColor: const Color(0xFF4F46E5),
              title: 'AI Tutor',
              subtitle: 'Personalized lessons from your notebooks',
              onTap: () {
                final notebooks = ref.read(notebookProvider);
                if (notebooks.isNotEmpty) {
                  context.push('/notebook/${notebooks.first.id}/tutor-sessions');
                } else {
                  showDialog(context: context, builder: (_) => const CreateNotebookDialog());
                }
              },
            ),
            Row(
              children: [
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.layers,
                    iconColor: const Color(0xFF0284C7),
                    title: 'Flashcards',
                    onTap: () {
                      final notebooks = ref.read(notebookProvider);
                      if (notebooks.isNotEmpty) {
                        context.push('/notebook/${notebooks.first.id}/flashcards');
                      } else {
                        showDialog(context: context, builder: (_) => const CreateNotebookDialog());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.checkCircle,
                    iconColor: const Color(0xFFE11D48),
                    title: 'Quizzes',
                    onTap: () {
                      final notebooks = ref.read(notebookProvider);
                      if (notebooks.isNotEmpty) {
                        context.push('/notebook/${notebooks.first.id}/quizzes');
                      } else {
                        showDialog(context: context, builder: (_) => const CreateNotebookDialog());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.languages,
                    iconColor: const Color(0xFF16A34A),
                    title: 'Languages',
                    onTap: () => context.push('/language-learning'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ActionTile(
              icon: LucideIcons.bookOpen,
              iconColor: const Color(0xFF9333EA),
              title: 'Ebook Creator',
              subtitle: 'Turn your notes and sources into a polished ebook',
              onTap: () => context.push('/ebook-creator'),
            ),
            const SizedBox(height: 28),

            // ── Community ────────────────────────────────────────────────
            const _SectionLabel(label: 'Community'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.users,
                    iconColor: const Color(0xFF0D9488),
                    title: 'Social Hub',
                    onTap: () => context.push('/social'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.trophy,
                    iconColor: const Color(0xFFD97706),
                    title: 'Progress',
                    onTap: () => context.push('/progress'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompactTile(
                    icon: LucideIcons.flame,
                    iconColor: const Color(0xFFDC2626),
                    title: 'Challenges',
                    onTap: () => context.push('/daily-challenges'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick actions strip — 4 icon buttons at the top
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionsRow extends StatelessWidget {
  final WidgetRef ref;
  const _QuickActionsRow({required this.ref});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final actions = [
      const _QuickAction(icon: LucideIcons.messageSquare, label: 'Chat', route: '/chat'),
      const _QuickAction(icon: LucideIcons.search, label: 'Research', route: '/search'),
      const _QuickAction(icon: LucideIcons.clipboardList, label: 'Projects', route: '/planning'),
      const _QuickAction(icon: LucideIcons.fileText, label: 'Sources', route: '/sources'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: actions
            .map(
              (a) => _QuickActionButton(
                icon: a.icon,
                label: a.label,
                onTap: () => context.push(a.route),
              ),
            )
            .toList(),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final String route;
  const _QuickAction({required this.icon, required this.label, required this.route});
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 22, color: scheme.primary),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-width action tile with icon, title, subtitle, optional badge
// ─────────────────────────────────────────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isDark
                  ? scheme.surfaceContainer.withValues(alpha: 0.55)
                  : scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (badgeColor ?? iconColor)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                badge!,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: badgeColor ?? iconColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact 3-up tile (icon + label only, used in grids of 3)
// ─────────────────────────────────────────────────────────────────────────────
class _CompactTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  const _CompactTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.surfaceContainer.withValues(alpha: 0.55)
                : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}
