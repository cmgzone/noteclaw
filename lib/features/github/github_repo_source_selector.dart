import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/github/github_service.dart';
import '../notebook/notebook_provider.dart';
import '../sources/source_provider.dart';
import 'github_provider.dart';

/// Imports a GitHub repo as a new notebook, and repo files as sources.
class GitHubRepoSourceSelector extends ConsumerStatefulWidget {
  final GitHubRepo repo;

  const GitHubRepoSourceSelector({
    super.key,
    required this.repo,
  });

  @override
  ConsumerState<GitHubRepoSourceSelector> createState() =>
      _GitHubRepoSourceSelectorState();
}

class _GitHubRepoSourceSelectorState
    extends ConsumerState<GitHubRepoSourceSelector> {
  bool _isImporting = false;
  String? _error;

  final _maxFilesController = TextEditingController();
  final _maxSizeKbController = TextEditingController();
  final _includeExtController = TextEditingController();
  final _excludeExtController = TextEditingController();

  @override
  void dispose() {
    _maxFilesController.dispose();
    _maxSizeKbController.dispose();
    _includeExtController.dispose();
    _excludeExtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cloud_download_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Text('Import Repo'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRepoCard(scheme),
              const SizedBox(height: 12),
              Text(
                'This will create a new notebook and add repository files as sources (skips binary and very large files).',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              _buildNotebookPreview(scheme),
              const SizedBox(height: 12),
              _buildAdvancedOptions(scheme),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _buildError(scheme, _error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isImporting ? null : _importRepo,
          icon: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.playlist_add, size: 18),
          label: Text(_isImporting ? 'Importing...' : 'Import'),
        ),
      ],
    );
  }

  Widget _buildRepoCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder, color: scheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.repo.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Branch: ${widget.repo.defaultBranch}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotebookPreview(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.book_outlined, color: scheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'New notebook',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.repo.fullName,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedOptions(ColorScheme scheme) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Advanced options',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface.withValues(alpha: 0.9),
        ),
      ),
      children: [
        Text(
          'Defaults: max 200 files, max 200 KB per file.',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _maxFilesController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Max files',
            hintText: 'e.g. 200',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _maxSizeKbController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Max file size (KB)',
            hintText: 'e.g. 200',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _includeExtController,
          decoration: const InputDecoration(
            labelText: 'Include extensions (comma separated)',
            hintText: 'e.g. dart,ts,md',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _excludeExtController,
          decoration: const InputDecoration(
            labelText: 'Exclude extensions (comma separated)',
            hintText: 'e.g. png,jpg,lock',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'If include extensions are provided, exclude list is ignored.',
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildError(ColorScheme scheme, String message) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importRepo() async {
    setState(() {
      _isImporting = true;
      _error = null;
    });

    try {
      final maxFiles = _parseOptionalInt(_maxFilesController);
      final maxSizeKb = _parseOptionalInt(_maxSizeKbController);
      final maxFileSizeBytes = maxSizeKb != null ? maxSizeKb * 1024 : null;
      final includeExtensions = _parseExtensions(_includeExtController);
      final excludeExtensions = _parseExtensions(_excludeExtController);

      final result = await ref.read(githubProvider.notifier).importRepoAsNotebook(
            owner: widget.repo.owner,
            repo: widget.repo.name,
            branch: widget.repo.defaultBranch,
            notebookTitle: widget.repo.fullName,
            notebookDescription: 'Imported from GitHub: ${widget.repo.htmlUrl}',
            notebookCategory: 'GitHub',
            maxFiles: maxFiles,
            maxFileSizeBytes: maxFileSizeBytes,
            includeExtensions: includeExtensions,
            excludeExtensions: excludeExtensions,
          );

      if (!mounted) return;

      if (result == null || result['success'] != true) {
        setState(() {
          _isImporting = false;
          _error = result?['message']?.toString() ?? 'Failed to import repo';
        });
        return;
      }

      await ref.read(notebookProvider.notifier).refresh();
      await ref.read(sourceProvider.notifier).loadSources();

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      final notebook = result['notebook'];
      final notebookId = notebook is Map ? notebook['id']?.toString() : null;
      Navigator.pop(context, notebookId);
      _showSuccessSnackBar(messenger, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _error = e.toString();
        });
      }
    }
  }

  void _showSuccessSnackBar(
      ScaffoldMessengerState messenger, Map<String, dynamic> result) {
    final added = result['addedCount'] ?? 0;
    final skipped = result['skippedCount'] ?? 0;
    final limited = result['limited'] == true;
    final notebook = result['notebook'];
    final title = notebook is Map ? (notebook['title']?.toString() ?? '') : '';

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                limited
                    ? 'Created "$title" and added $added files (skipped $skipped, limit reached)'
                    : 'Created "$title" and added $added files (skipped $skipped)',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

int? _parseOptionalInt(TextEditingController controller) {
  final text = controller.text.trim();
  if (text.isEmpty) return null;
  final value = int.tryParse(text);
  if (value == null || value <= 0) return null;
  return value;
}

List<String>? _parseExtensions(TextEditingController controller) {
  final text = controller.text.trim();
  if (text.isEmpty) return null;
  final items = text
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  return items.isEmpty ? null : items;
}

/// Shows the repo import dialog and returns the created notebookId (if any).
Future<String?> showGitHubRepoSourceSelector(
  BuildContext context, {
  required GitHubRepo repo,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) => GitHubRepoSourceSelector(repo: repo),
  );
  return result;
}

