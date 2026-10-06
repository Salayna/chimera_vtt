import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/table/log_panel.dart';
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
}
