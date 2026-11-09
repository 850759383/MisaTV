import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kniephos/ui/widgets/secondary_long_press.dart';

void main() {
  testWidgets('右键按住 600ms 触发长按，短按右键只触发 tap', (tester) async {
    var longPressed = 0;
    var tapped = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SecondaryLongPressDetector(
            onLongPress: () => longPressed++,
            onTap: () => tapped++,
            child: const SizedBox(key: Key('target'), width: 120, height: 120),
          ),
        ),
      ),
    );

    final target = find.byKey(const Key('target'));

    // 按住超过阈值：只触发长按，松手后不再视为短按。
    final hold = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(longPressed, 1);
    await hold.up();
    await tester.pump();
    expect(tapped, 0);

    // 快速右键：只触发短按。
    final quick = await tester.startGesture(
      tester.getCenter(target),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await quick.up();
    await tester.pump();
    expect(tapped, 1);
    expect(longPressed, 1);
  });
}
