import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'app_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'agent_notebook_badge.dart';

class NotebookCard extends StatelessWidget {
  const NotebookCard({
    super.key,
    required this.title,
    required this.sourceCount,
    required this.notebookId,
    this.coverImage,
    this.onPlay,
    this.onCoverTap,
    this.isAgentNotebook = false,
    this.agentName,
    this.agentStatus = 'active',
  });

  final String title;
  final int sourceCount;
  final String notebookId;
  final String? coverImage;
  final VoidCallback? onPlay;
  final VoidCallback? onCoverTap;
  final bool isAgentNotebook;
  final String? agentName;
  final String agentStatus;

  // Helper to generate a consistent gradient based on notebook ID
  List<Color> _getGradient(ColorScheme scheme) {
    final int hash = notebookId.hashCode;
    final gradients = [
      [scheme.primary, scheme.tertiary],
      [scheme.secondary, scheme.primary],
      [Colors.blueAccent, Colors.purpleAccent],
      [Colors.orangeAccent, Colors.deepOrange],
      [Colors.teal, Colors.greenAccent],
      [Colors.indigo, Colors.pinkAccent],
    ];
    final selection = gradients[hash.abs() % gradients.length];
    return [
      selection[0].withValues(alpha: 0.8),
      selection[1].withValues(alpha: 0.6),
    ];
  }

  Widget? _buildCoverImage(BuildContext context) {
    if (coverImage == null || coverImage!.isEmpty) return null;

    try {
      if (coverImage!.startsWith('data:image/svg+xml')) {
        return null;
      } else if (coverImage!.startsWith('data:')) {
        final base64Data = coverImage!.split(',').last;
        return Image.memory(
          base64Decode(base64Data),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _buildPlaceholder(context),
        );
      } else if (coverImage!.startsWith('http')) {
        return AppNetworkImage(
          imageUrl: coverImage!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          placeholder: (_) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_) => _buildPlaceholder(context),
        );
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  Widget _buildPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _getGradient(scheme),
        ),
      ),
      child: Center(
        child: Icon(
          LucideIcons.book,
          size: 48,
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coverWidget = _buildCoverImage(context);
    final hasCover = coverWidget != null;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/notebook/$notebookId'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Section: Cover or Gradient
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasCover) coverWidget else _buildPlaceholder(context),
                  
                  // Play button overlay
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: IconButton(
                        onPressed: onPlay ?? () => _showAudioPreview(context),
                        icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                        tooltip: 'Play Audio Overview',
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ).animate().fadeIn(),
                ],
              ),
            ),
            
            // Bottom Section: Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Title
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                    ),
                    
                    // Metadata Row
                    Row(
                      children: [
                        // Source Count Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: scheme.outline.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.files, size: 10, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 2),
                              Text(
                                '$sourceCount',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const Spacer(),
                        
                        if (isAgentNotebook && agentName != null) ...[
                          AgentNotebookBadge(
                            agentName: agentName!,
                            status: agentStatus,
                            compact: true,
                          ),
                        ] else ...[
                          // AI Label
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome, 
                                  size: 8, 
                                  color: scheme.onPrimaryContainer
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'AI',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAudioPreview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Audio Overview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'Generate an AI-powered audio summary of "$title"',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.go('/studio');
              },
              icon: const Icon(Icons.mic_none),
              label: const Text('Generate Audio'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
