import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/ai_settings_service.dart';
import 'package:uuid/uuid.dart';
import 'meal.dart';
import '../../core/api/api_service.dart';

class MealPlannerState {
  final List<WeeklyMealPlan> weeklyPlans;
  final List<Meal> savedMeals;
  final bool isLoading;
  final String? error;

  const MealPlannerState({
    this.weeklyPlans = const [],
    this.savedMeals = const [],
    this.isLoading = false,
    this.error,
  });

  MealPlannerState copyWith({
    List<WeeklyMealPlan>? weeklyPlans,
    List<Meal>? savedMeals,
    bool? isLoading,
    String? error,
  }) {
    return MealPlannerState(
      weeklyPlans: weeklyPlans ?? this.weeklyPlans,
      savedMeals: savedMeals ?? this.savedMeals,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class MealPlannerNotifier extends StateNotifier<MealPlannerState> {
  final Ref ref;

  MealPlannerNotifier(this.ref) : super(const MealPlannerState()) {
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final api = ref.read(apiServiceProvider);
      final plansData = await api.getMealPlans();
      final mealsData = await api.getSavedMeals();

      final plans = plansData
          .map((json) => WeeklyMealPlan.fromJson(_convertBackendPlan(json)))
          .toList()
        ..sort((a, b) => b.weekStart.compareTo(a.weekStart));

      final meals = mealsData
          .map((json) => Meal.fromJson(_convertBackendMeal(json)))
          .toList();

      state = state.copyWith(weeklyPlans: plans, savedMeals: meals);
    } catch (e) {
      debugPrint('Error loading meal plans: $e');
    }
  }

  Map<String, dynamic> _convertBackendPlan(Map<String, dynamic> raw) {
    return {
      'id': raw['id'],
      'weekStart': raw['week_start'],
      'days':
          raw['days'] is String ? jsonDecode(raw['days']) : (raw['days'] ?? []),
      'createdAt': raw['created_at'],
      'updatedAt': raw['updated_at'],
    };
  }

  Map<String, dynamic> _convertBackendMeal(Map<String, dynamic> raw) {
    return {
      'id': raw['id'],
      'name': raw['name'],
      'description': raw['description'],
      'type': raw['meal_type'],
      'calories': raw['calories'],
      'protein': raw['protein'],
      'carbs': raw['carbs'],
      'fat': raw['fat'],
      'fiber': raw['fiber'],
      'ingredients': raw['ingredients'] is String
          ? jsonDecode(raw['ingredients'])
          : (raw['ingredients'] ?? []),
      'instructions': raw['instructions'],
      'prepTime': raw['prep_time'],
      'imageUrl': raw['image_url'],
      'createdAt': raw['created_at'],
    };
  }

  Future<void> _savePlan(WeeklyMealPlan plan) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.saveMealPlan({
        'id': plan.id,
        'weekStart': plan.weekStart.toIso8601String().split('T').first,
        'days': plan.days.map((d) => d.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('Error saving meal plan: $e');
    }
  }

  Future<void> _saveMealToBackend(Meal meal) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.saveMeal(meal.toJson());
    } catch (e) {
      debugPrint('Error saving meal: $e');
    }
  }

  /// Get or create a weekly plan for the given week
  WeeklyMealPlan getOrCreateWeekPlan(DateTime date) {
    final weekStart = _getWeekStart(date);
    final existing = state.weeklyPlans.firstWhere(
      (p) => _isSameDay(p.weekStart, weekStart),
      orElse: () => _createEmptyWeekPlan(weekStart),
    );
    return existing;
  }

  DateTime _getWeekStart(DateTime date) {
    final diff = date.weekday - DateTime.monday;
    return DateTime(date.year, date.month, date.day - diff);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  WeeklyMealPlan _createEmptyWeekPlan(DateTime weekStart) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final date = weekStart.add(Duration(days: i));
      return DayMealPlan(
        id: const Uuid().v4(),
        date: date,
      );
    });

