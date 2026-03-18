import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/api/api_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<OnboardingPage> _pages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPages();
  }

  Future<void> _loadPages() async {
    try {
      final api = ref.read(apiServiceProvider);
      final token = await api.getToken();
      if (token == null) {
        _useDefaultPages();
        return;
      }

      final dbScreens = await api.getOnboardingScreens();

      if (dbScreens.isNotEmpty) {
        setState(() {
          _pages = dbScreens
              .map((data) => OnboardingPage(
                    title: data['title'] ?? '',
                    description: data['description'] ?? '',
                    imageUrl: data['image_url'] ?? '',
                    icon: _getIconByName(data['icon_name']),
                  ))
              .toList();
          _isLoading = false;
        });
      } else {
        _useDefaultPages();
      }
    } catch (e) {
      debugPrint('Error loading onboarding screens: $e');
      _useDefaultPages();
    }
  }

  void _useDefaultPages() {
    setState(() {
      _pages = [
        OnboardingPage(
          title: 'Welcome to NoteClaw',
          description:
              'Your intelligent companion for organizing, understanding, and creating knowledge from any source. Now with advanced AI.',
          imageUrl: 'assets/images/onboarding_collaboration.png',
          icon: Icons.auto_awesome,
        ),
        OnboardingPage(
          title: 'Connect Any Data (MCP)',
          description:
              'Powered by the Model Context Protocol. Connect databases, local files, and remote APIs seamlessly to your AI context.',
          imageUrl: 'assets/images/onboarding_mcp.png',
          icon: Icons.hub,
        ),
        OnboardingPage(
          title: 'AI Coding Agent',
          description:
              'Build custom tools and apps directly within your notebook. Let the AI Coding Agent write and execute code for you.',
          imageUrl: 'assets/images/onboarding_coding_agent.png',
          icon: Icons.code,
        ),
        OnboardingPage(
          title: 'Deep Study & Research',
          description:
              'Analyze documents, generate study guides, and get citations. Your personal AI tutor is always ready to help.',
          imageUrl: 'assets/images/onboarding_ai_study.png',
          icon: Icons.school,
        ),
        OnboardingPage(
          title: 'Ready to Achieve',
          description:
              'Start your journey to higher productivity and smarter learning. Join the future of knowledge management.',
          imageUrl: 'assets/images/onboarding_success.png',
          icon: Icons.rocket_launch,
        ),
      ];
      _isLoading = false;
    });
  }

  IconData _getIconByName(String? name) {
    switch (name) {
      case 'upload_file':
        return Icons.upload_file;
      case 'chat_bubble_outline':
        return Icons.chat_bubble_outline;
      case 'create':
        return Icons.create;
      case 'rocket_launch':
        return Icons.rocket_launch;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'school':
        return Icons.school;
      case 'book':
        return Icons.book;
      case 'lightbulb':
        return Icons.lightbulb;
      case 'hub':
        return Icons.hub;
      case 'code':
        return Icons.code;
      default:
        return Icons.auto_awesome;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _skipOnboarding() {
    _finishOnboarding();
  }

  void _finishOnboarding() {
    // Navigate to completion screen
    context.go('/onboarding-completion');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: scheme.surface,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _skipOnboarding,
                  child: Text(
                    'Skip',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms),

              // Page content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, index) {
                          final page = _pages[index];
                          return _buildPage(page, scheme, text);
                        },
                      ),
              ),

              // Page indicators
              // Hide indicators if loading
              if (!_isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _currentPage == index
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.3),
                        ),
                      )
                          .animate()
                          .scale(duration: 300.ms, curve: Curves.easeOut),
                    ),
                  ),
                ),

              // Action button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentPage == _pages.length - 1
                              ? 'Get Started'
                              : 'Next',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _currentPage == _pages.length - 1
                              ? Icons.check
                              : Icons.arrow_forward,
                          color: scheme.onPrimary,
                        ),
                      ],
                    ),
                  ).animate().slideY(begin: 0.2, delay: 300.ms).fadeIn(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page, ColorScheme scheme, TextTheme text) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Prevent RenderFlex overflows on small viewports by scaling the hero image and spacing.
        final imageHeight =
            (constraints.maxHeight * 0.35).clamp(140.0, 240.0).toDouble();
        final beforeImageSpacing =
            (constraints.maxHeight * 0.07).clamp(24.0, 48.0).toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon badge
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  page.icon,
                  size: 48,
                  color: scheme.primary,
                ),
              ).animate().scale(duration: 600.ms, curve: Curves.easeOut),

              const SizedBox(height: 32),

              // Title
              Text(
                page.title,
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ).animate().slideY(begin: 0.2, delay: 100.ms).fadeIn(),

              const SizedBox(height: 16),

              // Description
              Text(
                page.description,
                style: text.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ).animate().slideY(begin: 0.2, delay: 200.ms).fadeIn(),

              SizedBox(height: beforeImageSpacing),

              // Generated image
              Container(
                height: imageHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: page.imageUrl.startsWith('http')
                      ? Image.network(
                          page.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.1),
                                    scheme.secondary.withValues(alpha: 0.1),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: scheme.primary,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.1),
                                    scheme.secondary.withValues(alpha: 0.1),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  page.icon,
                                  size: 64,
                                  color: scheme.primary.withValues(alpha: 0.5),
                                ),
                              ),
                            );
                          },
                        )
                      : Image.asset(
                          page.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint(
                                'Error loading asset image: ${page.imageUrl}, error: $error');
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.1),
                                    scheme.secondary.withValues(alpha: 0.1),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  page.icon,
                                  size: 64,
                                  color: scheme.primary.withValues(alpha: 0.5),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ).animate().slideY(begin: 0.3, delay: 300.ms).fadeIn(),
            ],
          ),
        );
      },
    );
  }
}

class OnboardingPage {
  final String title;
  final String description;
  final String imageUrl;
  final IconData icon;

  OnboardingPage({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.icon,
  });
}
