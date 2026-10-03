import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/room.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_engine/tactical_engine.dart' show SystemPack;

void main() {
  final scene = Scene(
      settings: const SceneSettings(width: 100, height: 100, grid: Grid(cellSize: 10)));
  final mine = SystemPack.fromJson({'id': 'mine', 'name': 'Mine', 'unit': 'zone'});

  test("a scene opens on its campaign's system", () {
    expect(sceneOnSystem(scene, 'dnd5e', const []).settings.pack, 'dnd5e');
    // An installed system: the scene carries its file, for the players.
    final played = sceneOnSystem(scene, 'mine', [mine]);
    expect(played.settings.pack, 'mine');
    expect(played.toJson().toString(), contains('Mine'));
    // Already on it: the same scene.
    expect(identical(sceneOnSystem(played, 'mine', [mine]), played), isTrue);
    // A new version of the module reaches it.
    final v2 = SystemPack.fromJson({...mine.toJson(), 'version': 2, 'name': 'Mine 2'});
    expect(sceneOnSystem(played, 'mine', [v2]).packFile!.data['name'], 'Mine 2');
  });

  test('a system this GM no longer has leaves the scene as it is', () {
    final played = sceneOnSystem(scene, 'mine', [mine]);
    expect(identical(sceneOnSystem(played, 'gone', const []), played), isTrue);
    expect(identical(sceneOnSystem(scene, 'gone', const []), scene), isTrue);
  });
}
