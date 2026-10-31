import 'package:budget/flows.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A short flow's screen: a title and a button that returns a value.
class _Flow extends StatelessWidget {
  const _Flow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Flow screen'),
        TextButton(
          onPressed: () => Navigator.of(context).pop('done'),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

/// A screen with one button that opens [_Flow] and keeps what it returns.
class _Caller extends StatelessWidget {
  const _Caller({required this.presentation, required this.result});

  final FlowPresentation presentation;
  final ValueNotifier<String?> result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async {
          result.value = await openFlow<String>(
            context,
            presentation: presentation,
            builder: (_) => const _Flow(),
          );
        },
        child: const Text('Open flow'),
      ),
    ),
  );
}

/// The sheet a desktop window opens, so a test can tell it from a route.
final _sheet = find.byKey(const ValueKey('flow-sheet'));

Future<ValueNotifier<String?>> _pump(
  WidgetTester tester,
  FlowPresentation presentation, {
  Size size = const Size(800, 600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final result = ValueNotifier<String?>(null);
  addTearDown(result.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: _Caller(presentation: presentation, result: result),
    ),
  );
  return result;
}

void main() {
  testWidgets('a flow opens as a full-screen route by default', (tester) async {
    final result = await _pump(tester, FlowPresentation.route);

    await tester.tap(find.text('Open flow'));
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(_sheet, findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsNothing);
    expect(result.value, 'done');
  });

  testWidgets('a flow that is a sheet on a phone opens as a sheet', (
    tester,
  ) async {
    final result = await _pump(tester, FlowPresentation.sheet);

    await tester.tap(find.text('Open flow'));
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(_sheet, findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsNothing);
    expect(result.value, 'done');
  });

  testWidgets('a desktop window opens a flow as a sheet over the screen', (
    tester,
  ) async {
    final result = await _pump(
      tester,
      FlowPresentation.route,
      size: const Size(1280, 820),
    );

    await tester.tap(find.text('Open flow'));
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsOneWidget);
    expect(_sheet, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // The screen under the sheet is still there.
    expect(find.text('Open flow'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsNothing);
    expect(_sheet, findsNothing);
    expect(result.value, 'done');
  });

  testWidgets('Esc closes a desktop sheet and nothing is returned', (
    tester,
  ) async {
    final result = await _pump(
      tester,
      FlowPresentation.route,
      size: const Size(1280, 820),
    );

    await tester.tap(find.text('Open flow'));
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsNothing);
    expect(_sheet, findsNothing);
    expect(result.value, isNull);
  });

  testWidgets('a flow that is a sheet on a phone is a desktop sheet too', (
    tester,
  ) async {
    await _pump(tester, FlowPresentation.sheet, size: const Size(1280, 820));

    await tester.tap(find.text('Open flow'));
    await tester.pumpAndSettle();

    expect(find.text('Flow screen'), findsOneWidget);
    expect(_sheet, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
