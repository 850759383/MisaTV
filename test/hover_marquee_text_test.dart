import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/ui/widgets/hover_marquee_text.dart';

void main() {
  testWidgets('长标题悬停后循环滚动，移出后恢复省略号', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 110,
              child: HoverMarqueeText(
                '这是一个特别长的体育比赛直播标题',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('这是一个特别长的体育比赛直播标题'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(HoverMarqueeText)),
    );
    await tester.pump();

    // 悬停后渲染首尾两份文本，配合横向位移动画形成无缝循环。
    expect(find.text('这是一个特别长的体育比赛直播标题'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 2));

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await gesture.removePointer();

    expect(find.text('这是一个特别长的体育比赛直播标题'), findsOneWidget);
  });

  testWidgets('外层卡片悬停也能触发标题滚动', (tester) async {
    var hover = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) {
                return MouseRegion(
                  onEnter: (_) => setState(() => hover = true),
                  onExit: (_) => setState(() => hover = false),
                  child: SizedBox(
                    width: 110,
                    child: HoverMarqueeText(
                      '另一个特别长的体育比赛直播标题',
                      externalHover: hover,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('另一个特别长的体育比赛直播标题'), findsOneWidget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(HoverMarqueeText)),
    );
    await tester.pump();

    expect(find.text('另一个特别长的体育比赛直播标题'), findsNWidgets(2));

    await gesture.moveTo(const Offset(400, 400));
    await tester.pump();
    await gesture.removePointer();

    expect(find.text('另一个特别长的体育比赛直播标题'), findsOneWidget);
  });

  testWidgets('短标题悬停不启动滚动', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: HoverMarqueeText('短标题', style: TextStyle(fontSize: 16)),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(HoverMarqueeText)),
    );
    await tester.pump();

    expect(find.text('短标题'), findsOneWidget);
    await gesture.removePointer();
  });
}
