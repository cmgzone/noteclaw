import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../core/services/background_ai_service.dart';

/// Provider for background service enabled state
final backgroundEnabledProvider = FutureProvider<bool>((ref) async {
  return await backgroundAIService.isEnabled;
});

/// Provider for background task status
final backgroundTaskStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return await backgroundAIService.getTaskStatus();
});

/// Provider for error log
final backgroundErrorLogProvider =
    FutureProvider<List<Map<String, String>>>((ref) async {
  return await backgroundAIService.getErrorLog();
});

class BackgroundSettingsScreen extends ConsumerStatefulWidget {
  const BackgroundSettingsScreen({super.key});

  @override
  ConsumerState<BackgroundSettingsScreen> createState() =>
      _BackgroundSettingsScreenState();
}

class _BackgroundSettingsScreenState
    extends ConsumerState<BackgroundSettingsScreen> {
  bool _isEnabled = true;
  bool _isLoading = true;
  bool _isCheckingBattery = false;
  bool? _batteryOptimizationDisabled;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    _isEnabled = await backgroundAIService.isEnabled;
    await _checkBatteryOptimization();

    setState(() => _isLoading = false);
  }

  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) {
      _batteryOptimizationDisabled = true;
      return;
    }

    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      _batteryOptimizationDisabled = status.isGranted;
    } catch (e) {
      debugPrint('Error checking battery optimization: $e');
      _batteryOptimizationDisabled = null;
    }
  }

  Future<void> _requestBatteryOptimization() async {
    setState(() => _isCheckingBattery = true);

    try {
      if (Platform.isAndroid) {
        final status = await Permission.ignoreBatteryOptimizations.request();
        _batteryOptimizationDisabled = status.isGranted;

        if (!status.isGranted) {
          // Show manual instructions
          _showBatteryOptimizationDialog();
        }
      }
    } catch (e) {
      debugPrint('Error requesting battery optimization: $e');
      _showBatteryOptimizationDialog();
    }

    setState(() => _isCheckingBattery = false);
  }

  void _showBatteryOptimizationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.battery_alert, color: Colors.orange),
            SizedBox(width: 8),
            Text('Battery Optimization'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To ensure background tasks complete reliably, please disable battery optimization for NoteClaw:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            const Text('1. Open Settings → Apps → NoteClaw'),
            const SizedBox(height: 4),
            const Text('2. Tap "Battery" or "App battery usage"'),
            const SizedBox(height: 4),
            const Text('3. Select "Unrestricted" or "Don\'t optimize"'),
            const SizedBox(height: 16),
            Text(
              'This allows the app to continue AI generation even when running in the background.',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              // Open app settings
              await openAppSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBackgroundExecution(bool enabled) async {
    setState(() => _isEnabled = enabled);
    await backgroundAIService.setEnabled(enabled);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled
              ? 'Background execution enabled'
              : 'Background execution disabled'),
          backgroundColor: enabled ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  Future<void> _clearErrorLog() async {
    await backgroundAIService.clearErrorLog();
    ref.invalidate(backgroundErrorLogProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error log cleared'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final taskStatus = ref.watch(backgroundTaskStatusProvider);
    final errorLog = ref.watch(backgroundErrorLogProvider);

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.premiumGradient,
          ),
        ),
        title: const Text('Background Execution',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Main toggle card

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isEnabled
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.3)
                          : Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.1),
                      width: _isEnabled ? 2 : 1,
                    ),
                    boxShadow: [
                      if (_isEnabled)
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isEnabled
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.memory,
                              color: _isEnabled
                                  ? Colors.white
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Background Processing',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isEnabled ? 'Active' : 'Disabled',
                                  style: TextStyle(
                                    color: _isEnabled
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Transform.scale(
                            scale: 0.9,
                            child: Switch(
                              value: _isEnabled,
                              onChanged: _toggleBackgroundExecution,
                              activeThumbColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      if (_isEnabled) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'AI tasks will continue when app is minimized',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ).animate().premiumFade().premiumSlide(),

                const SizedBox(height: 16),

                // Battery optimization card (Android only)
                if (Platform.isAndroid)
                  Card(
                    color: _batteryOptimizationDisabled == true
                        ? scheme.primaryContainer.withValues(alpha: 0.3)
                        : scheme.errorContainer.withValues(alpha: 0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _batteryOptimizationDisabled == true
                                    ? Icons.battery_full
                                    : Icons.battery_alert,
                                color: _batteryOptimizationDisabled == true
                                    ? scheme.primary
                                    : scheme.error,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Battery Optimization',
                                  style: text.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (_batteryOptimizationDisabled == true)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'Optimized',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _batteryOptimizationDisabled == true
                                ? 'Battery optimization is disabled. Background tasks will run reliably.'
                                : 'Battery optimization may interrupt background tasks. Tap below to fix this.',
                            style: text.bodyMedium,
                          ),
                          if (_batteryOptimizationDisabled != true) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _isCheckingBattery
                                  ? null
                                  : _requestBatteryOptimization,
                              icon: _isCheckingBattery
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.settings),
                              label: const Text('Disable Battery Optimization'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                      .animate()
                      .premiumFade(delay: 100.ms)
                      .premiumSlide(delay: 100.ms),

                const SizedBox(height: 16),

                // Current task status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline),
                            const SizedBox(width: 12),
                            Text(
                              'Current Status',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () =>
                                  ref.invalidate(backgroundTaskStatusProvider),
                              tooltip: 'Refresh',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        taskStatus.when(
                          data: (status) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _StatusRow(
                                label: 'Service Running',
                                value:
                                    status['isRunning'] == true ? 'Yes' : 'No',
                                color: status['isRunning'] == true
                                    ? Colors.green
                                    : scheme.onSurfaceVariant,
                              ),
                              _StatusRow(
                                label: 'Status',
                                value:
                                    _formatStatus(status['status'] as String?),
                                color: _getStatusColor(
                                    status['status'] as String?),
                              ),
                              if (status['progress'] != null &&
                                  status['progress'] > 0)
                                _StatusRow(
                                  label: 'Progress',
                                  value: '${status['progress']}%',
                                  color: scheme.primary,
                                ),
                              if (status['error'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: scheme.errorContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline,
                                            color: scheme.error, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            status['error'],
                                            style: TextStyle(
                                              color: scheme.error,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('Error: $e'),
                        ),
                      ],
                    ),
                  ),
                )
                    .animate()
                    .premiumFade(delay: 200.ms)
                    .premiumSlide(delay: 200.ms),

                const SizedBox(height: 16),

                // Error log section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_outlined,
                                color: Colors.orange),
                            const SizedBox(width: 12),
                            Text(
                              'Error Log',
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _clearErrorLog,
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: const Text('Clear'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        errorLog.when(
                          data: (errors) {
                            // No errors empty state
                            if (errors.isEmpty) {
                              return Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 24, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: scheme.outline
                                            .withValues(alpha: 0.1)),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        color:
                                            Colors.green.withValues(alpha: 0.7),
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'System Healthy',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'No errors recorded in log',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return Column(
                              children: errors.reversed.take(5).map((error) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            error['taskType'] ?? 'Unknown',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const Spacer(),
                                          Text(
                                            _formatTimestamp(
                                                error['timestamp']),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        error['error'] ?? 'Unknown error',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.error,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Text('Error: $e'),
                        ),
                      ],
                    ),
                  ),
                )
                    .animate()
                    .premiumFade(delay: 300.ms)
                    .premiumSlide(delay: 300.ms),

                const SizedBox(height: 24),

                // Info section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline,
                              color: scheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'How it works',
                            style: text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '• Background execution allows AI tasks to continue when you switch apps\n'
                        '• A notification shows progress while tasks are running\n'
                        '• Results are saved and available when you return to the app\n'
                        '• Works for: Ebook generation, deep research, artifact creation',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ).animate().premiumFade(delay: 400.ms),
              ],
            ),
    );
  }

  String _formatStatus(String? status) {
    switch (status) {
      case 'idle':
        return 'Idle';
      case 'starting':
        return 'Starting...';
      case 'running':
        return 'Running';
      case 'completed':
        return 'Completed';
      case 'error':
        return 'Error';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'running':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp);
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp;
    }
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
