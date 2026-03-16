import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/github/github_service.dart';
import 'github_provider.dart';
import 'github_file_viewer_screen.dart';
import 'github_notebook_selector.dart';
import 'github_repo_source_selector.dart';
import '../notebook/notebook_detail_screen.dart';

class GitHubFileBrowserScreen extends ConsumerStatefulWidget {
  final GitHubRepo repo;
  const GitHubFileBrowserScreen({super.key, required this.repo});
  @override
  ConsumerState<GitHubFileBrowserScreen> createState() =>
      _GitHubFileBrowserScreenState();
}

class _GitHubFileBrowserScreenState
    extends ConsumerState<GitHubFileBrowserScreen> {
  final List<String> _pathStack = [];
  String? get currentPath => _pathStack.isEmpty ? null : _pathStack.join('/');

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(githubProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.repo.name),
            if (currentPath != null)
              Text(currentPath!,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.psychology),
              tooltip: 'AI Analysis',
              onPressed: () => _showAnalysisDialog(context)),
          IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search Code',
              onPressed: () => _showSearchDialog(context)),
          IconButton(
              icon: const Icon(Icons.playlist_add),
              tooltip: 'Import repo as notebook',
              onPressed: () async {
                final navigator = Navigator.of(context);
                final notebookId = await showGitHubRepoSourceSelector(
                  context,
                  repo: widget.repo,
                );
                if (!mounted) return;
                if (notebookId == null || notebookId.isEmpty) return;

                navigator.push(
                  MaterialPageRoute(
                    builder: (context) =>
                        NotebookDetailScreen(notebookId: notebookId),
                  ),
                );
              }),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(GitHubState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(state.error!),
        const SizedBox(height: 16),
        ElevatedButton(
            onPressed: () =>
                ref.read(githubProvider.notifier).selectRepo(widget.repo),
            child: const Text('Retry')),
      ]));
    }
    final items = ref.read(githubProvider.notifier).getItemsAtPath(currentPath);
    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.path.compareTo(b.path);
    });
    return Column(children: [
      _buildBreadcrumb(),
      Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      Icon(Icons.folder_open,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('This folder is empty',
                          style: TextStyle(color: Colors.grey[600])),
                    ]))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _buildFileItem(items[index])))
    ]);
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            InkWell(
                onTap: () => setState(() => _pathStack.clear()),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.home, size: 16),
                  const SizedBox(width: 4),
                  Text(widget.repo.name)
                ])),
            for (int i = 0; i < _pathStack.length; i++) ...[
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right, size: 16)),
              InkWell(
                  onTap: () => setState(
                      () => _pathStack.removeRange(i + 1, _pathStack.length)),
                  child: Text(_pathStack[i],
                      style: TextStyle(
                          fontWeight: i == _pathStack.length - 1
                              ? FontWeight.bold
                              : FontWeight.normal))),
            ],
          ])),
    );
  }

  Widget _buildFileItem(GitHubTreeItem item) {
    final fileName = item.path.split('/').last;
    final icon = item.isDirectory ? Icons.folder : _getFileIcon(fileName);
    final iconColor = item.isDirectory ? Colors.amber : Colors.grey[600];
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(fileName),
      subtitle: item.isDirectory
          ? null
          : Text(_formatFileSize(item.size ?? 0),
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: item.isDirectory
          ? const Icon(Icons.chevron_right)
          : PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _handleFileAction(value, item),
              itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'view',
                    child: Row(children: [
                      Icon(Icons.visibility, size: 20),
                      SizedBox(width: 8),
                      Text('View')
                    ])),
                const PopupMenuItem(
                    value: 'copy_path',
                    child: Row(children: [
                      Icon(Icons.copy, size: 20),
                      SizedBox(width: 8),
                      Text('Copy Path')
                    ])),
                const PopupMenuItem(
                    value: 'add_source',
                    child: Row(children: [
                      Icon(Icons.add_circle_outline, size: 20),
                      SizedBox(width: 8),
                      Text('Add as Source')
                    ])),
              ],
            ),
      onTap: () {
        if (item.isDirectory) {
          setState(() => _pathStack.add(fileName));
        } else {
          _viewFile(item);
        }
      },
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return Icons.flutter_dash;
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return Icons.javascript;
      case 'py':
        return Icons.code;
      case 'java':
      case 'kt':
        return Icons.android;
      case 'swift':
        return Icons.apple;
      case 'json':
      case 'yaml':
      case 'yml':
        return Icons.data_object;
      case 'md':
      case 'txt':
        return Icons.description;
      case 'html':
      case 'css':
        return Icons.web;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _handleFileAction(String action, GitHubTreeItem item) {
    switch (action) {
      case 'view':
        _viewFile(item);
        break;
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: item.path));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Path copied')));
        break;
      case 'add_source':
        showGitHubNotebookSelector(context,
            filePath: item.path,
            owner: widget.repo.owner,
            repo: widget.repo.name,
            branch: widget.repo.defaultBranch);
        break;
    }
  }

  void _viewFile(GitHubTreeItem item) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GitHubFileViewerScreen(
                repo: widget.repo, filePath: item.path)));
  }

  void _showAnalysisDialog(BuildContext context) {
    final focusController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('AI Repository Analysis'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Analyze this repository with AI to understand its structure, patterns, and key components.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: focusController,
                        decoration: const InputDecoration(
                            labelText: 'Focus Area (optional)',
                            hintText: 'e.g., authentication, API design',
                            border: OutlineInputBorder())),
                  ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      _runAnalysis(focusController.text);
                    },
                    child: const Text('Analyze')),
              ],
            ));
  }

  Future<void> _runAnalysis(String focus) async {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Starting AI analysis...')));
    final result = await ref
        .read(githubProvider.notifier)
        .analyzeRepo(focus: focus.isNotEmpty ? focus : null);
    if (result != null && mounted) _showAnalysisResult(result);
  }

  void _showAnalysisResult(Map<String, dynamic> result) {
    final aiAvailable = result['aiAnalysisAvailable'] ?? true;
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Row(children: [
                const Text('Analysis Result'),
                if (!aiAvailable) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                      message: 'AI analysis unavailable',
                      child: Icon(Icons.info_outline,
                          size: 20, color: Colors.orange[700]))
                ]
              ]),
              content: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    if (!aiAvailable)
                      Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange[300]!)),
                          child: Row(children: [
                            Icon(Icons.warning_amber,
                                color: Colors.orange[700]),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    'AI analysis unavailable. Showing basic info.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange[900])))
                          ])),
                    if (result['summary'] != null) ...[
                      const Text('Summary',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(result['summary']),
                      const SizedBox(height: 16)
                    ],
                    if (result['analysis'] != null) ...[
                      const Text('Analysis',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(result['analysis']),
                      const SizedBox(height: 16)
                    ],
                    if (result['technologies'] != null) ...[
                      const Text('Technologies',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: (result['technologies'] as List)
                              .map((t) => Chip(label: Text(t.toString())))
                              .toList()),
                      const SizedBox(height: 16)
                    ],
                    if (result['recommendations'] != null) ...[
                      const Text('Recommendations',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...((result['recommendations'] as List).map((r) =>
                          Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• '),
                                    Expanded(child: Text(r.toString()))
                                  ]))))
                    ],
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
            ));
  }

  void _showSearchDialog(BuildContext context) {
    final searchController = TextEditingController();
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Search Code'),
              content: TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                      labelText: 'Search query',
                      hintText: 'e.g., function name, class',
                      border: OutlineInputBorder()),
                  autofocus: true,
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      Navigator.pop(context);
                      _runSearch(value);
                    }
                  }),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () {
                      if (searchController.text.isNotEmpty) {
                        Navigator.pop(context);
                        _runSearch(searchController.text);
                      }
                    },
                    child: const Text('Search')),
              ],
            ));
  }

  Future<void> _runSearch(String query) async {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Searching for "$query"...')));
    final results = await ref.read(githubProvider.notifier).searchCode(query);
    if (mounted) {
      if (results.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No results found')));
      } else {
        _showSearchResults(query, results);
      }
    }
  }

  void _showSearchResults(String query, List<Map<String, dynamic>> results) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Results for "$query" (${results.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return ListTile(
                      leading: const Icon(Icons.code),
                      title: Text(result['path'] ?? 'Unknown'),
                      subtitle: result['text_matches'] != null
                          ? Text(
                              (result['text_matches'] as List).isNotEmpty
                                  ? (result['text_matches'][0]['fragment'] ??
                                      '')
                                  : '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GitHubFileViewerScreen(
                              repo: widget.repo,
                              filePath: result['path'] ?? '',
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
