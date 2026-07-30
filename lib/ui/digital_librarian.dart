import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Shared UI primitives translated from the NoteClaw Stitch project.
///
/// The visual language intentionally favors compact, information-dense
/// surfaces, thin borders and monospace metadata over decorative cards.
abstract final class DigitalLibrarian {
  static const background = Color(0xFF020617);
  static const surface = Color(0xFF0B1326);
  static const surfaceLowest = Color(0xFF060E20);
  static const surfaceLow = Color(0xFF131B2E);
  static const surfaceContainer = Color(0xFF171F33);
  static const surfaceHigh = Color(0xFF222A3D);
  static const surfaceHighest = Color(0xFF2D3449);
  static const outline = Color(0xFF424754);
  static const primary = Color(0xFFADC6FF);
  static const primaryStrong = Color(0xFF4D8EFF);
  static const secondary = Color(0xFF4EDEA3);
  static const tertiary = Color(0xFFD0BCFF);

  static const memoryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryStrong, Color(0xFF00A572)],
  );
}

class NoteClawHeader extends StatelessWidget {
  const NoteClawHeader({
    super.key,
    this.eyebrow,
    this.compact = false,
  });

  final String? eyebrow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 28 : 34,
          height: compact ? 28 : 34,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: DigitalLibrarian.surfaceHighest,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: DigitalLibrarian.secondary.withValues(alpha: 0.42),
            ),
          ),
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              LucideIcons.brainCircuit,
              size: 18,
              color: DigitalLibrarian.secondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NoteClaw',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            if (eyebrow != null)
              Text(
                eyebrow!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: DigitalLibrarian.secondary,
                  fontSize: 9,
                  letterSpacing: 0.9,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class TechnicalLabel extends StatelessWidget {
  const TechnicalLabel(
    this.label, {
    super.key,
    this.color,
    this.trailing,
  });

  final String label;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
          ),
    );
    if (trailing == null) return text;
    return Row(
      children: [
        Expanded(child: text),
        trailing!,
      ],
    );
  }
}

class DigitalLibrarianPanel extends StatelessWidget {
  const DigitalLibrarianPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor ??
              Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.025),
            blurRadius: 0,
            offset: const Offset(-1, -1),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: panel,
      ),
    );
  }
}

class LiveStatus extends StatelessWidget {
  const LiveStatus({
    super.key,
    required this.label,
    this.active = true,
    this.compact = false,
  });

  final String label;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? DigitalLibrarian.secondary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 6 : 8,
          height: compact ? 6 : 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.42),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

enum MemoryDestination { memory, agents, chat, planning, settings }

class MemoryNavigationBar extends StatelessWidget {
  const MemoryNavigationBar({
    super.key,
    required this.selected,
  });

  final MemoryDestination selected;

  static const _routes = [
    '/home',
    '/agents',
    '/memory-chat',
    '/planning',
    '/settings/account'
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      height: 64,
      selectedIndex: selected.index,
      onDestinationSelected: (index) => context.go(_routes[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(LucideIcons.bookOpen, size: 19),
          selectedIcon: Icon(LucideIcons.bookOpenCheck, size: 19),
          label: 'Memory',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.network, size: 19),
          selectedIcon: Icon(LucideIcons.workflow, size: 19),
          label: 'Agents',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.messagesSquare, size: 19),
          selectedIcon: Icon(LucideIcons.messageSquare, size: 19),
          label: 'Chat',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.clipboardList, size: 19),
          selectedIcon: Icon(LucideIcons.listChecks, size: 19),
          label: 'Plan',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.settings, size: 19),
          selectedIcon: Icon(LucideIcons.settings2, size: 19),
          label: 'Settings',
        ),
      ],
    );
  }
}

enum MemoryToolDestination { notebook, factCheck, codeReview, vault }

class MemoryToolNavigationBar extends StatelessWidget {
  const MemoryToolNavigationBar({
    super.key,
    required this.selected,
  });

  final MemoryToolDestination selected;

  static const _routes = [
    '/home',
    '/fact-check',
    '/code-review',
    '/memory-chat',
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      height: 64,
      selectedIndex: selected.index,
      onDestinationSelected: (index) => context.go(_routes[index]),
      destinations: const [
        NavigationDestination(
          icon: Icon(LucideIcons.database, size: 19),
          label: 'Notebook',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.badgeCheck, size: 19),
          label: 'Fact Check',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.code2, size: 19),
          label: 'Code Review',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.lock, size: 19),
          label: 'Vault',
        ),
      ],
    );
  }
}

String relativeMemoryTime(DateTime? date) {
  if (date == null) return 'No activity';
  final difference = DateTime.now().difference(date.toLocal());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${date.toLocal().month}/${date.toLocal().day}/${date.toLocal().year}';
}
