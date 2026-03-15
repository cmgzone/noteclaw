import 'package:flutter/foundation.dart';
import '../api/api_service.dart';

/// GitHub repository model
class GitHubRepo {
  final String id;
  final String fullName;
  final String name;
  final String owner;
  final String? description;
  final String defaultBranch;
  final bool isPrivate;
  final bool isFork;
  final String? language;
  final int starsCount;
  final int forksCount;
  final int sizeKb;
  final String htmlUrl;

  GitHubRepo({
    required this.id,
    required this.fullName,
    required this.name,
    required this.owner,
    this.description,
    required this.defaultBranch,
    required this.isPrivate,
    required this.isFork,
    this.language,
    required this.starsCount,
    required this.forksCount,
    required this.sizeKb,
    required this.htmlUrl,
  });

  factory GitHubRepo.fromJson(Map<String, dynamic> json) {
    return GitHubRepo(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName'] ?? json['full_name'] ?? '',
      name: json['name'] ?? '',
      owner: json['owner'] ?? '',
      description: json['description'],
      defaultBranch: json['defaultBranch'] ?? json['default_branch'] ?? 'main',
      isPrivate: json['isPrivate'] ?? json['is_private'] ?? false,
      isFork: json['isFork'] ?? json['is_fork'] ?? false,
      language: json['language'],
      starsCount: json['starsCount'] ?? json['stars_count'] ?? 0,
      forksCount: json['forksCount'] ?? json['forks_count'] ?? 0,
      sizeKb: json['sizeKb'] ?? json['size_kb'] ?? 0,
      htmlUrl: json['htmlUrl'] ?? json['html_url'] ?? '',
    );
  }
}

/// GitHub file tree item
class GitHubTreeItem {
  final String path;
  final String type; // 'blob' or 'tree'
  final String sha;
  final int? size;

  GitHubTreeItem({
    required this.path,
    required this.type,
    required this.sha,
    this.size,
  });

  bool get isFile => type == 'blob';
  bool get isDirectory => type == 'tree';

  factory GitHubTreeItem.fromJson(Map<String, dynamic> json) {
    return GitHubTreeItem(
      path: json['path'] ?? '',
      type: json['type'] ?? 'blob',
      sha: json['sha'] ?? '',
      size: json['size'],
    );
  }
}

/// GitHub file content
class GitHubFile {
  final String name;
  final String path;
  final String sha;
  final int size;
  final String? content;
  final String? downloadUrl;

  GitHubFile({
    required this.name,
    required this.path,
    required this.sha,
    required this.size,
    this.content,
    this.downloadUrl,
  });

  factory GitHubFile.fromJson(Map<String, dynamic> json) {
    return GitHubFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      sha: json['sha'] ?? '',
      size: json['size'] ?? 0,
      content: json['content'],
      downloadUrl: json['downloadUrl'] ?? json['download_url'],
    );
  }
}

/// GitHub connection status
class GitHubConnection {
  final bool connected;
  final String? username;
  final String? email;
  final String? avatarUrl;
  final List<String> scopes;
  final DateTime? connectedAt;
  final DateTime? lastUsedAt;

  GitHubConnection({
    required this.connected,
    this.username,
    this.email,
    this.avatarUrl,
    this.scopes = const [],
    this.connectedAt,
    this.lastUsedAt,
  });

  factory GitHubConnection.fromJson(Map<String, dynamic> json) {
    final connection = json['connection'];
    return GitHubConnection(
      connected: json['connected'] ?? false,
      username: connection?['username'],
      email: connection?['email'],
      avatarUrl: connection?['avatarUrl'],
      scopes: List<String>.from(connection?['scopes'] ?? []),
      connectedAt: connection?['connectedAt'] != null
          ? DateTime.tryParse(connection['connectedAt'])
          : null,
      lastUsedAt: connection?['lastUsedAt'] != null
          ? DateTime.tryParse(connection['lastUsedAt'])
          : null,
    );
  }
}

/// GitHub Service for mobile app
class GitHubService {
  final ApiService _api;

  GitHubService(this._api);

  /// Check GitHub connection status
  Future<GitHubConnection> getStatus() async {
    try {
      final response = await _api.get('/github/status');
      return GitHubConnection.fromJson(response);
    } catch (e) {
      debugPrint('GitHub status error: $e');
      return GitHubConnection(connected: false);
    }
  }

  /// Connect GitHub using Personal Access Token
  Future<GitHubConnection> connectWithToken(String token) async {
    final response = await _api.post('/github/connect', {
      'token': token,
    });
    return GitHubConnection(
      connected: true,
      username: response['connection']?['username'],
      email: response['connection']?['email'],
      avatarUrl: response['connection']?['avatarUrl'],
      scopes: List<String>.from(response['connection']?['scopes'] ?? []),
    );
  }

  /// Disconnect GitHub account
  Future<void> disconnect() async {
    await _api.delete('/github/disconnect');
  }

  /// Get OAuth authorization URL
  Future<String> getAuthUrl() async {
    final response = await _api.get('/github/auth-url');
    return response['authUrl'] ?? '';
  }

  /// List repositories
  Future<List<GitHubRepo>> listRepos({
    String type = 'all',
    String sort = 'updated',
    int perPage = 30,
    int page = 1,
  }) async {
    final response = await _api.get(
      '/github/repos?type=$type&sort=$sort&perPage=$perPage&page=$page',
    );

    final repos = response['repos'] as List? ?? [];
    return repos.map((r) => GitHubRepo.fromJson(r)).toList();
  }