    return WeeklyMealPlan(
      id: const Uuid().v4(),
      name: 'Week of ${_formatDate(weekStart)}',
      weekStart: weekStart,
      days: days,
      createdAt: now,
      updatedAt: now,
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  /// Add or update a meal in a day's plan
  Future<void> setMeal(DateTime date, MealType type, Meal meal) async {
    var plan = getOrCreateWeekPlan(date);

    final dayIndex = plan.days.indexWhere((d) => _isSameDay(d.date, date));
    if (dayIndex < 0) return;

    final day = plan.days[dayIndex];
    final updatedMeals = Map<MealType, Meal?>.from(day.meals);
    updatedMeals[type] = meal;

    final updatedDay = day.copyWith(meals: updatedMeals);
    final updatedDays = [...plan.days]..[dayIndex] = updatedDay;

    final updatedPlan = WeeklyMealPlan(
      id: plan.id,
      name: plan.name,
      weekStart: plan.weekStart,
      days: updatedDays,
      createdAt: plan.createdAt,
      updatedAt: DateTime.now(),
    );

    final planIndex = state.weeklyPlans.indexWhere((p) => p.id == plan.id);
    if (planIndex >= 0) {
      state = state.copyWith(
        weeklyPlans: [...state.weeklyPlans]..[planIndex] = updatedPlan,
      );
    } else {
      state = state.copyWith(
        weeklyPlans: [updatedPlan, ...state.weeklyPlans],
      );
    }
    await _savePlan(updatedPlan);
  }

  /// Remove a meal from a day's plan
  Future<void> removeMeal(DateTime date, MealType type) async {
    final weekStart = _getWeekStart(date);
    final planIndex = state.weeklyPlans.indexWhere(
      (p) => _isSameDay(p.weekStart, weekStart),
    );
    if (planIndex < 0) return;

    final plan = state.weeklyPlans[planIndex];
    final dayIndex = plan.days.indexWhere((d) => _isSameDay(d.date, date));
    if (dayIndex < 0) return;

    final day = plan.days[dayIndex];
    final updatedMeals = Map<MealType, Meal?>.from(day.meals);
    updatedMeals.remove(type);

    final updatedDay = day.copyWith(meals: updatedMeals);
    final updatedDays = [...plan.days]..[dayIndex] = updatedDay;

    final updatedPlan = WeeklyMealPlan(
      id: plan.id,
      name: plan.name,
      weekStart: plan.weekStart,
      days: updatedDays,
      createdAt: plan.createdAt,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      weeklyPlans: [...state.weeklyPlans]..[planIndex] = updatedPlan,
    );
    await _savePlan(updatedPlan);
  }

  /// Save a meal to favorites
  Future<void> saveMeal(Meal meal) async {
    if (!state.savedMeals.any((m) => m.id == meal.id)) {
      state = state.copyWith(savedMeals: [meal, ...state.savedMeals]);
      await _saveMealToBackend(meal);
    }
  }

  /// Remove a saved meal
  Future<void> removeSavedMeal(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteSavedMeal(id);
      state = state.copyWith(
        savedMeals: state.savedMeals.where((m) => m.id != id).toList(),
      );
    } catch (e) {
      debugPrint('Error deleting saved meal: $e');
    }
  }

  /// Generate a meal plan using AI
  Future<void> generateWeeklyPlan({
    String? dietaryPreferences,
    int targetCalories = 2000,
    DateTime? weekStart,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final start = weekStart ?? _getWeekStart(DateTime.now());
      final prompt = '''
Generate a 7-day meal plan with breakfast, lunch, dinner, and snack for each day.
${dietaryPreferences != null ? 'Dietary preferences: $dietaryPreferences' : ''}
Target daily calories: $targetCalories

Return ONLY a JSON array with this format:
[
  {
    "day": 0,
    "meals": [
      {"type": "breakfast", "name": "Oatmeal with Berries", "description": "Healthy start", "calories": 350, "ingredients": ["oats", "berries", "honey"]},
      {"type": "lunch", "name": "Grilled Chicken Salad", "description": "Protein-rich lunch", "calories": 450, "ingredients": ["chicken", "lettuce", "tomatoes"]},
      {"type": "dinner", "name": "Salmon with Vegetables", "description": "Omega-3 rich dinner", "calories": 550, "ingredients": ["salmon", "broccoli", "rice"]},
      {"type": "snack", "name": "Greek Yogurt", "description": "Protein snack", "calories": 150, "ingredients": ["yogurt", "nuts"]}
    ]
  }
]
''';

      final response = await _callAI(prompt);
      final plan = _parseMealPlanFromResponse(response, start);

      final planIndex = state.weeklyPlans.indexWhere(
        (p) => _isSameDay(p.weekStart, start),
      );

      if (planIndex >= 0) {
        state = state.copyWith(
          weeklyPlans: [...state.weeklyPlans]..[planIndex] = plan,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          weeklyPlans: [plan, ...state.weeklyPlans],
          isLoading: false,
        );
      }
      await _savePlan(plan);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<String> _callAI(String prompt) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final model = settings.getEffectiveModel();

    // Use Backend Proxy (Admin's API keys)
    final apiService = ref.read(apiServiceProvider);
    final messages = [
      {'role': 'user', 'content': prompt}
    ];

    return await apiService.chatWithAI(
      messages: messages,
      provider: settings.provider,
      model: model,
      billingFeature: 'meal_plan',
    );
  }

  WeeklyMealPlan _parseMealPlanFromResponse(
      String response, DateTime weekStart) {
    try {
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
      if (jsonMatch == null) throw Exception('No JSON found');

      final List<dynamic> jsonList = jsonDecode(jsonMatch.group(0)!);
      final now = DateTime.now();

      final days = <DayMealPlan>[];
      for (int i = 0; i < 7; i++) {
        final date = weekStart.add(Duration(days: i));
        final dayData = jsonList.firstWhere(
          (d) => d['day'] == i,
          orElse: () => {'meals': []},
        );

        final meals = <MealType, Meal?>{};
        for (final mealData in (dayData['meals'] as List? ?? [])) {
          final type = MealType.values.firstWhere(
            (t) => t.name == mealData['type'],
            orElse: () => MealType.lunch,
          );
          meals[type] = Meal(
            id: const Uuid().v4(),
            name: mealData['name'] ?? '',
            description: mealData['description'] ?? '',
            type: type,
            calories: mealData['calories'] ?? 0,
            ingredients: List<String>.from(mealData['ingredients'] ?? []),
            createdAt: now,
          );
        }

        days.add(DayMealPlan(
          id: const Uuid().v4(),
          date: date,
          meals: meals,
        ));
      }

      return WeeklyMealPlan(
        id: const Uuid().v4(),
        name: 'Week of ${_formatDate(weekStart)}',
        weekStart: weekStart,
        days: days,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      debugPrint('Error parsing meal plan: $e');
      return _createEmptyWeekPlan(weekStart);
    }
  }
}

final mealPlannerProvider =
    StateNotifierProvider<MealPlannerNotifier, MealPlannerState>((ref) {
  return MealPlannerNotifier(ref);
});
