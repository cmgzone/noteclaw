import 'dart:convert';

import '../models/design_document.dart';

class DesignDocumentHtmlBuilder {
  static const HtmlEscape _htmlEscape = HtmlEscape();

  static String build(
    DesignDocument document, {
    String? title,
    String? initialScreenId,
    bool mobilePrototype = false,
  }) {
    final screens = document.screens;
    final resolvedTitle =
        _preferredText(title, document.title, 'Design Preview');
    final resolvedSummary = document.summary.trim();
    final activeScreenId = screens.any((screen) => screen.id == initialScreenId)
        ? initialScreenId!
        : (screens.isNotEmpty ? screens.first.id : 'screen-0');

    final primary = _normalizeHex(document.theme.primaryColor, '#2563EB');
    final secondary = _normalizeHex(document.theme.secondaryColor, '#7C3AED');
    final accent = _normalizeHex(document.theme.accentColor, '#F59E0B');
    final background = _normalizeHex(document.theme.backgroundColor, '#F8FAFC');
    final surface = _normalizeHex(document.theme.surfaceColor, '#FFFFFF');
    final text = _normalizeHex(document.theme.textColor, '#0F172A');
    final radius = document.theme.radius > 0 ? document.theme.radius : 20;

    final navTabs = screens.length > 1
        ? screens
            .map(
              (screen) => '''
                <button
                  type="button"
                  class="screen-tab${screen.id == activeScreenId ? ' active' : ''}"
                  data-screen-target="${_escape(screen.id)}"
                  onclick="navigateTo('${_js(screen.id)}')"
                >
                  ${_escape(_preferredText(screen.name, screen.id, 'Screen'))}
                </button>
              ''',
            )
            .join()
        : '';

    final bottomNav = mobilePrototype && screens.length > 1
        ? screens.take(5).map((screen) {
            return '''
              <button
                type="button"
                class="bottom-nav__item${screen.id == activeScreenId ? ' active' : ''}"
                data-screen-target="${_escape(screen.id)}"
                onclick="navigateTo('${_js(screen.id)}')"
              >
                <span class="bottom-nav__icon">${_iconForScreen(screen)}</span>
                <span class="bottom-nav__label">${_escape(_preferredText(screen.name, screen.id, 'Screen'))}</span>
              </button>
            ''';
          }).join()
        : '';

    final screensHtml = screens.isEmpty
        ? '''
          <section class="screen active" id="screen-0">
            <div class="screen-shell">
              <div class="empty-state">
                <h2>No structured screens available</h2>
                <p>Add a structured design document to render a synced HTML preview.</p>
              </div>
            </div>
          </section>
        '''
        : screens
            .map(
              (screen) => '''
                <section
                  class="screen${screen.id == activeScreenId ? ' active' : ''}"
                  id="${_escape(screen.id)}"
                >
                  <div class="screen-shell">
                    <header class="screen-header">
                      <div class="screen-header__meta">Screen</div>
                      <h2>${_escape(_preferredText(screen.name, screen.id, 'Screen'))}</h2>
                      ${screen.description.trim().isNotEmpty ? '<p>${_escape(screen.description.trim())}</p>' : ''}
                    </header>
                    <div class="screen-content">
                      ${screen.nodes.map(_renderNode).join()}
                    </div>
                  </div>
                </section>
              ''',
            )
            .join();

    final shellFooterPadding = mobilePrototype && screens.length > 1 ? 110 : 40;

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
  <title>${_escape(resolvedTitle)}</title>
  <style>
    :root {
      --primary: $primary;
      --secondary: $secondary;
      --accent: $accent;
      --background: $background;
      --surface: $surface;
      --text: $text;
      --muted: ${_rgba(text, 0.68)};
      --outline: ${_rgba(primary, 0.14)};
      --soft-primary: ${_rgba(primary, 0.10)};
      --soft-secondary: ${_rgba(secondary, 0.12)};
      --soft-accent: ${_rgba(accent, 0.14)};
      --shadow: 0 18px 45px rgba(15, 23, 42, 0.10);
      --radius: ${radius.toStringAsFixed(radius == radius.roundToDouble() ? 0 : 1)}px;
    }

    * { box-sizing: border-box; }

    html, body {
      margin: 0;
      padding: 0;
      min-height: 100%;
    }

    body {
      font-family: Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top left, var(--soft-secondary) 0%, transparent 34%),
        radial-gradient(circle at top right, var(--soft-primary) 0%, transparent 28%),
        var(--background);
      -webkit-font-smoothing: antialiased;
      line-height: 1.5;
    }

