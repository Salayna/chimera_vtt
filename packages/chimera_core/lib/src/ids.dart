import 'dart:math';

/// Identity of a [Token]. Erased to [String] at runtime.
extension type const TokenId(String value) {}

/// Identity of a [FogOp].
extension type const FogOpId(String value) {}

/// Identity of a player, from Supabase Auth.
extension type const PlayerId(String value) {}

/// SHA-256 hex of an asset's bytes (ADR 006).
extension type const AssetId(String value) {}

/// Which type of entity. Sent on the wire so a bare id can be resolved.
enum EntityKind { settings, token, fogOp }

final _random = Random.secure();

/// A random 128-bit id as 32 hex characters. Minted by the GM session.
String newId() => [
      for (var i = 0; i < 16; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
