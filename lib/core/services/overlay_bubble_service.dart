import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'progress_notification_service.dart';

/// Legacy name kept to avoid changing orchestrators.
/// Now exclusively uses persistent system notifications instead of a dangerous overlay.
class OverlayBubbleService {
  static final OverlayBubbleService _instance = OverlayBubbleService._internal();
  factory OverlayBubbleService() => _instance;
  OverlayBubbleService._internal();

  bool _isShowing = false;
  String _status = 'Generating...';
  int _progress = 0;

  Future<bool> checkPermission() async => true;
  Future<bool> requestPermission() async => true;

  Future<void> show({String status = 'AI Generating...'}) async {
    if (_isShowing) return;
    _status = status;
    _isShowing = true;
    
    await progressNotificationService.showIndeterminate(
      title: 'Ebook Generation',
      status: status,
    );
  }

  Future<void> updateStatus(String status, {int? progress}) async {
    _status = status;
    if (progress != null) _progress = progress;

    if (_isShowing) {
      if (progress != null && progress > 0) {
        await progressNotificationService.showProgress(
          title: 'Ebook Generation',
          status: status,
          progress: progress,
          maxProgress: 100,
        );
      } else {
        await progressNotificationService.showIndeterminate(
          title: 'Ebook Generation',
          status: status,
        );
      }
    }
  }

  Future<void> hide() async {
    if (!_isShowing) return;
    _isShowing = false;
    await progressNotificationService.hide();
  }

  bool get isShowing => _isShowing;
  String get status => _status;
  int get progress => _progress;
}

final overlayBubbleService = OverlayBubbleService();
final overlayBubbleServiceProvider = Provider((ref) => overlayBubbleService);
