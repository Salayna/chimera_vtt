import 'dart:async';

import 'actor.dart';
import 'commands.dart';
import 'patch.dart';
import 'reducer.dart';
import 'scene.dart';

/// Holds the current scene and notifies listeners when it changes.
final class SceneStore {
  SceneStore(this._scene);

  Scene _scene;
  final _changes = StreamController<Scene>.broadcast();

  Scene get scene => _scene;
  Stream<Scene> get changes => _changes.stream;

  /// GM session: reduce [command] and apply it if accepted.
  Outcome execute(Actor actor, Command command) {
    final outcome = reduce(_scene, actor, command);
    if (outcome case Accepted(:final patches)) apply(patches);
    return outcome;
  }

  /// Applies patches from [execute] or, in a player session, the network.
  void apply(List<Patch> patches) {
    if (patches.isEmpty) return;
    _scene = _scene.applyPatches(patches);
    _changes.add(_scene);
  }

  /// Replaces the whole scene, for a snapshot or a loaded save.
  void replace(Scene scene) {
    _scene = scene;
    _changes.add(scene);
  }

  Future<void> dispose() => _changes.close();
}