    button {
      font: inherit;
      cursor: pointer;
    }

    .app-shell {
      max-width: 1120px;
      margin: 0 auto;
      padding: 24px 18px ${shellFooterPadding}px;
    }

    .page-header {
      margin-bottom: 18px;
      padding: 24px;
      border-radius: calc(var(--radius) + 10px);
      background:
        linear-gradient(145deg, ${_rgba(surface, 0.92)} 0%, ${_rgba(background, 0.98)} 100%);
      border: 1px solid var(--outline);
      box-shadow: var(--shadow);
      backdrop-filter: blur(16px);
    }

    .page-header__eyebrow {
      font-size: 12px;
      font-weight: 800;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      color: var(--primary);
      margin: 0 0 10px;
    }

    .page-header h1 {
      margin: 0;
      font-size: 30px;
      line-height: 1.1;
    }

    .page-header p {
      margin: 10px 0 0;
      color: var(--muted);
      max-width: 720px;
    }

    .screen-tabs {
      display: flex;
      gap: 10px;
      overflow-x: auto;
      padding: 4px 0 14px;
      margin-bottom: 14px;
      scrollbar-width: none;
    }

    .screen-tabs::-webkit-scrollbar {
      display: none;
    }

    .screen-tab {
      border: 1px solid var(--outline);
      background: ${_rgba(surface, 0.84)};
      color: var(--text);
      padding: 10px 14px;
      border-radius: 999px;
      font-size: 14px;
      font-weight: 700;
      white-space: nowrap;
      transition: all 0.18s ease;
    }

    .screen-tab.active {
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: white;
      border-color: transparent;
      box-shadow: 0 14px 28px ${_rgba(primary, 0.24)};
    }

    .screen {
      display: none;
      animation: fadeIn 0.22s ease;
    }

    .screen.active {
      display: block;
    }

    @keyframes fadeIn {
      from { opacity: 0; transform: translateY(8px); }
      to { opacity: 1; transform: translateY(0); }
    }

    .screen-shell {
      border-radius: calc(var(--radius) + 10px);
      background: ${_rgba(surface, 0.96)};
      border: 1px solid var(--outline);
      box-shadow: var(--shadow);
      overflow: hidden;
    }

    .screen-header {
      padding: 24px 24px 18px;
      background:
        linear-gradient(160deg, ${_rgba(primary, 0.10)} 0%, ${_rgba(secondary, 0.06)} 100%);
      border-bottom: 1px solid var(--outline);
    }

    .screen-header__meta {
      margin: 0 0 8px;
      color: var(--primary);
      font-size: 12px;
      font-weight: 800;
      letter-spacing: 0.10em;
      text-transform: uppercase;
    }

    .screen-header h2 {
      margin: 0;
      font-size: 26px;
      line-height: 1.15;
    }

    .screen-header p {
      margin: 8px 0 0;
      color: var(--muted);
      max-width: 720px;
    }

    .screen-content {
      padding: 22px;
      display: grid;
      gap: 18px;
    }

    .node {
      border-radius: var(--radius);
      border: 1px solid var(--outline);
      background: var(--surface);
      padding: 18px;
      box-shadow: 0 10px 28px rgba(15, 23, 42, 0.05);
    }

