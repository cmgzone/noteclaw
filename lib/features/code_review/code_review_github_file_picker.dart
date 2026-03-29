import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_service.dart';
import '../../core/github/github_service.dart';

class GitHubReviewFileSelection {
  final GitHubRepo repo;
  final String branch;
  final String path;
  final String content;
  final String language;

  const GitHubReviewFileSelection({
    required this.repo,
    required this.branch,
    required this.path,
    required this.content,
    required this.language,
  });
}

Future<GitHubReviewFileSelection?> showGitHubReviewFilePicker(
  BuildContext context, {
  String? initialOwner,
  String? initialRepo,
  String? initialBranch,
}) {
  return showDialog<GitHubReviewFileSelection>(
    context: context,
    builder: (context) => _GitHubReviewFilePickerDialog(
      initialOwner: initialOwner,
      initialRepo: initialRepo,
      initialBranch: initialBranch,
    ),
  );
}

class _GitHubReviewFilePickerDialog extends ConsumerStatefulWidget {
  final String? initialOwner;
  final String? initialRepo;
  final String? initialBranch;

  const _GitHubReviewFilePickerDialog({
    this.initialOwner,
    this.initialRepo,
    this.initialBranch,
  });

  @override
  ConsumerState<_GitHubReviewFilePickerDialog> createState() =>
      _GitHubReviewFilePickerDialogState();
}

