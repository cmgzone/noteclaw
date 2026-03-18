import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last updated: January 2026',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              theme,
              'Introduction',
              'NoteClaw ("we", "our", or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application and services.',
            ),
            _buildSection(
              theme,
              'Information We Collect',
              'We collect information that you provide directly to us, including:\n\n'
                  '• Account Information: Email address, name, and password\n'
                  '• Content: Notebooks, sources, notes, and other content you create\n'
                  '• Usage Data: How you interact with our services\n'
                  '• Device Information: Device type, operating system, and unique identifiers',
            ),
            _buildSection(
              theme,
              'How We Use Your Information',
              'We use the information we collect to:\n\n'
                  '• Provide, maintain, and improve our services\n'
                  '• Process your requests and transactions\n'
                  '• Send you technical notices and support messages\n'
                  '• Communicate with you about products, services, and events\n'
                  '• Monitor and analyze trends and usage\n'
                  '• Detect, prevent, and address technical issues',
            ),
            _buildSection(
              theme,
              'Data Storage and Security',
              'We use industry-standard security measures to protect your data. Your information is stored on secure servers and encrypted both in transit and at rest. However, no method of transmission over the Internet is 100% secure.',
            ),
            _buildSection(
              theme,
              'AI Processing',
              'When you use AI features, your content may be processed by third-party AI providers (such as OpenAI, Google Gemini, or Anthropic). We do not share your personal information with these providers beyond what is necessary to process your requests.',
            ),
            _buildSection(
              theme,
              'Data Sharing',
              'We do not sell your personal information. We may share your information with:\n\n'
                  '• Service providers who assist in operating our services\n'
                  '• When required by law or to protect our rights\n'
                  '• With your consent or at your direction',
            ),
            _buildSection(
              theme,
              'Your Rights',
              'You have the right to:\n\n'
                  '• Access your personal information\n'
                  '• Correct inaccurate data\n'
                  '• Request deletion of your data\n'
                  '• Export your data\n'
                  '• Opt-out of marketing communications',
            ),
            _buildSection(
              theme,
              'Children\'s Privacy',
              'Our services are not intended for children under 13 years of age. We do not knowingly collect personal information from children under 13.',
            ),
            _buildSection(
              theme,
              'Changes to This Policy',
              'We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Last updated" date.',
            ),
            _buildSection(
              theme,
              'Contact Us',
              'If you have questions about this Privacy Policy, please contact us at:\n\n'
                  'Email: privacy@noteclaw.com',
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ThemeData theme, String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
