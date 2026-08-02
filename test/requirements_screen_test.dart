import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteclaw/features/planning/models/plan.dart';
import 'package:noteclaw/features/planning/planning_provider.dart';
import 'package:noteclaw/features/planning/ui/plan_detail_screen.dart';
import 'package:noteclaw/theme/app_theme.dart';

class _FakePlanningNotifier extends PlanningNotifier {
  _FakePlanningNotifier(super.ref, Plan plan) {
    state = PlanningState(currentPlan: plan);
  }

  @override
  Future<void> loadPlan(String planId, {bool includeRelations = true}) async {}
}

void main() {
  testWidgets(
      'requirements screen has no gradient cover and opens bottom sheet',
      (tester) async {
    final now = DateTime(2026, 8, 2);
    final plan = Plan(
      id: 'plan-1',
      userId: 'user-1',
      title: 'Life',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planningProvider.overrideWith(
            (ref) => _FakePlanningNotifier(ref, plan),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const PlanDetailScreen(planId: 'plan-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FlexibleSpaceBar), findsNothing);
    expect(find.text('Life'), findsOneWidget);

    await tester.tap(find.text('Requirements (0)'));
    await tester.pumpAndSettle();

    expect(find.text('No Requirements Yet'), findsOneWidget);
    expect(find.text('Add Requirement'), findsOneWidget);

    await tester.tap(find.text('Add Requirement'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.text('Requirement Title'), findsOneWidget);
    expect(find.text('Description (optional)'), findsOneWidget);
    expect(find.text('EARS Pattern'), findsOneWidget);
    expect(find.text('Acceptance Criteria'), findsOneWidget);
  });
}
