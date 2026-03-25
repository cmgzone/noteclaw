import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_theme.dart';
import '../../../core/ai/ai_provider.dart';
import '../../../core/search/serper_service.dart';
import '../../../core/services/time_context_service.dart';
import '../../subscription/services/credit_manager.dart';
import '../models/plan_task.dart';
import '../planning_provider.dart';

/// Planning AI chat screen for brainstorming and generating requirements/tasks.
/// Implements Requirements: 2.1, 2.2, 2.3, 2.4, 2.5
class PlanningAIScreen extends ConsumerStatefulWidget {
  final String? planId;

  const PlanningAIScreen({super.key, this.planId});

  @override
  ConsumerState<PlanningAIScreen> createState() => _PlanningAIScreenState();
}

class _PlanningAIScreenState extends ConsumerState<PlanningAIScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_PlanningMessage> _messages = [];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _webSearchEnabled = true;
  _PlanningMode _currentMode = _PlanningMode.brainstorm;
  List<SerperSearchResult> _lastSearchResults = [];

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  void _initializeChat() {
    // Add welcome message (Requirements 2.1)
    _messages.add(_PlanningMessage(
      text: _getWelcomeMessage(),
      isUser: false,
      timestamp: DateTime.now(),
    ));
  }

  String _getWelcomeMessage() {
    final timeService = ref.read(timeContextServiceProvider);
    final timeInfo = timeService.getShortTimeContext();
    return _getProjectAssistantWelcomeMessage(timeInfo);
    /*
    
    return '''👋 **Welcome to Planning Mode AI!**

📅 $timeInfo

I'm here to help you brainstorm, organize ideas, and create structured plans. Here's what I can do:

🧠 **Brainstorm** - Explore and refine your ideas
🔍 **Research** - Search the web for latest info, dependencies, best practices
📋 **Generate Requirements** - Create EARS-pattern requirements
📐 **Design** - Create design notes and architectural decisions
✅ **Create Tasks** - Break down requirements into actionable tasks

🌐 **Web Search is ${_webSearchEnabled ? 'ENABLED' : 'DISABLED'}** - I can search for:
- Latest package versions and dependencies
- Best practices and documentation
- Technology comparisons and recommendations

**How to get started:**
1. Tell me about your project idea or goal
2. I'll help you break it down into clear requirements
3. We'll create actionable tasks from those requirements

What would you like to work on today?''';
    */
  }

  String _getProjectAssistantWelcomeMessage(String timeInfo) {
    return '''Welcome to Project Assistant.

$timeInfo

I can help you brainstorm, organize ideas, and turn them into a structured project workspace. This can support product builds, research, operations, content systems, and other non-coding work too.

- Brainstorm: Explore and refine your ideas
- Research: Search the web for current information, dependencies, and best practices
- Generate Requirements: Create EARS-pattern requirements
- Design: Create design notes and architectural decisions
- Create Tasks: Break work into actionable tasks

Web Search is ${_webSearchEnabled ? 'ENABLED' : 'DISABLED'}.
I can search for:
- Latest package versions and dependencies
- Best practices and documentation
- Technology comparisons and recommendations

How to get started:
1. Tell me about your project, workflow, or goal
2. I will help you break it down into clear requirements
3. We will create actionable tasks from those requirements

What would you like to work on today?''';
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    // Check credits
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage,
      feature: 'planning_ai_chat',
    );
    if (!hasCredits) return;

    // Add user message
    setState(() {
      _messages.add(_PlanningMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      // Generate AI response based on current mode
      final response = await _generateResponse(text);

      setState(() {
        _messages.add(_PlanningMessage(
          text: response,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_PlanningMessage(
          text: '❌ Error: ${e.toString()}',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  /// Generate AI response based on current mode (Requirements 2.1, 2.2, 2.3)
  Future<String> _generateResponse(String userInput) async {
    final aiNotifier = ref.read(aiProvider.notifier);
    final planState = ref.read(planningProvider);
    final currentPlan = planState.currentPlan;
    final timeService = ref.read(timeContextServiceProvider);

    // Get time context to reduce hallucinations
    final timeContext = timeService.getTimeContext();

    // Build context from current plan if available
    String planContext = '';
    if (currentPlan != null) {
      planContext = '''
**Current Plan: ${currentPlan.title}**
${currentPlan.description.isNotEmpty ? 'Description: ${currentPlan.description}' : ''}

**Existing Requirements (${currentPlan.requirements.length}):**
${currentPlan.requirements.map((r) => '- ${r.title}').join('\n')}

**Existing Tasks (${currentPlan.tasks.length}):**
${currentPlan.tasks.map((t) => '- ${t.title} [${t.status.name}]').join('\n')}
''';
    }

    // Perform web search if enabled and in research mode or if query seems to need current info
    String webSearchContext = '';
    if (_webSearchEnabled && _shouldSearchWeb(userInput)) {
      webSearchContext = await _performWebSearch(userInput);
    }

    // Build conversation history
    final history = _messages
        .where((m) => !m.isError)
        .map((m) => AIPromptResponse(
              prompt: m.isUser ? m.text : '',
              response: m.isUser ? '' : m.text,
            ))
        .toList();

    String systemPrompt;
    switch (_currentMode) {
      case _PlanningMode.brainstorm:
        systemPrompt = _getBrainstormPrompt(planContext, timeContext, webSearchContext);
        break;
      case _PlanningMode.research:
        systemPrompt = _getResearchPrompt(planContext, timeContext, webSearchContext);
        break;
      case _PlanningMode.requirements:
        systemPrompt = _getRequirementsPrompt(planContext);
        break;
      case _PlanningMode.design:
        systemPrompt = _getDesignPrompt(planContext);
        break;
      case _PlanningMode.tasks:
        systemPrompt = _getTasksPrompt(planContext);
        break;
    }

    await aiNotifier.generateContent(
      '''$systemPrompt

User Input: $userInput''',
      context: [planContext],
      style: ChatStyle.standard,
      externalHistory: history,
    );

    final aiState = ref.read(aiProvider);
    if (aiState.error != null) {
      throw Exception(aiState.error);
    }

    return aiState.lastResponse ??
        'I apologize, I couldn\'t generate a response.';
  }

  /// Check if the query should trigger a web search
  bool _shouldSearchWeb(String query) {
    final lowerQuery = query.toLowerCase();
    
    // Keywords that suggest need for current information
    final searchTriggers = [
      'latest', 'current', 'newest', 'version', 'update',
      'best practice', 'recommend', 'compare', 'vs',
      'dependency', 'dependencies', 'package', 'library',
      'how to', 'tutorial', 'documentation', 'docs',
      'api', 'sdk', 'framework', 'tool',
      '2024', '2025', '2026', 'today', 'now',
      'search', 'find', 'look up', 'research',
    ];
    
    // Always search in research mode
    if (_currentMode == _PlanningMode.research) return true;
    
    // Check for trigger keywords
    return searchTriggers.any((trigger) => lowerQuery.contains(trigger));
  }

  /// Perform web search and format results for AI context
  Future<String> _performWebSearch(String query) async {
    setState(() => _isSearching = true);
    
    try {
      final serperService = ref.read(serperServiceProvider);
      
      // Enhance query for better results
      String searchQuery = query;
      if (!query.toLowerCase().contains('2024') && 
          !query.toLowerCase().contains('2025') &&
          !query.toLowerCase().contains('2026')) {
        searchQuery = '$query ${DateTime.now().year}';
      }
      
      final results = await serperService.search(searchQuery, num: 5);
      _lastSearchResults = results;
      
      if (results.isEmpty) {
        return '';
      }
      
      // Format results for AI context
      final buffer = StringBuffer();
      buffer.writeln('\n**🔍 Web Search Results (Live Data):**');
      buffer.writeln('Search query: "$searchQuery"\n');
      
      for (int i = 0; i < results.length && i < 5; i++) {
        final result = results[i];
        buffer.writeln('${i + 1}. **${result.title}**');
        buffer.writeln('   ${result.snippet}');
        buffer.writeln('   Source: ${result.link}');
        if (result.date != null) {
          buffer.writeln('   Date: ${result.date}');
        }
        buffer.writeln();
      }
      
      buffer.writeln('---');
      buffer.writeln('*Use this information to provide accurate, up-to-date recommendations.*\n');
      
      return buffer.toString();
    } catch (e) {
      debugPrint('[PlanningAI] Web search error: $e');
      return '\n*Web search failed: ${e.toString()}*\n';
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  String _getBrainstormPrompt(String planContext, String timeContext, String webSearchContext) {
    return '''You are a Planning AI assistant helping users brainstorm and refine project ideas.

$timeContext

**Your Role (Requirements 2.1):**
- Engage in conversation to understand the user's goals
- Ask clarifying questions to better understand the scope
- Help break down complex ideas into manageable pieces
- Suggest related considerations they might have missed
- Be encouraging and collaborative
- Use current date/time context to provide accurate timeline estimates

$webSearchContext

**Context:**
$planContext

**Guidelines:**
- Keep responses focused and actionable
- Use bullet points for clarity
- Ask follow-up questions to deepen understanding
- Suggest when the user might be ready to move to requirements generation
- Use emojis sparingly for warmth
- If web search results are provided, use them to give accurate, up-to-date information
- Always mention the current date when discussing timelines or deadlines

**Response Format:**
Provide a helpful, conversational response that advances the planning process.''';
  }

  String _getResearchPrompt(String planContext, String timeContext, String webSearchContext) {
    return '''You are a Planning AI assistant with web research capabilities, helping users find up-to-date information for their projects.

$timeContext

**Your Role:**
- Search and analyze current information from the web
- Provide accurate, up-to-date recommendations for:
  • Package versions and dependencies
  • Best practices and design patterns
  • Technology comparisons
  • Documentation and tutorials
- Help users make informed decisions based on current data
- Reduce hallucinations by using real search results

$webSearchContext

**Context:**
$planContext

**Guidelines:**
- ALWAYS cite sources when providing information from web search
- Clearly distinguish between facts from search results and your own analysis
- If search results are outdated or conflicting, mention this
- Recommend checking official documentation for critical decisions
- Provide version numbers and dates when discussing packages/tools
- Be explicit about what information comes from search vs. your training data

**Response Format:**
1. Summarize key findings from web search
2. Provide your analysis and recommendations
3. List sources for verification
4. Suggest next steps or follow-up research if needed''';
  }

  String _getRequirementsPrompt(String planContext) {
    return '''You are a Planning AI assistant helping users create structured requirements following EARS patterns.

**Your Role (Requirements 2.2):**
- Help break down ideas into formal requirements
- Use EARS (Easy Approach to Requirements Syntax) patterns:
  • Ubiquitous: THE <system> SHALL <response>
  • Event-driven: WHEN <trigger>, THE <system> SHALL <response>
  • State-driven: WHILE <condition>, THE <system> SHALL <response>
  • Unwanted: IF <condition>, THEN THE <system> SHALL <response>
  • Optional: WHERE <option>, THE <system> SHALL <response>
  • Complex: Combination of above patterns

**Context:**
$planContext

**Guidelines:**
- Generate requirements that are testable and measurable
- Include acceptance criteria for each requirement
- Avoid vague terms like "quickly", "user-friendly"
- Use active voice and specific terminology
- Number requirements clearly

**Response Format:**
When generating requirements, use this format:

### Requirement [N]: [Title]
**User Story:** As a [role], I want [feature], so that [benefit]
**EARS Pattern:** [pattern type]
**Acceptance Criteria:**
1. [Criterion 1]
2. [Criterion 2]
...

Ask if the user wants to add these requirements to their plan.''';
  }

  String _getTasksPrompt(String planContext) {
    return '''You are a Planning AI assistant helping users create actionable tasks from requirements.

**Your Role (Requirements 2.3):**
- Break down requirements into discrete, actionable tasks
- Ensure tasks are specific and achievable
- Suggest appropriate priority levels
- Identify dependencies between tasks

**Context:**
$planContext

**Guidelines:**
- Each task should be completable in a reasonable timeframe
- Include clear descriptions of what needs to be done
- Reference which requirements each task addresses
- Suggest sub-tasks for complex items
- Consider the logical order of implementation

**Response Format:**
When generating tasks, use this format:

### Task [N]: [Title]
**Description:** [What needs to be done]
**Priority:** [Low/Medium/High/Critical]
**Requirements:** [Which requirements this addresses]
**Sub-tasks (if any):**
- [ ] Sub-task 1
- [ ] Sub-task 2

Ask if the user wants to add these tasks to their plan.''';
  }

  String _getDesignPrompt(String planContext) {
    return '''You are a Planning AI assistant helping users create design notes and architectural decisions.

**Your Role:**
- Help document design decisions and architectural choices
- Create technical notes that explain HOW requirements will be implemented
- Document trade-offs, alternatives considered, and rationale
- Link design decisions to specific requirements

**Context:**
$planContext

**Guidelines:**
- Focus on technical implementation details
- Document architectural patterns and approaches
- Explain the reasoning behind design choices
- Consider scalability, maintainability, and performance
- Reference which requirements each design note addresses

**Response Format:**
When generating design notes, use this format:

### Design Note [N]: [Title]
**Content:** [Technical description of the design decision]
**Rationale:** [Why this approach was chosen]
**Requirements:** [Which requirements this addresses]
**Alternatives Considered:** [Other options that were evaluated]

Ask if the user wants to add these design notes to their plan.''';
  }

  /// Generate requirements from the conversation (Requirements 2.2)
  Future<void> _generateRequirements() async {
    if (_isLoading) return;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * 2,
      feature: 'planning_generate_requirements',
    );
    if (!hasCredits) return;

    setState(() => _isLoading = true);

    try {
      // Gather conversation context
      final conversationSummary =
          _messages.where((m) => m.isUser).map((m) => m.text).join('\n');

      final prompt =
          '''Based on our conversation, generate structured requirements following EARS patterns.

**Conversation Summary:**
$conversationSummary

**Instructions:**
1. Identify the key features and functionalities discussed
2. Create formal requirements using EARS patterns
3. Include acceptance criteria for each requirement
4. Number requirements sequentially

Generate 3-5 requirements that capture the core functionality discussed.''';

      final aiNotifier = ref.read(aiProvider.notifier);
      await aiNotifier.generateContent(
        prompt,
        style: ChatStyle.standard,
      );

      final aiState = ref.read(aiProvider);
      if (aiState.error != null) {
        throw Exception(aiState.error);
      }

      final response = aiState.lastResponse ?? '';

      setState(() {
        _messages.add(_PlanningMessage(
          text: '📋 **Generated Requirements:**\n\n$response',
          isUser: false,
          timestamp: DateTime.now(),
          hasActions: true,
          actionType: _ActionType.requirements,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_PlanningMessage(
          text: '❌ Failed to generate requirements: ${e.toString()}',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
    }
  }

  /// Generate tasks from requirements (Requirements 2.3)
  Future<void> _generateTasks() async {
    if (_isLoading) return;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * 2,
      feature: 'planning_generate_tasks',
    );
    if (!hasCredits) return;

    final planState = ref.read(planningProvider);
    final currentPlan = planState.currentPlan;

    if (currentPlan == null || currentPlan.requirements.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Please add requirements first before generating tasks'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final requirementsList = currentPlan.requirements
          .map((r) =>
              '${r.title}: ${r.description}\nAcceptance Criteria: ${r.acceptanceCriteria.join(", ")}')
          .join('\n\n');

      final prompt = '''Generate actionable tasks from these requirements:

**Requirements:**
$requirementsList

**Instructions:**
1. Break down each requirement into discrete tasks
2. Assign appropriate priority levels
3. Identify any dependencies
4. Suggest sub-tasks for complex items

Generate tasks that will fully implement all requirements.''';

      final aiNotifier = ref.read(aiProvider.notifier);
      await aiNotifier.generateContent(
        prompt,
        style: ChatStyle.standard,
      );

      final aiState = ref.read(aiProvider);
      if (aiState.error != null) {
        throw Exception(aiState.error);
      }

      final response = aiState.lastResponse ?? '';

      setState(() {
        _messages.add(_PlanningMessage(
          text: '✅ **Generated Tasks:**\n\n$response',
          isUser: false,
          timestamp: DateTime.now(),
          hasActions: true,
          actionType: _ActionType.tasks,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_PlanningMessage(
          text: '❌ Failed to generate tasks: ${e.toString()}',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
    }
  }

  /// Generate design notes from requirements
  Future<void> _generateDesignNotes() async {
    if (_isLoading) return;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * 2,
      feature: 'planning_generate_design_notes',
    );
    if (!hasCredits) return;

    final planState = ref.read(planningProvider);
    final currentPlan = planState.currentPlan;

    if (currentPlan == null || currentPlan.requirements.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please add requirements first before generating design notes'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final requirementsList = currentPlan.requirements
          .map((r) =>
              '${r.title}: ${r.description}\nAcceptance Criteria: ${r.acceptanceCriteria.join(", ")}')
          .join('\n\n');

      final prompt =
          '''Generate design notes and architectural decisions for these requirements:

**Requirements:**
$requirementsList

**Instructions:**
1. Create design notes that explain HOW each requirement will be implemented
2. Document architectural decisions and patterns
3. Explain trade-offs and rationale
4. Consider technical constraints and best practices

Generate design notes that provide clear technical guidance for implementation.''';

      final aiNotifier = ref.read(aiProvider.notifier);
      await aiNotifier.generateContent(
        prompt,
        style: ChatStyle.standard,
      );

      final aiState = ref.read(aiProvider);
      if (aiState.error != null) {
        throw Exception(aiState.error);
      }

      final response = aiState.lastResponse ?? '';

      setState(() {
        _messages.add(_PlanningMessage(
          text: '📐 **Generated Design Notes:**\n\n$response',
          isUser: false,
          timestamp: DateTime.now(),
          hasActions: true,
          actionType: _ActionType.designNotes,
        ));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(_PlanningMessage(
          text: '❌ Failed to generate design notes: ${e.toString()}',
          isUser: false,
          timestamp: DateTime.now(),
          isError: true,
        ));
        _isLoading = false;
      });
    }
  }

  /// Show dialog to add generated content to plan (Requirements 2.4)
  void _showAddToplanDialog(_ActionType type) {
    final planState = ref.read(planningProvider);
    final currentPlan = planState.currentPlan;

    if (currentPlan == null) {
      _showCreatePlanFirstDialog();
      return;
    }

    String typeLabel;
    IconData typeIcon;
    switch (type) {
      case _ActionType.requirements:
        typeLabel = 'requirements';
        typeIcon = LucideIcons.fileText;
        break;
      case _ActionType.tasks:
        typeLabel = 'tasks';
        typeIcon = LucideIcons.listChecks;
        break;
      case _ActionType.designNotes:
        typeLabel = 'design notes';
        typeIcon = LucideIcons.penTool;
        break;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              typeIcon,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Text('Add ${typeLabel[0].toUpperCase()}${typeLabel.substring(1)}'),
          ],
        ),
        content: Text(
          'Add the generated $typeLabel '
          'to "${currentPlan.title}"?\n\n'
          'You can edit them later from the project workspace.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addGeneratedContentToPlan(type);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showCreatePlanFirstDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(LucideIcons.alertCircle, color: Colors.orange),
            SizedBox(width: 12),
            Text('No Project Selected'),
          ],
        ),
        content: const Text(
          'Please create or select a project workspace first before adding requirements, tasks, or design notes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addGeneratedContentToPlan(_ActionType type) async {
    final planState = ref.read(planningProvider);
    final currentPlan = planState.currentPlan;

    if (currentPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No project selected')),
      );
      return;
    }

    // Find the last AI message with generated content
    final lastGeneratedMessage = _messages.reversed.firstWhere(
      (m) => !m.isUser && m.hasActions && m.actionType == type,
      orElse: () => _PlanningMessage(
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    if (lastGeneratedMessage.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No generated content found')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final planningNotifier = ref.read(planningProvider.notifier);

      if (type == _ActionType.requirements) {
        // Parse and add requirements
        final requirements =
            _parseRequirementsFromMarkdown(lastGeneratedMessage.text);
        if (requirements.isEmpty) {
          throw Exception('Could not parse any requirements from the response');
        }

        // Add all requirements without reloading after each one
        for (int i = 0; i < requirements.length; i++) {
          final req = requirements[i];
          final isLast = i == requirements.length - 1;
          await planningNotifier.createRequirement(
            title: req['title'] as String,
            description: req['description'] as String?,
            earsPattern: req['earsPattern'] as String?,
            acceptanceCriteria:
                (req['acceptanceCriteria'] as List<String>?) ?? [],
            reloadPlan: isLast, // Only reload on the last one
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Added ${requirements.length} requirements to project'),
            action: SnackBarAction(
              label: 'View Project',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        );
      } else if (type == _ActionType.tasks) {
        // Parse and add tasks
        final tasks = _parseTasksFromMarkdown(lastGeneratedMessage.text);
        if (tasks.isEmpty) {
          throw Exception('Could not parse any tasks from the response');
        }

        for (final task in tasks) {
          await planningNotifier.createTask(
            title: task['title'] as String,
            description: task['description'] as String?,
            priority: _parsePriority(task['priority'] as String?),
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${tasks.length} tasks to project'),
            action: SnackBarAction(
              label: 'View Project',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        );
      } else if (type == _ActionType.designNotes) {
        // Parse and add design notes
        final notes = _parseDesignNotesFromMarkdown(lastGeneratedMessage.text);
        if (notes.isEmpty) {
          throw Exception('Could not parse any design notes from the response');
        }

        for (final note in notes) {
          await planningNotifier.createDesignNote(
            content: note['content'] as String,
            requirementIds: (note['requirementIds'] as List<String>?) ?? [],
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${notes.length} design notes to project'),
            action: SnackBarAction(
              label: 'View Project',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Parse requirements from AI-generated markdown - flexible parser
  List<Map<String, dynamic>> _parseRequirementsFromMarkdown(String markdown) {
    final requirements = <Map<String, dynamic>>[];

    // Try multiple patterns to match requirement blocks
    // Pattern 1: ### Requirement [N]: [Title] or ### Requirement N: [Title]
    var reqPattern = RegExp(
      r'#{1,3}\s*Requirement\s*[\[\(]?\d+[\]\)]?[:\.\s]+([^\n]+)',
      caseSensitive: false,
    );
    var matches = reqPattern.allMatches(markdown).toList();

    // Pattern 2: **Requirement N:** or **N.** format
    if (matches.isEmpty) {
      reqPattern = RegExp(
        r'\*\*(?:Requirement\s*)?(\d+)[:\.\)]*\*\*\s*([^\n]+)',
        caseSensitive: false,
      );
      matches = reqPattern.allMatches(markdown).toList();
    }

    // Pattern 3: Numbered list (1. Title)
    if (matches.isEmpty) {
      reqPattern = RegExp(
        r'^\s*(\d+)[\.\)]\s+([^\n]+)',
        multiLine: true,
      );
      matches = reqPattern.allMatches(markdown).toList();
    }

    for (final match in matches) {
      // Get title from appropriate group
      String title;
      if (match.groupCount >= 2) {
        title = match.group(2)?.trim() ?? match.group(1)?.trim() ?? '';
      } else {
        title = match.group(1)?.trim() ?? '';
      }
      if (title.isEmpty) continue;

      // Skip if it looks like a sub-item
      final lowerTitle = title.toLowerCase();
      if (lowerTitle.startsWith('acceptance') ||
          lowerTitle.startsWith('criterion') ||
          lowerTitle.startsWith('sub-task') ||
          lowerTitle.startsWith('description:')) {
        continue;
      }

      // Get content section for this requirement
      final startIndex = match.end;
      final nextMatchIndex = matches
          .where((m) => m.start > match.start)
          .map((m) => m.start)
          .cast<int?>()
          .firstOrNull;
      final endIndex = nextMatchIndex ?? markdown.length;
      final content = markdown.substring(startIndex, endIndex);

      // Extract description
      String? description;
      final userStoryMatch = RegExp(
        r'\*\*User Story[:\s]*\*\*\s*([^\n]+(?:\n(?!\*\*)[^\n]+)*)',
        caseSensitive: false,
      ).firstMatch(content);
      if (userStoryMatch != null) {
        description = userStoryMatch.group(1)?.trim();
      }

      // Extract EARS pattern
      String? earsPattern;
      final patternMatch = RegExp(
        r'\*\*(?:EARS\s*)?Pattern[:\s]*\*\*\s*(\w+)',
        caseSensitive: false,
      ).firstMatch(content);
      if (patternMatch != null) {
        final pattern = patternMatch.group(1)?.toLowerCase();
        if (['ubiquitous', 'event', 'state', 'unwanted', 'optional', 'complex']
            .contains(pattern)) {
          earsPattern = pattern;
        }
      }

      // Extract acceptance criteria
      final acceptanceCriteria = <String>[];
      final criteriaMatch = RegExp(
        r'\*\*Acceptance Criteria[:\s]*\*\*([^*]+?)(?=\n\*\*|\n#{1,3}|$)',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(content);
      if (criteriaMatch != null) {
        final criteriaText = criteriaMatch.group(1) ?? '';
        final criteriaLines =
            RegExp(r'^\s*(?:\d+[\.\)]|-|\*)\s*(.+)', multiLine: true)
                .allMatches(criteriaText);
        for (final line in criteriaLines) {
          final criterion = line.group(1)?.trim();
          if (criterion != null && criterion.isNotEmpty) {
            acceptanceCriteria.add(criterion);
          }
        }
      }

      requirements.add({
        'title': title,
        'description': description,
        'earsPattern': earsPattern,
        'acceptanceCriteria': acceptanceCriteria,
      });
    }

    // Fallback: extract from plain text lines
    if (requirements.isEmpty) {
      final lines = markdown.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.length < 10 || trimmed.length > 300) {
          continue;
        }
        if (trimmed.startsWith('#') && !trimmed.contains('Requirement')) {
          continue;
        }
        if (trimmed.startsWith('**Generated') || trimmed.startsWith('📋')) {
          continue;
        }
        if (trimmed.toLowerCase().contains('acceptance criteria')) continue;

        // Clean up the title
        var title = trimmed
            .replaceFirst(RegExp(r'^#{1,3}\s*'), '')
            .replaceFirst(RegExp(r'^[\d\.\)\-\*\[\]]+\s*'), '')
            .replaceAll(RegExp(r'\*\*'), '')
            .trim();

        if (title.isNotEmpty && title.length > 5) {
          requirements.add({
            'title': title,
            'description': null,
            'earsPattern': null,
            'acceptanceCriteria': <String>[],
          });
        }
      }
    }

    return requirements;
  }

  /// Parse tasks from AI-generated markdown - flexible parser
  List<Map<String, dynamic>> _parseTasksFromMarkdown(String markdown) {
    final tasks = <Map<String, dynamic>>[];

    // Try multiple patterns
    var taskPattern = RegExp(
      r'#{1,3}\s*Task\s*[\[\(]?\d+[\]\)]?[:\.\s]+([^\n]+)',
      caseSensitive: false,
    );
    var matches = taskPattern.allMatches(markdown).toList();

    if (matches.isEmpty) {
      taskPattern = RegExp(
        r'\*\*(?:Task\s*)?(\d+)[:\.\)]*\*\*\s*([^\n]+)',
        caseSensitive: false,
      );
      matches = taskPattern.allMatches(markdown).toList();
    }

    if (matches.isEmpty) {
      taskPattern = RegExp(
        r'^\s*(\d+)[\.\)]\s+([^\n]+)',
        multiLine: true,
      );
      matches = taskPattern.allMatches(markdown).toList();
    }

    for (final match in matches) {
      String title;
      if (match.groupCount >= 2) {
        title = match.group(2)?.trim() ?? match.group(1)?.trim() ?? '';
      } else {
        title = match.group(1)?.trim() ?? '';
      }
      if (title.isEmpty) continue;
      if (title.toLowerCase().startsWith('sub-task')) continue;

      final startIndex = match.end;
      final nextMatchIndex = matches
          .where((m) => m.start > match.start)
          .map((m) => m.start)
          .cast<int?>()
          .firstOrNull;
      final endIndex = nextMatchIndex ?? markdown.length;
      final content = markdown.substring(startIndex, endIndex);

      String? description;
      final descMatch = RegExp(
        r'\*\*Description[:\s]*\*\*\s*([^\n]+(?:\n(?!\*\*)[^\n]+)*)',
        caseSensitive: false,
      ).firstMatch(content);
      if (descMatch != null) {
        description = descMatch.group(1)?.trim();
      }

      String? priority;
      final priorityMatch = RegExp(
        r'\*\*Priority[:\s]*\*\*\s*(\w+)',
        caseSensitive: false,
      ).firstMatch(content);
      if (priorityMatch != null) {
        priority = priorityMatch.group(1)?.toLowerCase();
      }

      tasks.add({
        'title': title,
        'description': description,
        'priority': priority,
      });
    }

    // Fallback
    if (tasks.isEmpty) {
      final lines = markdown.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.length < 5 || trimmed.length > 300) {
          continue;
        }
        if (trimmed.startsWith('#') && !trimmed.contains('Task')) {
          continue;
        }
        if (trimmed.startsWith('**Generated') || trimmed.startsWith('✅')) {
          continue;
        }

        var title = trimmed
            .replaceFirst(RegExp(r'^#{1,3}\s*'), '')
            .replaceFirst(RegExp(r'^[\d\.\)\-\*\[\]]+\s*'), '')
            .replaceAll(RegExp(r'\*\*'), '')
            .trim();

        if (title.isNotEmpty && title.length > 3) {
          tasks.add({
            'title': title,
            'description': null,
            'priority': null,
          });
        }
      }
    }

    return tasks;
  }

  /// Parse design notes from AI-generated markdown
  List<Map<String, dynamic>> _parseDesignNotesFromMarkdown(String markdown) {
    final notes = <Map<String, dynamic>>[];

    // Pattern to match design note blocks
    // ### Design Note [N]: [Title]
    final notePattern = RegExp(
      r'###\s*Design\s*Note\s*\[?\d+\]?:?\s*(.+?)(?=\n)',
      caseSensitive: false,
    );

    // Find all design note headers
    final matches = notePattern.allMatches(markdown);

    for (final match in matches) {
      final title = match.group(1)?.trim() ?? '';
      if (title.isEmpty) continue;

      // Get the content after this header until the next header or end
      final startIndex = match.end;
      final nextMatch =
          notePattern.allMatches(markdown.substring(startIndex)).firstOrNull;
      final endIndex =
          nextMatch != null ? startIndex + nextMatch.start : markdown.length;
      final content = markdown.substring(startIndex, endIndex);

      // Extract content/description
      String noteContent = title; // Default to title if no content found
      final contentMatch =
          RegExp(r'\*\*Content:\*\*\s*(.+?)(?=\n\*\*|\n###|$)', dotAll: true)
              .firstMatch(content);
      if (contentMatch != null) {
        noteContent = contentMatch.group(1)?.trim() ?? title;
      }

      // Also try to extract rationale and append it
      final rationaleMatch =
          RegExp(r'\*\*Rationale:\*\*\s*(.+?)(?=\n\*\*|\n###|$)', dotAll: true)
              .firstMatch(content);
      if (rationaleMatch != null) {
        final rationale = rationaleMatch.group(1)?.trim();
        if (rationale != null && rationale.isNotEmpty) {
          noteContent = '$noteContent\n\nRationale: $rationale';
        }
      }

      // Extract requirement IDs if mentioned
      final requirementIds = <String>[];
      // For now, we don't parse requirement IDs from markdown
      // They would need to be matched against existing requirements

      notes.add({
        'content': noteContent,
        'requirementIds': requirementIds,
      });
    }

    // If no structured notes found, try to parse as plain text sections
    if (notes.isEmpty) {
      // Split by numbered items or bullet points
      final lines = markdown.split('\n');
      final buffer = StringBuffer();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        // Skip header lines
        if (trimmed.startsWith('#')) continue;
        if (trimmed.startsWith('**Generated') || trimmed.startsWith('📐')) {
          continue;
        }

        buffer.writeln(trimmed);
      }

      final fullContent = buffer.toString().trim();
      if (fullContent.isNotEmpty) {
        notes.add({
          'content': fullContent,
          'requirementIds': <String>[],
        });
      }
    }

    return notes;
  }

  TaskPriority _parsePriority(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      case 'critical':
        return TaskPriority.critical;
      default:
        return TaskPriority.medium;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final planState = ref.watch(planningProvider);
    final currentPlan = planState.currentPlan;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with gradient header
          SliverAppBar(
            floating: false,
            pinned: true,
            expandedHeight: 140,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.premiumGradient,
                ),
                child: Stack(
                  children: [
                    // Decorative elements
                    Positioned(
                      top: -30,
                      right: -30,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  LucideIcons.brain,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Project Assistant',
                                          style: text.titleLarge?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (currentPlan != null)
                                        Text(
                                          currentPlan.title,
                                          style: text.bodySmall?.copyWith(
                                            color: Colors.white
                                                .withValues(alpha: 0.8),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ).animate().fadeIn().slideX(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              // Mode selector
              PopupMenuButton<_PlanningMode>(
                icon: const Icon(Icons.tune, color: Colors.white),
                tooltip: 'Assistant Modes',
                onSelected: (mode) => setState(() => _currentMode = mode),
                itemBuilder: (ctx) => [
                  _buildModeMenuItem(
                    _PlanningMode.brainstorm,
                    LucideIcons.lightbulb,
                    'Brainstorm',
                    'Explore and refine ideas',
                  ),
                  _buildModeMenuItem(
                    _PlanningMode.research,
                    LucideIcons.search,
                    'Research',
                    'Search web for latest info',
                  ),
                  _buildModeMenuItem(
                    _PlanningMode.requirements,
                    LucideIcons.fileText,
                    'Requirements',
                    'Generate EARS requirements',
                  ),
                  _buildModeMenuItem(
                    _PlanningMode.design,
                    LucideIcons.penTool,
                    'Design',
                    'Create design notes',
                  ),
                  _buildModeMenuItem(
                    _PlanningMode.tasks,
                    LucideIcons.listChecks,
                    'Tasks',
                    'Create actionable tasks',
                  ),
                ],
              ),
              // Web search toggle
              IconButton(
                icon: Icon(
                  _webSearchEnabled ? LucideIcons.globe : LucideIcons.globe2,
                  color: _webSearchEnabled ? Colors.white : Colors.white54,
                ),
                onPressed: () {
                  setState(() => _webSearchEnabled = !_webSearchEnabled);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _webSearchEnabled 
                          ? '🌐 Web search enabled' 
                          : '🔒 Web search disabled',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                tooltip: _webSearchEnabled ? 'Disable Web Search' : 'Enable Web Search',
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _messages.clear();
                    _initializeChat();
                  });
                },
                tooltip: 'Clear Chat',
              ),
            ],
          ),

          // Mode indicator
          SliverToBoxAdapter(
            child: _ModeIndicator(
              currentMode: _currentMode,
              onModeChanged: (mode) => setState(() => _currentMode = mode),
            ),
          ),

          // Messages list
          SliverFillRemaining(
            child: Column(
              children: [
                // Search indicator
                if (_isSearching)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '🔍 Searching the web...',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                          ),
                        ),
                        if (_lastSearchResults.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '(${_lastSearchResults.length} results)',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isLoading) {
                        return const _TypingIndicator();
                      }
                      final message = _messages[index];
                      return _MessageBubble(
                        message: message,
                        onAddToPlan: message.hasActions
                            ? () => _showAddToplanDialog(message.actionType!)
                            : null,
                      ).animate().fadeIn(
                            delay: Duration(milliseconds: index * 50),
                          );
                    },
                  ),
                ),

                // Quick actions
                _QuickActionsBar(
                  onGenerateRequirements: _generateRequirements,
                  onGenerateTasks: _generateTasks,
                  onGenerateDesignNotes: _generateDesignNotes,
                  isLoading: _isLoading,
                  currentMode: _currentMode,
                ),

                // Input area
                _ChatInputArea(
                  controller: _controller,
                  onSend: _sendMessage,
                  isLoading: _isLoading,
                  currentMode: _currentMode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_PlanningMode> _buildModeMenuItem(
    _PlanningMode mode,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final isSelected = _currentMode == mode;
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected ? scheme.primary : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? scheme.primary : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
          if (isSelected)
            Icon(LucideIcons.check, size: 16, color: scheme.primary),
        ],
      ),
    );
  }
}

// ==================== ENUMS ====================

enum _PlanningMode {
  brainstorm,
  research,
  requirements,
  design,
  tasks,
}

enum _ActionType {
  requirements,
  tasks,
  designNotes,
}

// ==================== DATA CLASSES ====================

class _PlanningMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  final bool hasActions;
  final _ActionType? actionType;

  _PlanningMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
    this.hasActions = false,
    this.actionType,
  });
}

// ==================== WIDGETS ====================

/// Mode indicator showing current planning mode
class _ModeIndicator extends StatelessWidget {
  final _PlanningMode currentMode;
  final ValueChanged<_PlanningMode> onModeChanged;

  const _ModeIndicator({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: scheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ModeChip(
              icon: LucideIcons.lightbulb,
              label: 'Brainstorm',
              isSelected: currentMode == _PlanningMode.brainstorm,
              onTap: () => onModeChanged(_PlanningMode.brainstorm),
            ),
            const SizedBox(width: 8),
            _ModeChip(
              icon: LucideIcons.search,
              label: 'Research',
              isSelected: currentMode == _PlanningMode.research,
              onTap: () => onModeChanged(_PlanningMode.research),
            ),
            const SizedBox(width: 8),
            _ModeChip(
              icon: LucideIcons.fileText,
              label: 'Requirements',
              isSelected: currentMode == _PlanningMode.requirements,
              onTap: () => onModeChanged(_PlanningMode.requirements),
            ),
            const SizedBox(width: 8),
            _ModeChip(
              icon: LucideIcons.penTool,
              label: 'Design',
              isSelected: currentMode == _PlanningMode.design,
              onTap: () => onModeChanged(_PlanningMode.design),
            ),
            const SizedBox(width: 8),
            _ModeChip(
              icon: LucideIcons.listChecks,
              label: 'Tasks',
              isSelected: currentMode == _PlanningMode.tasks,
              onTap: () => onModeChanged(_PlanningMode.tasks),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message bubble widget
class _MessageBubble extends StatelessWidget {
  final _PlanningMessage message;
  final VoidCallback? onAddToPlan;

  const _MessageBubble({
    required this.message,
    this.onAddToPlan,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isUser
                    ? scheme.primary
                    : message.isError
                        ? scheme.errorContainer
                        : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: MarkdownBody(
                data: message.text,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: isUser
                        ? scheme.onPrimary
                        : message.isError
                            ? scheme.onErrorContainer
                            : scheme.onSurface,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  strong: TextStyle(
                    color: isUser ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  listBullet: TextStyle(
                    color: isUser ? scheme.onPrimary : scheme.onSurface,
                  ),
                  h3: TextStyle(
                    color: isUser ? scheme.onPrimary : scheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                onTapLink: (text, href, title) {
                  if (href != null) {
                    launchUrl(Uri.parse(href));
                  }
                },
              ),
            ),
            // Action buttons for generated content
            if (message.hasActions && onAddToPlan != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: onAddToPlan,
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: Text(
                      message.actionType == _ActionType.requirements
                          ? 'Add Requirements'
                          : message.actionType == _ActionType.designNotes
                              ? 'Add Design Notes'
                              : 'Add Tasks',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Timestamp
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Typing indicator widget
class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TypingDot(delay: 0),
            SizedBox(width: 4),
            _TypingDot(delay: 150),
            SizedBox(width: 4),
            _TypingDot(delay: 300),
          ],
        ),
      ),
    );
  }
}

class _TypingDot extends StatelessWidget {
  final int delay;

  const _TypingDot({required this.delay});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.6),
        shape: BoxShape.circle,
      ),
    )
        .animate(
          onPlay: (controller) => controller.repeat(reverse: true),
        )
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.3, 1.3),
          duration: const Duration(milliseconds: 400),
          delay: Duration(milliseconds: delay),
        )
        .fadeIn(
          duration: const Duration(milliseconds: 200),
          delay: Duration(milliseconds: delay),
        );
  }
}

/// Quick actions bar for generating content
class _QuickActionsBar extends StatelessWidget {
  final VoidCallback onGenerateRequirements;
  final VoidCallback onGenerateTasks;
  final VoidCallback onGenerateDesignNotes;
  final bool isLoading;
  final _PlanningMode currentMode;

  const _QuickActionsBar({
    required this.onGenerateRequirements,
    required this.onGenerateTasks,
    required this.onGenerateDesignNotes,
    required this.isLoading,
    required this.currentMode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QuickActionButton(
              icon: LucideIcons.fileText,
              label: 'Generate Requirements',
              onTap: isLoading ? null : onGenerateRequirements,
              isHighlighted: currentMode == _PlanningMode.requirements,
            ),
            const SizedBox(width: 8),
            _QuickActionButton(
              icon: LucideIcons.penTool,
              label: 'Generate Design Notes',
              onTap: isLoading ? null : onGenerateDesignNotes,
              isHighlighted: currentMode == _PlanningMode.design,
            ),
            const SizedBox(width: 8),
            _QuickActionButton(
              icon: LucideIcons.listChecks,
              label: 'Generate Tasks',
              onTap: isLoading ? null : onGenerateTasks,
              isHighlighted: currentMode == _PlanningMode.tasks,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEnabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isHighlighted
                ? scheme.primary.withValues(alpha: 0.1)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isHighlighted
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isEnabled
                    ? (isHighlighted ? scheme.primary : scheme.onSurface)
                    : scheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isHighlighted ? FontWeight.w600 : FontWeight.normal,
                  color: isEnabled
                      ? (isHighlighted ? scheme.primary : scheme.onSurface)
                      : scheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chat input area
class _ChatInputArea extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isLoading;
  final _PlanningMode currentMode;

  const _ChatInputArea({
    required this.controller,
    required this.onSend,
    required this.isLoading,
    required this.currentMode,
  });

  String _getHintText() {
    switch (currentMode) {
      case _PlanningMode.brainstorm:
        return 'Describe your project idea...';
      case _PlanningMode.research:
        return 'Search for latest versions, best practices...';
      case _PlanningMode.requirements:
        return 'What features do you need?';
      case _PlanningMode.design:
        return 'What design decisions need to be made?';
      case _PlanningMode.tasks:
        return 'What tasks should be created?';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: TextField(
                controller: controller,
                enabled: !isLoading,
                decoration: InputDecoration(
                  hintText: _getHintText(),
                  hintStyle: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: IconButton.filled(
              onPressed: isLoading ? null : onSend,
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(LucideIcons.send),
              style: IconButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                disabledBackgroundColor: scheme.primary.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