    .node h3, .node h4, .node p {
      margin-top: 0;
    }

    .node__eyebrow {
      margin: 0 0 10px;
      color: var(--primary);
      font-size: 12px;
      font-weight: 800;
      letter-spacing: 0.10em;
      text-transform: uppercase;
    }

    .node__title {
      margin: 0;
      font-size: 20px;
      line-height: 1.2;
    }

    .node__subtitle {
      margin: 8px 0 0;
      color: var(--text);
      font-size: 15px;
      font-weight: 600;
    }

    .node__body {
      margin: 10px 0 0;
      color: var(--muted);
    }

    .node__header {
      margin-bottom: 16px;
    }

    .node-hero {
      background:
        linear-gradient(145deg, ${_rgba(primary, 0.10)} 0%, ${_rgba(secondary, 0.12)} 100%);
      border: none;
      box-shadow: 0 24px 46px ${_rgba(primary, 0.14)};
      padding: 24px;
    }

    .node-hero .node__title {
      font-size: 30px;
    }

    .hero-actions,
    .action-row,
    .cta-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 18px;
    }

    .button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 12px 16px;
      border-radius: 999px;
      border: 1px solid transparent;
      font-weight: 700;
      text-decoration: none;
    }

    .button--primary {
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: white;
      box-shadow: 0 16px 32px ${_rgba(primary, 0.24)};
    }

    .button--secondary {
      background: transparent;
      border-color: var(--outline);
      color: var(--text);
    }

    .stats-grid {
      display: grid;
      gap: 12px;
      grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    }

    .stat-card,
    .feature-card,
    .list-card,
    .field-card {
      border-radius: calc(var(--radius) - 4px);
      background: ${_rgba(background, 0.92)};
      border: 1px solid var(--outline);
      padding: 14px;
    }

    .stat-card__value {
      font-size: 28px;
      font-weight: 800;
      line-height: 1.1;
    }

    .stat-card__label {
      margin-top: 6px;
      color: var(--muted);
      font-size: 13px;
    }

    .feature-grid {
      display: grid;
      gap: 12px;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
    }

    .feature-card__title,
    .list-card__title {
      margin: 0;
      font-size: 16px;
      font-weight: 700;
    }

    .feature-card__subtitle,
    .list-card__subtitle,
    .list-card__meta {
      margin-top: 8px;
      color: var(--muted);
      font-size: 14px;
    }

    .list-stack,
    .timeline {
      display: grid;
      gap: 12px;
    }

    .timeline-item {
      position: relative;
      padding-left: 18px;
    }

    .timeline-item::before {
      content: "";
      position: absolute;
      top: 8px;
      left: 0;
      width: 9px;
      height: 9px;
      border-radius: 999px;
      background: linear-gradient(135deg, var(--primary), var(--accent));
      box-shadow: 0 0 0 5px ${_rgba(primary, 0.10)};
    }

    .quote-card {
      background: linear-gradient(160deg, ${_rgba(accent, 0.12)} 0%, ${_rgba(surface, 0.96)} 100%);
      border-left: 4px solid var(--accent);
    }

    .quote-card blockquote {
      margin: 0;
      font-size: 20px;
      font-weight: 700;
      line-height: 1.45;
    }

    .quote-card cite {
      display: block;
      margin-top: 12px;
      color: var(--muted);
      font-style: normal;
    }

    .content-list {
      display: grid;
      gap: 10px;
      margin-top: 14px;
    }

    .content-list__item {
      display: flex;
      gap: 10px;
      align-items: flex-start;
    }

    .content-list__dot {
      width: 9px;
      height: 9px;
      margin-top: 8px;
      border-radius: 999px;
      background: var(--primary);
      flex-shrink: 0;
    }

    .form-fields {
      display: grid;
      gap: 12px;
      margin-top: 16px;
    }

    .field-label {
      display: block;
      margin-bottom: 6px;
      font-size: 13px;
      font-weight: 700;
      color: var(--text);
    }

    .field-input {
      width: 100%;
      border-radius: 14px;
      border: 1px solid var(--outline);
      background: ${_rgba(background, 0.86)};
      color: var(--muted);
      padding: 13px 14px;
      outline: none;
    }

    .cta-card {
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: white;
      border: none;
      box-shadow: 0 22px 44px ${_rgba(primary, 0.20)};
    }

    .cta-card .node__eyebrow,
    .cta-card .node__subtitle,
    .cta-card .node__body {
      color: rgba(255, 255, 255, 0.86);
    }

    .cta-card .node__title {
      color: white;
    }

    .tag-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 12px;
    }

    .tag {
      display: inline-flex;
      align-items: center;
      padding: 6px 10px;
      border-radius: 999px;
      background: var(--soft-primary);
      color: var(--primary);
      font-size: 12px;
      font-weight: 700;
    }

    .node-children {
      display: grid;
      gap: 12px;
      margin-top: 16px;
    }

    .empty-state {
      padding: 40px 24px;
      text-align: center;
    }

    .empty-state h2 {
      margin: 0 0 10px;
    }

    .empty-state p {
      margin: 0;
      color: var(--muted);
    }

    .bottom-nav {
      position: fixed;
      left: 12px;
      right: 12px;
      bottom: 12px;
      display: flex;
      gap: 8px;
      padding: 10px;
      border-radius: 24px;
      background: ${_rgba(surface, 0.92)};
      border: 1px solid var(--outline);
      box-shadow: 0 20px 40px rgba(15, 23, 42, 0.15);
      backdrop-filter: blur(18px);
      z-index: 20;
    }

    .bottom-nav__item {
      flex: 1;
      min-width: 0;
      border: none;
      background: transparent;
      border-radius: 16px;
      padding: 10px 8px;
      color: var(--muted);
      display: grid;
      gap: 4px;
      justify-items: center;
      transition: all 0.18s ease;
    }

    .bottom-nav__item.active {
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: white;
      box-shadow: 0 14px 28px ${_rgba(primary, 0.22)};
    }

    .bottom-nav__icon {
      font-size: 18px;
      line-height: 1;
    }

    .bottom-nav__label {
      font-size: 11px;
      font-weight: 700;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      max-width: 100%;
    }

    @media (max-width: 720px) {
      .app-shell {
        padding-left: 14px;
        padding-right: 14px;
      }

      .page-header,
      .screen-header,
      .screen-content,
      .node,
      .node-hero {
        padding-left: 16px;
        padding-right: 16px;
      }

      .node-hero .node__title {
        font-size: 26px;
      }
    }
  </style>
