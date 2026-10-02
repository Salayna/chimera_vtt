import 'dart:convert';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final scene = Scene(
    settings: const SceneSettings(
        map: AssetId('abc'), width: 2048, height: 1024, grid: Grid(cellSize: 64)),
    tokens: {
      const TokenId('t'): const Token(
          id: TokenId('t'), position: (x: 96, y: 32), size: 64, hidden: true),
    },
  );

  test('an exported scene imports back unchanged', () {
    final file = sceneToFile(scene);
    expect(utf8.decode(file), contains('\n  "format": 1')); // Readable.
    expect(sceneFromFile(file).toJson(), equals(scene.toJson()));
  });

  test('anything else is a FormatException with a readable message', () {
    for (final bad in ['not json', '[]', '{"format": 1}', '{"format": 99}']) {
      expect(() => sceneFromFile(utf8.encode(bad)),
          throwsA(isA<FormatException>()), reason: bad);
    }
  });
}
