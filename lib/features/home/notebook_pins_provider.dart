import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local (on-device) notebook pin state.
///
/// Until the user customizes pins, the dashboard treats the first three
/// notebooks as pinned (preserving the original behaviour). The first
/// pin/unpin action materializes the set and marks it customized.
class NotebookPinsState {
  const NotebookPinsState({
    this.pins = const <String>{},
    this.customized = false,
  });

  final Set<String> pins;
  final bool customized;
}

class NotebookPinsNotifier extends StateNotifier<NotebookPinsState> {
  NotebookPinsNotifier() : super(const NotebookPinsState()) {
    _load();
  }

  static const _pinsKey = 'notebook_pins_v1';
  static const _customizedKey = 'notebook_pins_customized_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final pins = (prefs.getStringList(_pinsKey) ?? const <String>[]).toSet();
    final customized = prefs.getBool(_customizedKey) ?? false;
    state = NotebookPinsState(pins: pins, customized: customized);
  }

  /// The pinned id set, falling back to [defaultIds] before customization.
  Set<String> effectivePins(List<String> defaultIds) {
    return state.customized ? state.pins : defaultIds.toSet();
  }

  bool isPinned(String id, List<String> defaultIds) =>
      effectivePins(defaultIds).contains(id);

  Future<void> toggle(String id, List<String> defaultIds) async {
    final next = Set<String>.from(effectivePins(defaultIds));
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = NotebookPinsState(pins: next, customized: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinsKey, next.toList());
    await prefs.setBool(_customizedKey, true);
  }
}

final notebookPinsProvider =
    StateNotifierProvider<NotebookPinsNotifier, NotebookPinsState>(
  (ref) => NotebookPinsNotifier(),
);
