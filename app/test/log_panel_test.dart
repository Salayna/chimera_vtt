import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:chimera_vtt/table/log_panel.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a typed line rolls with /r or /roll, and says anything else', () {
    Json? json(String line) => commandFor(line)?.toJson();
    expect(json('/r 2d6+3'), const RollDice('2d6+3').toJson());
    expect(json('/roll d20'), const RollDice('d20').toJson());
    expect(json('/r'), const RollDice('').toJson()); // Refused, with a hint.
    expect(json('  hello there '), const Say('hello there').toJson());
    expect(json('/rolling'), const Say('/rolling').toJson());
    expect(json('   '), isNull);
    expect(commandFor('/r d20', secret: true)!.toJson(),
        const RollDice('d20', secret: true).toJson());
    expect(commandFor('hi', secret: true)!.toJson(),
        const Say('hi', secret: true).toJson());
  });

  testWidgets('the dice roll how many, which, and the modifier', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ClientSession(LoopbackHub().connect(), const PlayerId('alice'));
    final sent = _Sent();
    await tester.pumpWidget(cvApp(
        title: 'test',
        home: Align(
            alignment: Alignment.topLeft,
            child: LogPanel(session: session, send: sent.call))));
    await tester.tap(find.bySemanticsLabel('Roll dice'));
    await tester.pumpAndSettle(); // It pops in.
    await tester.tap(find.bySemanticsLabel('More: dice'));
    await tester.tap(find.bySemanticsLabel('Less: modifier'));
    await tester.pump();
    await tester.tap(find.text('d6'));
    await tester.pump();
    expect([for (final c in sent.commands) c.toJson()], [const RollDice('2d6-1').toJson()]);
    expect(find.text('d6'), findsNothing); // It closes.
  });
}

class _Sent {
  final commands = <Command>[];
  Outcome call(Command c) {
    commands.add(c);
    return const Accepted([]);
  }
}