class _GitHubReviewFilePickerDialogState
    extends ConsumerState<_GitHubReviewFilePickerDialog> {
  static const Map<String, String> _languageByExtension = {
    'dart': 'dart',
    'js': 'javascript',
    'jsx': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'py': 'python',
    'java': 'java',
    'kt': 'kotlin',
    'swift': 'swift',
    'go': 'go',
    'rs': 'rust',
    'c': 'c',
    'cc': 'cpp',
    'cpp': 'cpp',
    'cxx': 'cpp',
    'cs': 'csharp',
    'php': 'php',
    'rb': 'ruby',
    'sql': 'sql',
  };

  final TextEditingController _branchController = TextEditingController();
  final List<String> _pathStack = <String>[];

  List<GitHubRepo> _repos = const <GitHubRepo>[];
  List<GitHubTreeItem> _tree = const <GitHubTreeItem>[];
  GitHubRepo? _selectedRepo;

  bool _isLoadingRepos = true;
  bool _isLoadingTree = false;
  bool _isLoadingFile = false;
  String? _error;

  GitHubService get _githubService =>
      GitHubService(ref.read(apiServiceProvider));

  String? get _currentBranch {
    final branch = _branchController.text.trim();
    return branch.isEmpty ? null : branch;
  }

  String? get _currentPath => _pathStack.isEmpty ? null : _pathStack.join('/');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRepos();
    });
  }

  @override
  void dispose() {
    _branchController.dispose();
    super.dispose();
  }

  Future<void> _loadRepos() async {
    setState(() {
      _isLoadingRepos = true;
      _error = null;
    });

    try {
      final repos = await _githubService.listRepos(perPage: 100);
      repos.sort((a, b) => a.fullName.compareTo(b.fullName));

      GitHubRepo? initialRepo;
      if (widget.initialOwner != null && widget.initialRepo != null) {
        for (final repo in repos) {
          if (repo.owner == widget.initialOwner &&
              repo.name == widget.initialRepo) {
            initialRepo = repo;
            break;
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _repos = repos;
        _isLoadingRepos = false;
      });

      if (initialRepo != null) {
        await _selectRepo(
          initialRepo,
          branchOverride: widget.initialBranch,
        );
      } else if (repos.length == 1) {
        await _selectRepo(repos.first);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingRepos = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectRepo(
    GitHubRepo repo, {
    String? branchOverride,
  }) async {
    setState(() {
      _selectedRepo = repo;
      _tree = const <GitHubTreeItem>[];
      _pathStack.clear();
      _branchController.text =
          (branchOverride != null && branchOverride.trim().isNotEmpty)
              ? branchOverride.trim()
              : repo.defaultBranch;
    });

    await _loadTree();
  }

  Future<void> _loadTree() async {
    final repo = _selectedRepo;
    if (repo == null) {
      return;
    }

    setState(() {
      _isLoadingTree = true;
      _error = null;
      _tree = const <GitHubTreeItem>[];
      _pathStack.clear();
    });

    try {
      final tree = await _githubService.getRepoTree(
        repo.owner,
        repo.name,
        branch: _currentBranch,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _tree = tree;
        _isLoadingTree = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingTree = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _useFile(GitHubTreeItem item) async {
    final repo = _selectedRepo;
    if (repo == null) {
      return;
    }

    final language = _languageFromPath(item.path);
    if (language == null) {
      setState(() {
        _error = 'This file type is not supported for code review.';
      });
      return;
    }

    setState(() {
      _isLoadingFile = true;
      _error = null;
    });

    try {
      final file = await _githubService.getFileContent(
        repo.owner,
        repo.name,
        item.path,
        branch: _currentBranch,
      );

      final content = file.content?.trimRight();
      if (content == null || content.isEmpty) {
        throw Exception('This file could not be loaded or is empty.');
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        GitHubReviewFileSelection(
          repo: repo,
          branch: _currentBranch ?? repo.defaultBranch,
          path: item.path,
          content: content,
          language: language,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingFile = false;
        _error = e.toString();
      });
    }
  }

  List<GitHubTreeItem> _visibleItems() {
    final currentPath = _currentPath;
    final items = _tree.where((item) {
      if (currentPath == null || currentPath.isEmpty) {
        return !item.path.contains('/');
      }

      final prefix = '$currentPath/';
      if (!item.path.startsWith(prefix)) {
        return false;
      }

      final remaining = item.path.substring(prefix.length);
      return !remaining.contains('/');
    }).where((item) {
      if (item.isDirectory) {
        return true;
      }
      return _languageFromPath(item.path) != null;
    }).toList();

    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) {
        return -1;
      }
      if (!a.isDirectory && b.isDirectory) {
        return 1;
      }
      return a.path.compareTo(b.path);
    });

    return items;
  }

  String? _languageFromPath(String path) {
    final name = path.split('/').last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return null;
    }

    final ext = name.substring(dotIndex + 1).toLowerCase();
    return _languageByExtension[ext];
  }

  IconData _iconForItem(GitHubTreeItem item) {
    if (item.isDirectory) {
      return Icons.folder;
    }

    switch (_languageFromPath(item.path)) {
      case 'dart':
        return Icons.flutter_dash;
      case 'javascript':
      case 'typescript':
        return Icons.javascript;
      case 'python':
        return Icons.code;
      case 'java':
      case 'kotlin':
        return Icons.android;
      case 'swift':
        return Icons.apple;
      case 'sql':
        return Icons.storage;
      default:
        return Icons.description_outlined;
    }
  }

  String _formatFileSize(int? bytes) {
    final value = bytes ?? 0;
    if (value < 1024) {
      return '$value B';
    }
    if (value < 1024 * 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _visibleItems();

    return AlertDialog(
      title: const Text('Load From GitHub'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a connected repository file to load directly into Code Review.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoadingRepos)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedRepo?.id.isNotEmpty == true
                    ? _selectedRepo!.id
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Repository',
                  border: OutlineInputBorder(),
                ),
                items: _repos.map((repo) {
                  return DropdownMenuItem<String>(
                    value: repo.id,
                    child: Text(repo.fullName, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _isLoadingTree || _isLoadingFile
                    ? null
                    : (repoId) {
                        if (repoId == null) {
                          return;
                        }
                        final repo =
                            _repos.where((item) => item.id == repoId).first;
                        _selectRepo(repo);
                      },
              ),
              if (_repos.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'No repositories were returned for this GitHub connection.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_selectedRepo != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _branchController,
                        decoration: InputDecoration(
                          labelText: 'Branch',
                          hintText: _selectedRepo!.defaultBranch,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: 'Reload branch',
                            onPressed: (_isLoadingTree || _isLoadingFile)
                                ? null
                                : _loadTree,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                        onSubmitted: (_) => _loadTree(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildBreadcrumb(theme),
                const SizedBox(height: 8),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isLoadingTree
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : items.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No reviewable files found in this folder.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final fileName = item.path.split('/').last;
                                final language = _languageFromPath(item.path);

                                return ListTile(
                                  enabled: !_isLoadingFile,
                                  leading: Icon(
                                    _iconForItem(item),
                                    color: item.isDirectory
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  title: Text(fileName),
                                  subtitle: item.isDirectory
                                      ? null
                                      : Text(
                                          '$language - ${_formatFileSize(item.size)}',
                                        ),
                                  trailing: item.isDirectory
                                      ? const Icon(Icons.chevron_right)
                                      : _isLoadingFile
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons
                                              .download_for_offline_outlined),
                                  onTap: item.isDirectory
                                      ? () {
                                          setState(() {
                                            _pathStack.add(fileName);
                                          });
                                        }
                                      : () => _useFile(item),
                                );
                              },
                            ),
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoadingFile ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildBreadcrumb(ThemeData theme) {
    final chips = <Widget>[
      InkWell(
        onTap: () {
          setState(() {
            _pathStack.clear();
          });
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.home, size: 16),
            SizedBox(width: 4),
            Text('Repo root'),
          ],
        ),
      ),
    ];

    for (var index = 0; index < _pathStack.length; index++) {
      chips.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.chevron_right, size: 16),
      ));
      chips.add(
        InkWell(
          onTap: () {
            setState(() {
              _pathStack.removeRange(index + 1, _pathStack.length);
            });
          },
          child: Text(
            _pathStack[index],
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: index == _pathStack.length - 1
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }
}
