enum DesignArtifactType {
  prototype('prototype'),
  designSystem('design_system'),
  screenSet('screen_set'),
  componentLibrary('component_library'),
  flow('flow');

  final String backendValue;
  const DesignArtifactType(this.backendValue);

  static DesignArtifactType fromBackend(String? value) {
    switch (value) {
      case 'design_system':
        return DesignArtifactType.designSystem;
      case 'screen_set':
        return DesignArtifactType.screenSet;
      case 'component_library':
        return DesignArtifactType.componentLibrary;
      case 'flow':
        return DesignArtifactType.flow;
      case 'prototype':
      default:
        return DesignArtifactType.prototype;
    }
  }
}

enum DesignArtifactStatus {
  draft('draft'),
  ready('ready'),
  archived('archived');

  final String backendValue;
  const DesignArtifactStatus(this.backendValue);

  static DesignArtifactStatus fromBackend(String? value) {
    switch (value) {
      case 'ready':
        return DesignArtifactStatus.ready;
      case 'archived':
        return DesignArtifactStatus.archived;
      case 'draft':
      default:
        return DesignArtifactStatus.draft;
    }
  }
}

enum DesignArtifactSource {
  manual('manual'),
  aiGenerated('ai_generated'),
  imported('imported');

  final String backendValue;
  const DesignArtifactSource(this.backendValue);

  static DesignArtifactSource fromBackend(String? value) {
    switch (value) {
      case 'ai_generated':
        return DesignArtifactSource.aiGenerated;
      case 'imported':
        return DesignArtifactSource.imported;
      case 'manual':
      default:
        return DesignArtifactSource.manual;
    }
  }
}

class DesignArtifactVersion {
  final String id;
  final String artifactId;
  final int versionNumber;
  final Map<String, dynamic> snapshot;
  final String? changeSummary;
  final String? createdBy;
  final DateTime createdAt;

  const DesignArtifactVersion({
    required this.id,
    required this.artifactId,
    required this.versionNumber,
    required this.snapshot,
    required this.createdAt,
    this.changeSummary,
    this.createdBy,
  });

  factory DesignArtifactVersion.fromBackendJson(Map<String, Object?> json) {
    final snapshot = json['snapshot'];
    final versionValue = json['versionNumber'] ?? json['version_number'];
    return DesignArtifactVersion(
      id: json['id'] as String? ?? '',
      artifactId: (json['artifactId'] ?? json['artifact_id']) as String? ?? '',
      versionNumber: versionValue is int
          ? versionValue
          : int.tryParse('$versionValue') ?? 1,
      snapshot: snapshot is Map
          ? Map<String, dynamic>.from(snapshot)
          : <String, dynamic>{},
      changeSummary:
          (json['changeSummary'] ?? json['change_summary']) as String?,
      createdBy: (json['createdBy'] ?? json['created_by']) as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : json['created_at'] != null
              ? DateTime.parse(json['created_at'] as String)
              : DateTime.now(),
    );
  }
}

class DesignArtifact {
  final String id;
  final String planId;
  final String name;
  final DesignArtifactType artifactType;
  final DesignArtifactStatus status;
  final DesignArtifactSource source;
  final int schemaVersion;
  final Map<String, dynamic> rootData;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int latestVersionNumber;
  final List<DesignArtifactVersion> versions;

  const DesignArtifact({
    required this.id,
    required this.planId,
    required this.name,
    required this.artifactType,
    required this.status,
    required this.source,
    required this.schemaVersion,
    required this.rootData,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    required this.latestVersionNumber,
    this.versions = const [],
  });

  factory DesignArtifact.fromBackendJson(Map<String, Object?> json) {
    final rootData = json['rootData'] ?? json['root_data'];
    final metadata = json['metadata'];
    final versionsList = json['versions'];
    final schemaValue = json['schemaVersion'] ?? json['schema_version'];
    final latestVersionValue =
        json['latestVersionNumber'] ?? json['latest_version_number'];

    return DesignArtifact(
      id: json['id'] as String? ?? '',
      planId: (json['planId'] ?? json['plan_id']) as String? ?? '',
      name: json['name'] as String? ?? '',
      artifactType:
          DesignArtifactType.fromBackend(json['artifactType'] as String? ??
              json['artifact_type'] as String?),
      status:
          DesignArtifactStatus.fromBackend(json['status'] as String?),
      source: DesignArtifactSource.fromBackend(json['source'] as String?),
      schemaVersion: schemaValue is int
          ? schemaValue
          : int.tryParse('$schemaValue') ?? 1,
      rootData: rootData is Map
          ? Map<String, dynamic>.from(rootData)
          : <String, dynamic>{},
      metadata: metadata is Map
          ? Map<String, dynamic>.from(metadata)
          : <String, dynamic>{},
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : json['created_at'] != null
              ? DateTime.parse(json['created_at'] as String)
              : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : json['updated_at'] != null
              ? DateTime.parse(json['updated_at'] as String)
              : DateTime.now(),
      latestVersionNumber: latestVersionValue is int
          ? latestVersionValue
          : int.tryParse('$latestVersionValue') ?? 0,
      versions: versionsList is List
          ? versionsList
              .map((v) => DesignArtifactVersion.fromBackendJson(
                  v as Map<String, Object?>))
              .toList()
          : const [],
    );
  }

  DesignArtifact copyWith({
    String? id,
    String? planId,
    String? name,
    DesignArtifactType? artifactType,
    DesignArtifactStatus? status,
    DesignArtifactSource? source,
    int? schemaVersion,
    Map<String, dynamic>? rootData,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? latestVersionNumber,
    List<DesignArtifactVersion>? versions,
  }) {
    return DesignArtifact(
      id: id ?? this.id,
      planId: planId ?? this.planId,
      name: name ?? this.name,
      artifactType: artifactType ?? this.artifactType,
      status: status ?? this.status,
      source: source ?? this.source,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      rootData: rootData ?? this.rootData,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      latestVersionNumber: latestVersionNumber ?? this.latestVersionNumber,
      versions: versions ?? this.versions,
    );
  }

  Map<String, dynamic> toBackendJson() {
    return {
      'name': name,
      'artifactType': artifactType.backendValue,
      'status': status.backendValue,
      'source': source.backendValue,
      'schemaVersion': schemaVersion,
      'rootData': rootData,
      'metadata': metadata,
    };
  }
}
