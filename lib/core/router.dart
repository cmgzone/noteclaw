import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/motion.dart';
import 'auth/custom_auth_guard.dart';

import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/onboarding_completion_screen.dart';
import '../features/home/home_screen.dart';
import '../features/sources/enhanced_sources_screen.dart';
import '../features/chat/enhanced_chat_screen.dart';
import '../features/studio/studio_screen.dart';
import '../features/studio/artifact_viewer_screen.dart';
import '../features/studio/artifact.dart';
import '../features/search/web_search_screen.dart';
import '../features/studio/visual_studio_screen.dart';
import '../features/settings/ai_model_settings_screen.dart';
import '../features/auth/privacy_policy_screen.dart';
import '../features/auth/terms_of_service_screen.dart';
import '../features/settings/migrate_agent_id_screen.dart';
import '../features/notebook/notebook_detail_screen.dart';
import '../features/notebook/notebook_chat_screen.dart';
import '../features/notebook/notebook_research_screen.dart';
import '../features/chat/context_profile_screen.dart';
import '../ui/app_scaffold.dart';
import '../features/auth/custom_login_screen.dart';
import '../features/subscription/screens/subscription_screen.dart';
import '../features/subscription/screens/plan_selection_screen.dart';
import '../features/auth/security_settings_screen.dart';
import '../features/auth/password_reset_screen.dart';
import '../features/auth/email_verification_screen.dart';
import '../features/ebook/ui/ebook_creator_wizard.dart';
import '../features/ebook/ui/ebook_library_screen.dart';
import '../features/settings/background_settings_screen.dart';
import '../features/settings/api_keys_screen.dart';
// New learning tools imports
import '../features/flashcards/flashcards_list_screen.dart';
import '../features/flashcards/flashcard_deck_screen.dart';
import '../features/quiz/quizzes_list_screen.dart';
import '../features/quiz/quiz_screen.dart';
import '../features/mindmap/mind_map_screen.dart';
import '../features/infographics/infographics_list_screen.dart';
import '../features/meal_planner/meal_planner_screen.dart';
import '../features/story_generator/story_generator_screen.dart';
import '../features/ads/ads_generator_screen.dart';
import '../features/wellness/wellness_screen.dart';
import '../features/tutor/tutor_sessions_screen.dart';
import '../features/tutor/ai_tutor_screen.dart';
import '../features/gamification/gamification_hub_screen.dart';
import '../features/gamification/achievements_screen.dart';
import '../features/gamification/daily_challenges_screen.dart';
import '../features/language_learning/language_learning_hub.dart';
import '../features/language_learning/language_session_screen.dart';
import '../features/admin/ai_models_manager_screen.dart';
import '../features/ai_browser/ai_browser_screen.dart';
import '../features/settings/agent_connections_screen.dart';
import '../features/agent_skills/agent_skills_screen.dart';
import '../features/custom_agents/custom_agents_screen.dart';
import '../features/github/github_connect_screen.dart';
import '../features/github/github_repos_screen.dart';
import '../features/planning/ui/plans_list_screen.dart';
import '../features/planning/ui/plan_detail_screen.dart';
import '../features/planning/ui/planning_ai_screen.dart';
import '../features/planning/ui/ui_design_generator_screen.dart';
import '../features/planning/ui/project_prototype_screen.dart';
import '../features/code_review/code_review_screen.dart';
import '../features/social/ui/social_hub_screen.dart';
import '../features/social/ui/friends_screen.dart';
import '../features/social/ui/study_groups_screen.dart';
import '../features/social/ui/activity_feed_screen.dart';
import '../features/social/ui/social_leaderboard_screen.dart';
import '../features/social/ui/direct_chat_screen.dart';
import '../features/social/ui/conversations_screen.dart';
import '../features/social/ui/group_chat_screen.dart';
import '../features/social/ui/public_notebook_screen.dart';
import '../features/social/ui/public_plan_screen.dart';
import '../features/social/ui/profile_screen.dart';
import '../features/social/ui/edit_profile_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../core/error/not_found_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

