import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
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
              'Agreement to Terms',
              'By accessing or using NoteClaw, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use our services.',
            ),
            _buildSection(
              theme,
              'Description of Service',
              'NoteClaw is an AI-powered note-taking and research assistant application that helps you organize information, conduct research, and generate insights using artificial intelligence.',
            ),
            _buildSection(
              theme,
              'User Accounts',
              'To use certain features, you must create an account. You are responsible for:\n\n'
                  '• Maintaining the security of your account\n'
                  '• All activities that occur under your account\n'
                  '• Ensuring your account information is accurate\n'
                  '• Notifying us immediately of any unauthorized access',
            ),
            _buildSection(
              theme,
              'Acceptable Use',
              'You agree not to:\n\n'
                  '• Violate any laws or regulations\n'
                  '• Infringe on intellectual property rights\n'
                  '• Upload malicious code or viruses\n'
                  '• Attempt to gain unauthorized access to our systems\n'
                  '• Use the service to harass, abuse, or harm others\n'
                  '• Impersonate any person or entity\n'
                  '• Engage in any activity that disrupts the service',
            ),
            _buildSection(
              theme,
              'User Content',
              'You retain all rights to the content you create. By using our service, you grant us a license to:\n\n'
                  '• Store and process your content to provide the service\n'
                  '• Use anonymized data to improve our services\n\n'
                  'You represent that you have all necessary rights to the content you upload.',
            ),
            _buildSection(
              theme,
              'AI-Generated Content',
              'AI-generated content is provided "as is" without warranties. You are responsible for:\n\n'
                  '• Verifying the accuracy of AI-generated content\n'
                  '• Ensuring compliance with applicable laws\n'
                  '• Not using AI output for illegal or harmful purposes',
            ),
            _buildSection(
              theme,
              'Subscription and Payments',
              'Certain features require a paid subscription. You agree to:\n\n'
                  '• Provide accurate billing information\n'
                  '• Pay all fees as described\n'
                  '• Subscriptions auto-renew unless cancelled\n'
                  '• Refunds are provided according to our refund policy',
            ),
            _buildSection(
              theme,
              'Intellectual Property',
              'The NoteClaw service, including its software, design, and content, is owned by us and protected by intellectual property laws. You may not copy, modify, or distribute our service without permission.',
            ),
            _buildSection(
              theme,
              'Disclaimers',
              'THE SERVICE IS PROVIDED "AS IS" WITHOUT WARRANTIES OF ANY KIND. WE DO NOT GUARANTEE:\n\n'
                  '• Uninterrupted or error-free service\n'
                  '• Accuracy of AI-generated content\n'
                  '• That the service will meet your requirements\n'
                  '• That data loss will not occur',
            ),
            _buildSection(
              theme,
              'Limitation of Liability',
              'TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR:\n\n'
                  '• Indirect, incidental, or consequential damages\n'
                  '• Loss of profits, data, or business opportunities\n'
                  '• Damages exceeding the amount you paid us in the last 12 months',
            ),
            _buildSection(
              theme,
              'Termination',
              'We may suspend or terminate your account if you violate these terms. You may cancel your account at any time. Upon termination:\n\n'
                  '• Your right to use the service ceases immediately\n'
                  '• We may delete your data after a reasonable period',
            ),
            _buildSection(
              theme,
              'Changes to Terms',
              'We reserve the right to modify these terms at any time. We will notify you of material changes. Continued use of the service after changes constitutes acceptance.',
            ),
            _buildSection(
              theme,
              'Governing Law',
              'These terms are governed by the laws of the jurisdiction in which we operate, without regard to conflict of law principles.',
            ),
            _buildSection(
              theme,
              'Contact Us',
              'For questions about these Terms of Service, contact us at:\n\n'
                  'Email: support@noteclaw.com',
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