</head>
<body>
  <div class="app-shell">
    <header class="page-header">
      <p class="page-header__eyebrow">${_escape(document.theme.style.isNotEmpty ? document.theme.style : 'structured design')}</p>
      <h1>${_escape(resolvedTitle)}</h1>
      ${resolvedSummary.isNotEmpty ? '<p>${_escape(resolvedSummary)}</p>' : ''}
    </header>
    ${navTabs.isNotEmpty ? '<div class="screen-tabs">$navTabs</div>' : ''}
    <main>
      $screensHtml
    </main>
  </div>
  ${bottomNav.isNotEmpty ? '<nav class="bottom-nav">$bottomNav</nav>' : ''}
  <script>
    function navigateTo(screenId) {
      var screens = document.querySelectorAll('.screen');
      var matched = false;
      screens.forEach(function(screen) {
        var isActive = screen.id === screenId;
        screen.classList.toggle('active', isActive);
        if (isActive) {
          matched = true;
        }
      });

      document.querySelectorAll('[data-screen-target]').forEach(function(button) {
        button.classList.toggle('active', button.getAttribute('data-screen-target') === screenId);
      });

      if (!matched && screens.length > 0) {
        screens[0].classList.add('active');
      }

      window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    window.navigateTo = navigateTo;
    document.addEventListener('DOMContentLoaded', function() {
      navigateTo('${_js(activeScreenId)}');
    });
  </script>
</body>
</html>
''';
  }

  static String _renderNode(DesignNodeSpec node) {
    switch (node.type) {
      case 'hero':
        return '''
          <section class="node node-hero" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node, titleTag: 'h3')}
            ${_renderActionButtons(node.items, primaryLabel: node.label)}
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'stats_row':
        return '''
          <section class="node" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            <div class="stats-grid">
              ${node.items.isNotEmpty ? node.items.map(_renderStatItem).join() : _renderEmptyHelper('Add stat items to show KPI cards.')}
            </div>
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'feature_grid':
        return '''
          <section class="node" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            <div class="feature-grid">
              ${node.items.isNotEmpty ? node.items.map(_renderFeatureItem).join() : _renderEmptyHelper('Add feature items to show a feature grid.')}
            </div>
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'card_list':
        return '''
          <section class="node" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            <div class="list-stack">
              ${node.items.isNotEmpty ? node.items.map(_renderListItem).join() : _renderEmptyHelper('Add list items to populate this section.')}
            </div>
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'timeline':
        return '''
          <section class="node" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            <div class="timeline">
              ${node.items.isNotEmpty ? node.items.map(_renderTimelineItem).join() : _renderEmptyHelper('Add timeline items to build this flow.')}
            </div>
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'quote':
        return '''
          <section class="node quote-card" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${node.label.trim().isNotEmpty ? '<p class="node__eyebrow">${_escape(node.label.trim())}</p>' : ''}
            <blockquote>${_escape(_preferredText(node.body, node.title, 'Add a supporting quote.'))}</blockquote>
            ${(node.title.trim().isNotEmpty || node.subtitle.trim().isNotEmpty) ? '<cite>${_escape([
                node.title.trim(),
                node.subtitle.trim()
              ].where((part) => part.isNotEmpty).join(' | '))}</cite>' : ''}
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'cta':
        return '''
          <section class="node cta-card" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            ${_renderActionButtons(node.items, primaryLabel: node.label.isNotEmpty ? node.label : 'Continue')}
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'action_bar':
        return '''
          <section class="node" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            <div class="action-row">
              ${_renderInlineActions(node.items, node.label)}
            </div>
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'form':
        return '''
          <section class="node" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            <div class="form-fields">
              ${_renderFormFields(node)}
            </div>
            ${_renderActionButtons(node.items, primaryLabel: node.label.isNotEmpty ? node.label : 'Submit')}
            ${_renderNodeChildren(node)}
          </section>
        ''';
      case 'content':
      default:
        return '''
          <section class="node" data-node-id="${_escape(node.id)}" data-node-type="${_escape(node.type)}">
            ${_renderNodeHeader(node)}
            ${node.items.isNotEmpty ? '<div class="content-list">${node.items.map(_renderContentItem).join()}</div>' : ''}
            ${_renderNodeChildren(node)}
          </section>
        ''';
    }
  }

  static String _renderNodeHeader(DesignNodeSpec node,
      {String titleTag = 'h3'}) {
    final parts = <String>[];
    if (node.label.trim().isNotEmpty) {
      parts.add('<p class="node__eyebrow">${_escape(node.label.trim())}</p>');
    }
    if (node.title.trim().isNotEmpty) {
      parts.add(
          '<$titleTag class="node__title">${_escape(node.title.trim())}</$titleTag>');
    }
    if (node.subtitle.trim().isNotEmpty) {
      parts.add(
          '<p class="node__subtitle">${_escape(node.subtitle.trim())}</p>');
    }
    if (node.body.trim().isNotEmpty) {
      parts.add('<p class="node__body">${_escape(node.body.trim())}</p>');
    }
    if (parts.isEmpty) return '';
    return '<div class="node__header">${parts.join()}</div>';
  }

  static String _renderStatItem(DesignNodeItem item) {
    final value = _preferredText(item.value, item.title, '--');
    final label = _preferredText(item.label, item.subtitle, 'Metric');
    return '''
      <article class="stat-card">
        <div class="stat-card__value">${_escape(value)}</div>
        <div class="stat-card__label">${_escape(label)}</div>
      </article>
    ''';
  }

  static String _renderFeatureItem(DesignNodeItem item) {
    final tags = item.tags.isNotEmpty
        ? '<div class="tag-row">${item.tags.map((tag) => '<span class="tag">${_escape(tag)}</span>').join()}</div>'
        : '';
    return '''
      <article class="feature-card">
        <h4 class="feature-card__title">${_escape(_preferredText(item.title, item.label, 'Feature'))}</h4>
        ${item.subtitle.trim().isNotEmpty ? '<p class="feature-card__subtitle">${_escape(item.subtitle.trim())}</p>' : ''}
        ${item.meta.trim().isNotEmpty ? '<p class="feature-card__subtitle">${_escape(item.meta.trim())}</p>' : ''}
        $tags
      </article>
    ''';
  }

  static String _renderListItem(DesignNodeItem item) {
    final metaLine = [item.meta.trim(), item.value.trim()]
        .where((part) => part.isNotEmpty)
        .join(' | ');
    return '''
      <article class="list-card">
        <h4 class="list-card__title">${_escape(_preferredText(item.title, item.label, 'Item'))}</h4>
        ${item.subtitle.trim().isNotEmpty ? '<p class="list-card__subtitle">${_escape(item.subtitle.trim())}</p>' : ''}
        ${metaLine.isNotEmpty ? '<p class="list-card__meta">${_escape(metaLine)}</p>' : ''}
      </article>
    ''';
  }

  static String _renderTimelineItem(DesignNodeItem item) {
    final metaLine = item.meta.trim().isNotEmpty
        ? '<p class="list-card__meta">${_escape(item.meta.trim())}</p>'
        : '';
    return '''
      <article class="timeline-item">
        <div class="list-card">
          <h4 class="list-card__title">${_escape(_preferredText(item.title, item.label, 'Milestone'))}</h4>
          ${item.subtitle.trim().isNotEmpty ? '<p class="list-card__subtitle">${_escape(item.subtitle.trim())}</p>' : ''}
          $metaLine
        </div>
      </article>
    ''';
  }

  static String _renderContentItem(DesignNodeItem item) {
    return '''
      <div class="content-list__item">
        <span class="content-list__dot"></span>
        <div>
          <strong>${_escape(_preferredText(item.title, item.label, 'Point'))}</strong>
          ${item.subtitle.trim().isNotEmpty ? '<p class="node__body" style="margin: 4px 0 0;">${_escape(item.subtitle.trim())}</p>' : ''}
          ${item.meta.trim().isNotEmpty ? '<p class="list-card__meta" style="margin-bottom: 0;">${_escape(item.meta.trim())}</p>' : ''}
        </div>
      </div>
    ''';
  }

  static String _renderFormFields(DesignNodeSpec node) {
    final fields = node.items.isNotEmpty
        ? node.items
        : const [
            DesignNodeItem(
              title: 'Name',
              subtitle: '',
              label: '',
              value: '',
              meta: '',
              icon: '',
              tags: [],
            ),
            DesignNodeItem(
              title: 'Email',
              subtitle: '',
              label: '',
              value: '',
              meta: '',
              icon: '',
              tags: [],
            ),
            DesignNodeItem(
              title: 'Message',
              subtitle: '',
              label: '',
              value: '',
              meta: '',
              icon: '',
              tags: [],
            ),
          ];

    return fields.map((field) {
      final label = _preferredText(field.label, field.title, 'Field');
      final placeholder =
          _preferredText(field.subtitle, field.value, 'Enter $label');
      return '''
        <div class="field-card">
          <label class="field-label">${_escape(label)}</label>
          <input class="field-input" type="text" value="" placeholder="${_escape(placeholder)}" />
        </div>
      ''';
    }).join();
  }

  static String _renderActionButtons(
    List<DesignNodeItem> items, {
    String? primaryLabel,
  }) {
    final actionButtons = <String>[];
    final candidates = items.take(2).toList();

    if (candidates.isEmpty &&
        primaryLabel != null &&
        primaryLabel.trim().isNotEmpty) {
      actionButtons.add(
          '<span class="button button--primary">${_escape(primaryLabel.trim())}</span>');
    } else {
      for (var i = 0; i < candidates.length; i++) {
        final item = candidates[i];
        final label = _preferredText(item.title, item.label, item.value);
        if (label.isEmpty) continue;
        actionButtons.add(
          '<span class="button ${i == 0 ? 'button--primary' : 'button--secondary'}">${_escape(label)}</span>',
        );
      }
    }

    if (actionButtons.isEmpty) return '';
    return '<div class="hero-actions">${actionButtons.join()}</div>';
  }

  static String _renderInlineActions(
      List<DesignNodeItem> items, String fallbackLabel) {
    final labels = items
        .map((item) => _preferredText(item.title, item.label, item.value))
        .where((label) => label.isNotEmpty)
        .take(4)
        .toList();

    if (labels.isEmpty && fallbackLabel.trim().isNotEmpty) {
      labels.add(fallbackLabel.trim());
    }

    if (labels.isEmpty) {
      return _renderEmptyHelper('Add actions to populate this toolbar.');
    }

    return labels.asMap().entries.map((entry) {
      return '<span class="button ${entry.key == 0 ? 'button--primary' : 'button--secondary'}">${_escape(entry.value)}</span>';
    }).join();
  }

  static String _renderNodeChildren(DesignNodeSpec node) {
    if (node.children.isEmpty) return '';
    return '<div class="node-children">${node.children.map(_renderNode).join()}</div>';
  }

  static String _renderEmptyHelper(String text) {
    return '<p class="node__body">${_escape(text)}</p>';
  }

  static String _iconForScreen(DesignScreenSpec screen) {
    final id = screen.id.toLowerCase();
    if (id.contains('home')) return 'H';
    if (id.contains('dashboard')) return 'D';
    if (id.contains('profile') || id.contains('account')) return 'P';
    if (id.contains('settings')) return 'S';
    if (id.contains('search')) return 'Q';
    if (id.contains('chat') || id.contains('message')) return 'M';
    if (id.contains('report') || id.contains('analytics')) return 'R';
    if (id.contains('task')) return 'T';
    return 'O';
  }

  static String _preferredText(String? a, String? b, [String fallback = '']) {
    final first = a?.trim() ?? '';
    if (first.isNotEmpty) return first;
    final second = b?.trim() ?? '';
    if (second.isNotEmpty) return second;
    return fallback;
  }

  static String _normalizeHex(String value, String fallback) {
    final normalized = value.trim().replaceAll('#', '');
    if (normalized.length == 6 && int.tryParse(normalized, radix: 16) != null) {
      return '#${normalized.toUpperCase()}';
    }
    if (normalized.length == 8 && int.tryParse(normalized, radix: 16) != null) {
      return '#${normalized.substring(2).toUpperCase()}';
    }
    return fallback;
  }

  static String _rgba(String value, double alpha) {
    final normalized = _normalizeHex(value, '#0F172A').replaceAll('#', '');
    final red = int.parse(normalized.substring(0, 2), radix: 16);
    final green = int.parse(normalized.substring(2, 4), radix: 16);
    final blue = int.parse(normalized.substring(4, 6), radix: 16);
    return 'rgba($red, $green, $blue, ${alpha.clamp(0, 1).toStringAsFixed(2)})';
  }

  static String _escape(String value) => _htmlEscape.convert(value);

  static String _js(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n');
}
