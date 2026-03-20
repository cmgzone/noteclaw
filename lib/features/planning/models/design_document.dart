class DesignDocument {
  final int schemaVersion;
  final String title;
  final String summary;
  final DesignThemeSpec theme;
  final List<DesignScreenSpec> screens;

  const DesignDocument({
    required this.schemaVersion,
    required this.title,
    required this.summary,
    required this.theme,
    required this.screens,
  });

  factory DesignDocument.fromJson(Map<String, dynamic> json) {
    final screens = json['screens'];
    return DesignDocument(
      schemaVersion: _asInt(json['schemaVersion'], fallback: 1),
      title: _asString(json['title'], fallback: 'Generated Design'),
      summary: _asString(json['summary']),
      theme: DesignThemeSpec.fromJson(_asMap(json['theme'])),
      screens: screens is List
          ? screens
              .map((screen) => DesignScreenSpec.fromJson(_asMap(screen)))
              .where((screen) => screen.id.isNotEmpty)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'title': title,
      'summary': summary,
      'theme': theme.toJson(),
      'screens': screens.map((screen) => screen.toJson()).toList(),
    };
  }

  DesignDocument copyWith({
    int? schemaVersion,
    String? title,
    String? summary,
    DesignThemeSpec? theme,
    List<DesignScreenSpec>? screens,
  }) {
    return DesignDocument(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      theme: theme ?? this.theme,
      screens: screens ?? this.screens,
    );
  }

  DesignScreenSpec? findScreen(String screenId) {
    for (final screen in screens) {
      if (screen.id == screenId) return screen;
    }
    return null;
  }

  DesignNodeSpec? findNode(String screenId, String nodeId) {
    final screen = findScreen(screenId);
    if (screen == null) return null;
    for (final node in screen.nodes) {
      final found = _findNodeRecursive(node, nodeId);
      if (found != null) return found;
    }
    return null;
  }

  DesignDocument updateNode(
    String screenId,
    String nodeId,
    DesignNodeSpec Function(DesignNodeSpec current) update,
  ) {
    return copyWith(
      screens: screens.map((screen) {
        if (screen.id != screenId) return screen;
        return screen.copyWith(
          nodes: screen.nodes
              .map((node) => _updateNodeRecursive(node, nodeId, update))
              .toList(),
        );
      }).toList(),
    );
  }
}

class DesignThemeSpec {
  final String style;
  final String primaryColor;
  final String secondaryColor;
  final String accentColor;
  final String backgroundColor;
  final String surfaceColor;
  final String textColor;
  final double radius;

  const DesignThemeSpec({
    required this.style,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.radius,
  });

  factory DesignThemeSpec.fromJson(Map<String, dynamic> json) {
    return DesignThemeSpec(
      style: _asString(json['style'], fallback: 'modern'),
      primaryColor: _asString(json['primaryColor'], fallback: '#2563EB'),
      secondaryColor: _asString(json['secondaryColor'], fallback: '#7C3AED'),
      accentColor: _asString(json['accentColor'], fallback: '#F59E0B'),
      backgroundColor: _asString(json['backgroundColor'], fallback: '#F8FAFC'),
      surfaceColor: _asString(json['surfaceColor'], fallback: '#FFFFFF'),
      textColor: _asString(json['textColor'], fallback: '#0F172A'),
      radius: _asDouble(json['radius'], fallback: 20),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'style': style,
      'primaryColor': primaryColor,
      'secondaryColor': secondaryColor,
      'accentColor': accentColor,
      'backgroundColor': backgroundColor,
      'surfaceColor': surfaceColor,
      'textColor': textColor,
      'radius': radius,
    };
  }

  DesignThemeSpec copyWith({
    String? style,
    String? primaryColor,
    String? secondaryColor,
    String? accentColor,
    String? backgroundColor,
    String? surfaceColor,
    String? textColor,
    double? radius,
  }) {
    return DesignThemeSpec(
      style: style ?? this.style,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      accentColor: accentColor ?? this.accentColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      textColor: textColor ?? this.textColor,
      radius: radius ?? this.radius,
    );
  }
}

class DesignScreenSpec {
  final String id;
  final String name;
  final String description;
  final List<DesignNodeSpec> nodes;

  const DesignScreenSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.nodes,
  });

  factory DesignScreenSpec.fromJson(Map<String, dynamic> json) {
    final nodes = json['nodes'];
    return DesignScreenSpec(
      id: _asString(json['id']),
      name: _asString(json['name'], fallback: 'Screen'),
      description: _asString(json['description']),
      nodes: nodes is List
          ? nodes
              .map((node) => DesignNodeSpec.fromJson(_asMap(node)))
              .where((node) => node.type.isNotEmpty)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'nodes': nodes.map((node) => node.toJson()).toList(),
    };
  }

  DesignScreenSpec copyWith({
    String? id,
    String? name,
    String? description,
    List<DesignNodeSpec>? nodes,
  }) {
    return DesignScreenSpec(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      nodes: nodes ?? this.nodes,
    );
  }
}