  /// Get repository file tree
  Future<List<GitHubTreeItem>> getRepoTree(
    String owner,
    String repo, {
    String? branch,
  }) async {
    String url = '/github/repos/$owner/$repo/tree';
    if (branch != null) {
      url += '?branch=$branch';
    }

    final response = await _api.get(url);
    final tree = response['tree'] as List? ?? [];
    return tree.map((t) => GitHubTreeItem.fromJson(t)).toList();
  }

  /// Get file contents
  Future<GitHubFile> getFileContent(
    String owner,
    String repo,
    String path, {
    String? branch,
  }) async {
    // Ensure path doesn't start with slash
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;

    String url = '/github/repos/$owner/$repo/contents/$cleanPath';
    if (branch != null) {
      url += '?branch=${Uri.encodeComponent(branch)}';
    }

    try {
      final response = await _api.get(url);
      if (response['success'] == false) {
        throw Exception(response['message'] ?? 'Failed to fetch file content');
      }
      return GitHubFile.fromJson(response['file']);
    } catch (e) {
      debugPrint('Error fetching file content: $e');
      debugPrint('URL: $url');
      rethrow;
    }
  }

  /// Get repository README
  Future<String?> getReadme(String owner, String repo) async {
    try {
      final response = await _api.get('/github/repos/$owner/$repo/readme');
      return response['readme'];
    } catch (e) {
      return null;
    }
  }

  /// Search code
  Future<List<Map<String, dynamic>>> searchCode(
    String query, {
    String? repo,
    String? language,
    String? path,
    int perPage = 20,
  }) async {
    final params = <String, String>{
      'q': query,
      if (repo != null) 'repo': repo,
      if (language != null) 'language': language,
      if (path != null) 'path': path,
      'perPage': perPage.toString(),
    };

    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final response = await _api.get('/github/search?$queryString');
    return List<Map<String, dynamic>>.from(response['results'] ?? []);
  }

  /// Add GitHub file as source to notebook
  Future<Map<String, dynamic>> addAsSource({
    required String notebookId,
    required String owner,
    required String repo,
    required String path,
    String? branch,
  }) async {
    final response = await _api.post('/github/add-source', {
      'notebookId': notebookId,
      'owner': owner,
      'repo': repo,
      'path': path,
      if (branch != null) 'branch': branch,
    });
    return response;
  }

  /// Add all files from a repository as sources
  Future<Map<String, dynamic>> addRepoAsSources({
    required String notebookId,
    required String owner,
    required String repo,
    String? branch,
    int? maxFiles,
    int? maxFileSizeBytes,
    List<String>? includeExtensions,
    List<String>? excludeExtensions,
  }) async {
    final response = await _api.post('/github/add-repo-sources', {
      'notebookId': notebookId,
      'owner': owner,
      'repo': repo,
      if (branch != null) 'branch': branch,
      if (maxFiles != null) 'maxFiles': maxFiles,
      if (maxFileSizeBytes != null) 'maxFileSizeBytes': maxFileSizeBytes,
      if (includeExtensions != null) 'includeExtensions': includeExtensions,
      if (excludeExtensions != null) 'excludeExtensions': excludeExtensions,
    });
    return response;
  }

  /// Create a new notebook for a repository and import its files as sources
  Future<Map<String, dynamic>> importRepoAsNotebook({
    required String owner,
    required String repo,
    String? branch,
    String? notebookTitle,
    String? notebookDescription,
    String? notebookCategory,
    int? maxFiles,
    int? maxFileSizeBytes,
    List<String>? includeExtensions,
    List<String>? excludeExtensions,
  }) async {
    final response = await _api.post('/github/import-repo-notebook', {
      'owner': owner,
      'repo': repo,
      if (branch != null) 'branch': branch,
      if (notebookTitle != null) 'notebookTitle': notebookTitle,
      if (notebookDescription != null) 'notebookDescription': notebookDescription,
      if (notebookCategory != null) 'notebookCategory': notebookCategory,
      if (maxFiles != null) 'maxFiles': maxFiles,
      if (maxFileSizeBytes != null) 'maxFileSizeBytes': maxFileSizeBytes,
      if (includeExtensions != null) 'includeExtensions': includeExtensions,
      if (excludeExtensions != null) 'excludeExtensions': excludeExtensions,
    });
    return response;
  }

  /// Request AI analysis of repository
  Future<Map<String, dynamic>> analyzeRepo(
    String owner,
    String repo, {
    String? focus,
    List<String>? includeFiles,
  }) async {
    final response = await _api.post('/github/analyze', {
      'owner': owner,
      'repo': repo,
      if (focus != null) 'focus': focus,
      if (includeFiles != null) 'includeFiles': includeFiles,
    });
    return response;
  }

  /// Create an issue
  Future<Map<String, dynamic>> createIssue(
    String owner,
    String repo, {
    required String title,
    String? body,
    List<String>? labels,
  }) async {
    final response = await _api.post('/github/repos/$owner/$repo/issues', {
      'title': title,
      if (body != null) 'body': body,
      if (labels != null) 'labels': labels,
    });
    return response;
  }

  /// Add comment to issue/PR
  Future<Map<String, dynamic>> addComment(
    String owner,
    String repo,
    int issueNumber,
    String body,
  ) async {
    final response = await _api.post(
      '/github/repos/$owner/$repo/issues/$issueNumber/comments',
      {'body': body},
    );
    return response;
  }
}
