import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zendiary/core/theme/zen_theme.dart';
import 'package:zendiary/models/unified_item.dart';
import 'package:zendiary/services/today_focus_service.dart';
import 'package:zendiary/views/workspace/today_focus_card.dart';

void main() {
  testWidgets('fits a 390px phone and opens the supplied detail entry', (
    tester,
  ) async {
    TodayFocusItem? tapped;
    final current = TodayFocusItem(
      item: const UnifiedItem(
        id: 'current',
        source: UnifiedItemSource.event,
        title: '当前课程',
        location: 'BOC R4057',
      ),
      startAt: DateTime(2026, 9, 5, 9),
      endAt: DateTime(2026, 9, 5, 10, 30),
    );
    final next = TodayFocusItem(
      item: const UnifiedItem(
        id: 'next',
        source: UnifiedItemSource.todo,
        title: '下一项作业',
      ),
      startAt: DateTime(2026, 9, 5, 11),
      endAt: DateTime(2026, 9, 5, 11, 30),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ZenTheme.lightTheme,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TodayFocusCard(
                focus: TodayFocus(current: [current], next: [next]),
                onItemTap: (value) => tapped = value,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('当前安排'), findsOneWidget);
    expect(find.text('当前课程'), findsOneWidget);
    expect(find.textContaining('地点：BOC R4057'), findsOneWidget);
    expect(find.text('接下来'), findsOneWidget);
    await tester.tap(find.text('下一项作业'));
    expect(tapped?.item.id, 'next');
  });
}
