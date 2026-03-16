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
    // Industrial Dashboard Layout
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Research & Analysis',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ).animate().fadeIn().slideX(),
            const SizedBox(height: 12),
            
            // 1. Deep Research (Top Priority)
            _BentoCard(
              title: 'Deep Research Agent',
              subtitle: 'Analyze huge documents and web sources',
              icon: LucideIcons.search,
              color: const Color(0xFF8B5CF6), // Violet
              onTap: () => context.push('/search'),
              height: 140,
              isWide: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BentoCard(
                    title: 'AI Browser',
                    subtitle: 'Browse pages with AI help',
                    icon: LucideIcons.globe,
                    color: const Color(0xFF60A5FA), // Blue 400
                    onTap: () => context.push('/ai-browser'),
                    height: 120,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BentoCard(
                    title: 'Sources',
                    subtitle: 'Manage your imported content',
                    icon: LucideIcons.fileText,
                    color: const Color(0xFF34D399), // Emerald 400
                    onTap: () => context.push('/sources'),
                    height: 120,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Engineering & Development',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ).animate().fadeIn().slideX(delay: 100.ms),
            const SizedBox(height: 12),

            // 2. Coding Tools Section
            Row(
              children: [
                Expanded(
                  child: _BentoCard(
                    title: 'Code Review',
                    subtitle: 'AI-powered code analysis',
                    icon: LucideIcons.code,
                    color: const Color(0xFF22D3EE), // Cyan
                    onTap: () => context.push('/code-review'),
                    height: 140,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BentoCard(
                    title: 'Architecture Plan',
                    subtitle: 'Design & structure projects',
                    icon: LucideIcons.clipboardList,
                    color: const Color(0xFFF472B6), // Pink 400
                    onTap: () => context.push('/planning'),
                    height: 140,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BentoCard(
                    title: 'GitHub',
                    subtitle: 'Connect repos and browse projects',
                    icon: LucideIcons.github,
                    color: const Color(0xFF94A3B8), // Slate 400
                    onTap: () => context.push('/github'),
                    height: 120,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BentoCard(
                    title: 'Studio',
                    subtitle: 'Generate and review AI artifacts',
                    icon: LucideIcons.palette,
                    color: const Color(0xFFF59E0B), // Amber 500
                    onTap: () => context.push('/studio'),
                    height: 120,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 24),

            Text(
              'Learning & Growth',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ).animate().fadeIn().slideX(delay: 200.ms),
            const SizedBox(height: 12),

            // 3. Learning Section
            Row(
              children: [
                Expanded(
                  child: _BentoCard(
                    title: 'Ai Tutor',
                    subtitle: 'Master any subject',
                    icon: LucideIcons.graduationCap,
                    color: const Color(0xFF6366F1), // Indigo
                    onTap: () {
                      final notebooks = ref.read(notebookProvider);
                      if (notebooks.isNotEmpty) {
                        final id = notebooks.first.id;
                        context.push('/notebook/$id/tutor-sessions');
                      } else {
                        showDialog(
                          context: context,
                          builder: (_) => const CreateNotebookDialog(),
                        );
                      }
                    },
                    height: 120,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BentoCard(
                    title: 'Wellness AI',
                    subtitle: 'Mental health & balance',
                    icon: LucideIcons.heartHandshake,
                    color: const Color(0xFFEC4899), // Pink
                    onTap: () => context.push('/wellness'),
                    height: 120,
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BentoCard(
                    title: 'Flashcards',
                    subtitle: 'Study with spaced repetition',
                    icon: LucideIcons.layers,
                    color: const Color(0xFF0EA5E9), // Sky 500
                    onTap: () {
                      final notebooks = ref.read(notebookProvider);
                      if (notebooks.isNotEmpty) {
                        final id = notebooks.first.id;
                        context.push('/notebook/$id/flashcards');
                      } else {
                        showDialog(
                          context: context,
                          builder: (_) => const CreateNotebookDialog(),
                        );
                      }
                    },
                    height: 120,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BentoCard(
                    title: 'Quizzes',
                    subtitle: 'Test your knowledge quickly',
                    icon: LucideIcons.checkCircle,
                    color: const Color(0xFFFB7185), // Rose 400
                    onTap: () {
                      final notebooks = ref.read(notebookProvider);
                      if (notebooks.isNotEmpty) {
                        final id = notebooks.first.id;
                        context.push('/notebook/$id/quizzes');
                      } else {
                        showDialog(
                          context: context,
                          builder: (_) => const CreateNotebookDialog(),
                        );
                      }
                    },
                    height: 120,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BentoCard(
                    title: 'Language Learning',
                    subtitle: 'Practice daily sessions',
                    icon: LucideIcons.languages,
                    color: const Color(0xFF22C55E), // Green 500
                    onTap: () => context.push('/language-learning'),
                    height: 120,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BentoCard(
                    title: 'Ebook Creator',
                    subtitle: 'Turn notes into ebooks',
                    icon: LucideIcons.bookOpen,
                    color: const Color(0xFFA855F7), // Purple 500
                    onTap: () => context.push('/ebook-creator'),
                    height: 120,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Community & Insights',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ).animate().fadeIn().slideX(delay: 300.ms),
            const SizedBox(height: 12),

            // 4. Community Section
            Row(
              children: [
                Expanded(
                  child: _BentoCard(
                    title: 'Social Hub',
                    icon: LucideIcons.users,
                    color: const Color(0xFF10B981), // Emerald
                    onTap: () => context.push('/social'),
                    height: 100,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BentoCard(
                    title: 'Progress Stats',
                    icon: LucideIcons.trophy,
                    color: const Color(0xFFFBBF24), // Amber
                    onTap: () => context.push('/progress'),
                    height: 100,
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _BentoCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double height;
  final bool compact;
  final bool isWide;

  const _BentoCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.height = 160,
    this.compact = false,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: isDark
                ? scheme.surfaceContainer.withValues(alpha: 0.6)
                : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                // Decorative Gradient Blob
                Positioned(
                  right: -20,
                  top: -20,
                  child: Container(
                    width: compact ? 80 : 120,
                    height: compact ? 80 : 120,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          color.withValues(alpha: 0.3),
                          color.withValues(alpha: 0.0),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

                // Content: icon + title/subtitle
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(compact ? 12 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        // Icon
                        Container(
                          padding: EdgeInsets.all(compact ? 8 : 12),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(compact ? 12 : 16),
                          ),
                          child:
                              Icon(icon, color: color, size: compact ? 20 : 24),
                        ),

                        // Text - pushed to bottom by spaceBetween
                        Flexible(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // These cards can get very short in some responsive breakpoints,
                              // so only show the subtitle when there is enough vertical space.
                              final canShowSubtitle = subtitle != null &&
                                  !compact &&
                                  constraints.maxHeight >= 44;
                              final subtitleMaxLines =
                                  constraints.maxHeight >= 58 ? 2 : 1;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: compact ? 13 : 16,
                                          height: 1.1,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (canShowSubtitle) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 12,
                                            height: 1.1,
                                          ),
                                      maxLines: subtitleMaxLines,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().scale(duration: 400.ms, curve: Curves.easeOut);
  }
}
