import 'ids.dart';

/// Who issues a command. Permissions follow the role, not the id.
sealed class Actor {
  const Actor();
}

final class Gm extends Actor {
  const Gm();
}

final class Player extends Actor {
  const Player(this.id);

  final PlayerId id;
}