class DesignNodeSpec {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String body;
  final String label;
  final String value;
  final String icon;
  final String variant;
  final List<DesignNodeItem> items;
  final List<DesignNodeSpec> children;
  final Map<String, dynamic> props;

  const DesignNodeSpec({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.label,
    required this.value,
    required this.icon,
    required this.variant,
    required this.items,
    required this.children,
    required this.props,
  });

  factory DesignNodeSpec.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    final children = json['children'];
    return DesignNodeSpec(
      id: _asString(json['id'], fallback: _asString(json['type'])),
      type: _asString(json['type']),
      title: _asString(json['title']),
      subtitle: _asString(json['subtitle']),
      body: _asString(json['body']),
      label: _asString(json['label']),
      value: _asString(json['value']),
      icon: _asString(json['icon']),
      variant: _asString(json['variant']),
      items: items is List
          ? items
              .map((item) => DesignNodeItem.fromJson(_asMap(item)))
              .toList()
          : const [],
      children: children is List
          ? children
              .map((child) => DesignNodeSpec.fromJson(_asMap(child)))
              .toList()
          : const [],
      props: _asMap(json['props']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'subtitle': subtitle,
      'body': body,
      'label': label,
      'value': value,
      'icon': icon,
      'variant': variant,
      'items': items.map((item) => item.toJson()).toList(),
      'children': children.map((child) => child.toJson()).toList(),
      'props': props,
    };
  }

  DesignNodeSpec copyWith({
    String? id,
    String? type,
    String? title,
    String? subtitle,
    String? body,
    String? label,
    String? value,
    String? icon,
    String? variant,
    List<DesignNodeItem>? items,
    List<DesignNodeSpec>? children,
    Map<String, dynamic>? props,
  }) {
    return DesignNodeSpec(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      body: body ?? this.body,
      label: label ?? this.label,
      value: value ?? this.value,
      icon: icon ?? this.icon,
      variant: variant ?? this.variant,
      items: items ?? this.items,
      children: children ?? this.children,
      props: props ?? this.props,
    );
  }
}

class DesignNodeItem {
  final String title;
  final String subtitle;
  final String label;
  final String value;
  final String meta;
  final String icon;
  final List<String> tags;

  const DesignNodeItem({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.value,
    required this.meta,
    required this.icon,
    required this.tags,
  });

  factory DesignNodeItem.fromJson(Map<String, dynamic> json) {
    final tags = json['tags'];
    return DesignNodeItem(
      title: _asString(json['title']),
      subtitle: _asString(json['subtitle']),
      label: _asString(json['label']),
      value: _asString(json['value']),
      meta: _asString(json['meta']),
      icon: _asString(json['icon']),
      tags: tags is List
          ? tags
              .map((tag) => _asString(tag))
              .where((tag) => tag.isNotEmpty)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'subtitle': subtitle,
      'label': label,
      'value': value,
      'meta': meta,
      'icon': icon,
      'tags': tags,
    };
  }

  DesignNodeItem copyWith({
    String? title,
    String? subtitle,
    String? label,
    String? value,
    String? meta,
    String? icon,
    List<String>? tags,
  }) {
    return DesignNodeItem(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      label: label ?? this.label,
      value: value ?? this.value,
      meta: meta ?? this.meta,
      icon: icon ?? this.icon,
      tags: tags ?? this.tags,
    );
  }
}

DesignNodeSpec? _findNodeRecursive(DesignNodeSpec node, String nodeId) {
  if (node.id == nodeId) return node;
  for (final child in node.children) {
    final found = _findNodeRecursive(child, nodeId);
    if (found != null) return found;
  }
  return null;
}

DesignNodeSpec _updateNodeRecursive(
  DesignNodeSpec node,
  String nodeId,
  DesignNodeSpec Function(DesignNodeSpec current) update,
) {
  if (node.id == nodeId) {
    return update(node);
  }

  if (node.children.isEmpty) {
    return node;
  }

  return node.copyWith(
    children: node.children
        .map((child) => _updateNodeRecursive(child, nodeId, update))
        .toList(),
  );
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final stringValue = value.toString().trim();
  return stringValue.isEmpty ? fallback : stringValue;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  return int.tryParse('$value') ?? fallback;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? fallback;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}