String getInitialLocation(bool hasSeenOnboarding) {
  // On web, prefer the browser's actual path so deep links work correctly.
  // For example, opening https://app.com/notebook/:id should land on that
  // notebook rather than getting redirected to /home.
  if (kIsWeb) {
    final browserPath = Uri.base.path;
    // Only use the browser path if it looks like a real app route (not '/',
    // '/index.html', or an empty string which all mean "no deep link").
    final isDeepLink = browserPath.isNotEmpty &&
        browserPath != '/' &&
        !browserPath.endsWith('index.html');
    if (isDeepLink) {
      return browserPath;
    }
  }
  return hasSeenOnboarding ? '/home' : '/onboarding';
}

GoRouter createRouter(bool hasSeenOnboarding, ProviderContainer container) {
  final authNotifier = CustomAuthChangeNotifier(container);

  return GoRouter(
    initialLocation: getInitialLocation(hasSeenOnboarding),
    refreshListenable: authNotifier,
    redirect: createCustomAuthRedirect(container),
    errorBuilder: (context, state) => NotFoundScreen(state: state),
    routes: [
      // Public routes
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const OnboardingScreen()),
      ),
      GoRoute(
        path: '/onboarding-completion',
        name: 'onboarding-completion',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const OnboardingCompletionScreen()),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const CustomLoginScreen()),
      ),
      GoRoute(
        path: '/password-reset/:token',
        name: 'password-reset',
        pageBuilder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return buildTransitionPage(
            child: PasswordResetScreen(token: token),
          );
        },
      ),
      GoRoute(
        path: '/verify-email/:token',
        name: 'verify-email',
        pageBuilder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return buildTransitionPage(
            child: EmailVerificationScreen(token: token),
          );
        },
      ),

      // Protected routes with shell
      ShellRoute(
        builder: (context, state, child) => AppScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const HomeScreen()),
          ),
          GoRoute(
            path: '/category/:category',
            name: 'category-notebooks',
            pageBuilder: (context, state) {
              final categoryEncoded = state.pathParameters['category'] ?? '';
              final category = Uri.decodeComponent(categoryEncoded);
              return buildTransitionPage(
                child: CategoryNotebooksScreen(category: category),
              );
            },
          ),
          GoRoute(
            path: '/sources',
            name: 'sources',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const EnhancedSourcesScreen()),
          ),
          GoRoute(
            path: '/chat',
            name: 'chat',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const EnhancedChatScreen()),
          ),
          GoRoute(
            path: '/studio',
            name: 'studio',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const StudioScreen()),
          ),
          GoRoute(
            path: '/search',
            name: 'search',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const WebSearchScreen()),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const AIModelSettingsScreen()),
          ),
          GoRoute(
            path: '/settings/api-keys',
            name: 'api-keys',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const ApiKeysScreen()),
          ),
          GoRoute(
            path: '/migrate-agent-id',
            name: 'migrate-agent-id',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const MigrateAgentIdScreen()),
          ),
          GoRoute(
            path: '/subscription',
            name: 'subscription',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const SubscriptionScreen()),
          ),
          GoRoute(
            path: '/notebook/:id',
            name: 'notebook-detail',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: NotebookDetailScreen(notebookId: id),
              );
            },
          ),
          GoRoute(
            path: '/notebook/:id/studio',
            name: 'notebook-studio',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: StudioScreen(notebookId: id),
              );
            },
          ),
          GoRoute(
            path: '/notebook/:id/chat',
            name: 'notebook-chat',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: NotebookChatScreen(notebookId: id),
              );
            },
          ),
          GoRoute(
            path: '/notebook/:id/research',
            name: 'notebook-research',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: NotebookResearchScreen(notebookId: id),
              );
            },
          ),
          // Flashcard routes
          GoRoute(
            path: '/notebook/:id/flashcards',
            name: 'notebook-flashcards',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: FlashcardsListScreen(notebookId: id),
              );
            },
          ),
          // Quiz routes
          GoRoute(
            path: '/notebook/:id/quizzes',
            name: 'notebook-quizzes',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: QuizzesListScreen(notebookId: id),
              );
            },
          ),
          // Infographics route
          GoRoute(
            path: '/notebook/:id/infographics',
            name: 'notebook-infographics',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: InfographicsListScreen(notebookId: id),
              );
            },
          ),
          GoRoute(
            path: '/context-profile',
            name: 'context-profile',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const ContextProfileScreen()),
          ),
          GoRoute(
            path: '/security',
            name: 'security',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const SecuritySettingsScreen()),
          ),
          GoRoute(
            path: '/background-settings',
            name: 'background-settings',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const BackgroundSettingsScreen()),
          ),
          GoRoute(
            path: '/meal-planner',
            name: 'meal-planner',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const MealPlannerScreen()),
          ),
          GoRoute(
            path: '/story-generator',
            name: 'story-generator',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const StoryGeneratorScreen()),
          ),
          GoRoute(
            path: '/ads-generator',
            name: 'ads-generator',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const AdsGeneratorScreen()),
          ),
          GoRoute(
            path: '/wellness',
            name: 'wellness',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const WellnessScreen()),
          ),
          GoRoute(
            path: '/privacy-policy',
            name: 'privacy-policy',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const PrivacyPolicyScreen()),
          ),
          GoRoute(
            path: '/terms-of-service',
            name: 'terms-of-service',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const TermsOfServiceScreen()),
          ),
          // Gamification routes
          GoRoute(
            path: '/progress',
            name: 'progress',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const GamificationHubScreen()),
          ),
          GoRoute(
            path: '/achievements',
            name: 'achievements',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const AchievementsScreen()),
          ),
          GoRoute(
            path: '/daily-challenges',
            name: 'daily-challenges',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const DailyChallengesScreen()),
          ),
          // Tutor routes
          GoRoute(
            path: '/notebook/:id/tutor-sessions',
            name: 'tutor-sessions',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: TutorSessionsScreen(notebookId: id),
              );
            },
          ),
          GoRoute(
            path: '/notebook/:id/tutor',
            name: 'tutor',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              final extra = state.extra as Map<String, dynamic>?;
              final sessionId = extra?['sessionId'] as String?;
              return buildTransitionPage(
                child: AITutorScreen(notebookId: id, sessionId: sessionId),
              );
            },
          ),
          // Language Learning Routes
          GoRoute(
            path: '/language-learning',
            name: 'language-learning',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const LanguageLearningHub()),
          ),
          GoRoute(
            path: '/language-learning/:id',
            name: 'language-learning-session',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return buildTransitionPage(
                child: LanguageSessionScreen(sessionId: id),
              );
            },
          ),
          GoRoute(
            path: '/ai-browser',
            name: 'ai-browser',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const AIBrowserScreen()),
          ),
          GoRoute(
            path: '/agent-connections',
            name: 'agent-connections',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const AgentConnectionsScreen()),
          ),
          GoRoute(
            path: '/agent-skills',
            name: 'agent-skills',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const AgentSkillsScreen()),
          ),
          GoRoute(
            path: '/custom-agents',
            name: 'custom-agents',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const CustomAgentsScreen()),
          ),
          GoRoute(
            path: '/github',
            name: 'github',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const GitHubConnectScreen()),
          ),
          GoRoute(
            path: '/github/repos',
            name: 'github-repos',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const GitHubReposScreen()),
          ),
          // Planning Mode routes
          GoRoute(
            path: '/planning',
            name: 'planning',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const PlansListScreen()),
          ),
          GoRoute(
            path: '/planning/:id',
            name: 'plan-detail',
            pageBuilder: (context, state) {
              final planId = state.pathParameters['id']!;
              return buildTransitionPage(
                child: PlanDetailScreen(planId: planId),
              );
            },
          ),
          GoRoute(
            path: '/planning/:id/ai',
            name: 'planning-ai',
            pageBuilder: (context, state) {
              final planId = state.pathParameters['id'];
              return buildTransitionPage(
                child: PlanningAIScreen(planId: planId),
              );
            },
          ),
          GoRoute(
            path: '/planning/:id/ui-designer',
            name: 'ui-designer',
            pageBuilder: (context, state) {
              final planId = state.pathParameters['id']!;
              return buildTransitionPage(
                child: UIDesignGeneratorScreen(planId: planId),
              );
            },
          ),
          GoRoute(
            path: '/planning/:id/prototype',
            name: 'project-prototype',
            pageBuilder: (context, state) {
              final planId = state.pathParameters['id']!;
              return buildTransitionPage(
                child: ProjectPrototypeScreen(planId: planId),
              );
            },
          ),
          // Code Review route
          GoRoute(
            path: '/code-review',
            name: 'code-review',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const CodeReviewScreen()),
          ),
          // Notifications route
          GoRoute(
            path: '/notifications',
            name: 'notifications',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const NotificationsScreen()),
          ),
          // Social routes
          GoRoute(
            path: '/social',
            name: 'social',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const SocialHubScreen()),
          ),
          GoRoute(
            path: '/social/friends',
            name: 'friends',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const FriendsScreen()),
          ),
          GoRoute(
            path: '/social/groups',
            name: 'study-groups',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const StudyGroupsScreen()),
          ),
          GoRoute(
            path: '/social/feed',
            name: 'activity-feed',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const ActivityFeedScreen()),
          ),
          GoRoute(
            path: '/social/leaderboard',
            name: 'leaderboard',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const SocialLeaderboardScreen()),
          ),
          GoRoute(
            path: '/social/messages',
            name: 'messages',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const ConversationsScreen()),
          ),
          GoRoute(
            path: '/social/chat/:userId',
            name: 'direct-chat',
            pageBuilder: (context, state) {
              final userId = state.pathParameters['userId']!;
              final username = state.extra as String?;
              return buildTransitionPage(
                child: DirectChatScreen(userId: userId, username: username),
              );
            },
          ),
          GoRoute(
            path: '/social/group/:groupId/chat',
            name: 'group-chat',
            pageBuilder: (context, state) {
              final groupId = state.pathParameters['groupId']!;
              final groupName = state.extra as String?;
              return buildTransitionPage(
                child: GroupChatScreen(groupId: groupId, groupName: groupName),
              );
            },
          ),
          GoRoute(
            path: '/social/notebook/:notebookId',
            name: 'public-notebook',
            pageBuilder: (context, state) {
              final notebookId = state.pathParameters['notebookId']!;
              return buildTransitionPage(
                child: PublicNotebookScreen(notebookId: notebookId),
              );
            },
          ),
          GoRoute(
            path: '/social/plan/:planId',
            name: 'public-plan',
            pageBuilder: (context, state) {
              final planId = state.pathParameters['planId']!;
              return buildTransitionPage(
                child: PublicPlanScreen(planId: planId),
              );
            },
          ),
          GoRoute(
            path: '/social/profile',
            name: 'profile',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const ProfileScreen()),
          ),
          GoRoute(
            path: '/social/profile/edit',
            name: 'edit-profile',
            pageBuilder: (context, state) =>
                buildTransitionPage(child: const EditProfileScreen()),
          ),
        ],
      ),

      // Full-screen routes (no shell)
      GoRoute(
        path: '/plan-selection',
        name: 'plan-selection',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const PlanSelectionScreen()),
      ),
      GoRoute(
        path: '/visual-studio',
        name: 'visual-studio',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const VisualStudioScreen()),
      ),
      GoRoute(
        path: '/artifact',
        name: 'artifact',
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is Artifact) {
            return buildTransitionPage(
              child: ArtifactViewerScreen(artifact: extra),
            );
          }
          return buildTransitionPage(child: const StudioScreen());
        },
      ),
      GoRoute(
        path: '/ebook-creator',
        name: 'ebook-creator',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const EbookCreatorWizard()),
      ),
      GoRoute(
        path: '/ebooks',
        name: 'ebooks',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const EbookLibraryScreen()),
      ),
      // Flashcard study route
      GoRoute(
        path: '/flashcards/:id/study',
        name: 'flashcard-study',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return buildTransitionPage(
            child: FlashcardDeckScreen(deckId: id),
          );
        },
      ),
      // Quiz play route
      GoRoute(
        path: '/quiz/:id/play',
        name: 'quiz-play',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return buildTransitionPage(
            child: QuizScreen(quizId: id),
          );
        },
      ),
      // Mind map route
      GoRoute(
        path: '/mindmap/:id',
        name: 'mindmap',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return buildTransitionPage(
            child: MindMapScreen(mindMapId: id),
          );
        },
      ),
      GoRoute(
        path: '/admin/ai-models',
        name: 'admin-ai-models',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const AIModelsManagerScreen()),
      ),
    ],
  );
}
