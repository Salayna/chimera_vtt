# Chimera VTT — Lexicon

As of 2026-09-29 · Companion to [PLAN.md](PLAN.md)

One word, one meaning. When code, docs and conversation disagree, this file wins. Change it first, then rename in the code. The **Code** column gives the Dart name where one exists or is planned.

## Contents

1. [At the table](#at-the-table)
2. [Domain core](#domain-core)
3. [Sync](#sync)
4. [Rules](#rules)
5. [Project](#project)
6. [Words to avoid](#words-to-avoid)

---

## At the table

| Term | Code | Meaning |
| --- | --- | --- |
| **GM** | `Gm` | The game master. Runs the authoritative session and sees everything. |
| **Player** | `Player` | Anyone at the table who isn't the GM. Sees a filtered copy of the scene. |
| **Campaign** | `Campaign` | Everything one group plays with: scenes, packs, assets and members. Owned by one signed-in GM. |
| **Member** | — | A player who has entered a campaign's room at least once, with the name and colour they chose. Signed in or anonymous. The GM can remove one. A token's owner is a member. |
| **Scene** | `Scene` | One map and everything on it. A set of entities keyed by id. |
| **Map** | — | The background image of a scene. It's an asset, referenced from the scene settings. |
| **Token** | `Token` | An entity standing for a creature or object on the map. It has a position, a size, an optional owner and a hidden flag. |
| **Owner** | `Token.owner` | The player allowed to move a token. A token has no owner or exactly one. |
| **Hidden** | `Token.hidden` | GM-only. A hidden token is never sent to players. Not the same as *under fog*. |
| **Fog** | — | The mask that darkens parts of the map for players. It's the result of every fog op, applied in order. |
| **Under fog** | — | Inside a fogged area. The entity is still sent to players and only hidden when drawn ("trust the table"). |
| **Grid** | `Grid` | Cell size and offset used to snap and measure. A field of the scene settings, not an entity. |
| **Cell** | — | One square of the grid. |
| **Snap** | `Grid.snap` | Moving a dropped token onto the grid: its edges onto grid lines, or the middle of a cell for tokens smaller than one. On by default; the GM can turn it off, and holding Alt places one token freely. |
| **Room** | — | A live session that players can join. Today it holds one scene; with campaigns, it's a campaign's session, showing whichever scene the GM has live. |
| **Room code** | `newRoomCode` | The short, human-typable code players enter to join a room: 6 characters, without look-alikes (0/O, 1/I/L). The Realtime channel is `room:<code>`. It's not an id. |
| **Join link** | `?room=CODE` | The app's URL with a room code, which opens that room as a player. |
| **Cinematic scene** | — | A phase 5 presentation mode: art, parallax, particles, music. Not a tactical map. |

## Domain core

| Term | Code | Meaning |
| --- | --- | --- |
| **Entity** | `Entity` (sealed) | A piece of scene state with its own identity that changes independently. It's the unit of sync, visibility, permission and persistence. It has an id, a kind and a schema version. See [Entity or field?](#entity-or-field). |
| **Kind** | `EntityKind` | Which type of entity: `token`, `fogOp`, `settings`… Sent on the wire so a bare id can be resolved. |
| **Field** | — | A value inside an entity with no identity of its own, for example a token's position or the grid. |
| **Id** | `TokenId`, `FogOpId`… | An entity's identity. It never changes and is never reused. Typed per kind with extension types. |
| **Scene settings** | `SceneSettings` | The single-instance entity holding the map asset, map size, grid, whether grid lines show, and default fog. It has no id: its kind identifies it, and it can't be deleted. |
| **Fog op** | `FogOp` | One fog operation (`FogMode.cover` or `reveal`) with a shape and an `order`. |
| **Fog shape** | `FogShape` (sealed) | `FogRect` (two opposite corners) or `FogBrush` (a polyline of points swept by a radius). |
| **Order** | `FogOp.order` | A fog op's drawing position. Assigned by the reducer as the current maximum + 1, never by the client. |
| **Point** | `Point` | A position in world coordinates (map pixels), as a Dart record `({double x, double y})`. JSON: `[x, y]`. |
| **Token size** | `Token.size` | Width and height in world units, like positions, so it works on gridless maps. |
| **Actor** | `Actor` (sealed) | Who issues a command: `Gm` or `Player(PlayerId)`. These are the same `Gm` and `Player` as under [At the table](#at-the-table). Permissions follow the actor's role, not their id. |
| **Command** | `Command` (sealed) | A request to change the scene: `UpdateSettings`, `PlaceToken`, `MoveToken`, `AssignOwner`, `SetTokenHidden`, `RemoveToken`, `AddFogOp`. Principle 2: nothing changes state except a command. Players may only send `MoveToken`. |
| **New id** | `newId` | A random 128-bit hex id, minted by the GM session before the command, so the reducer stays pure. |
| **Reducer** | `reduce` | The pure function `(scene, actor, command) → accepted patches or refusal`. It changes no state itself. |
| **Outcome** | `Outcome` (sealed) | What the reducer returns: `Accepted(patches)` or `Refused(refusal)`. |
| **Refusal** | `Refusal` | Why the reducer rejected a command: `notFound`, `notOwner`, `gmOnly`, `invalid`, `duplicateId`. |
| **Patch** | `Patch` (sealed) | One change to one entity: an **upsert** (create or replace the whole entity) or a **delete** (by kind and id). |
| **Apply** | `applyPatches` | The only way a scene changes. It's the same function for the GM and for players. |
| **Visibility filter** | `visibleTo`, `patchesFor` | Removes what a viewer may not see from a scene or a patch list. |
| **Store** | `SceneStore` | Holds the current scene and notifies listeners when patches are applied. |
| **Scene file** | `sceneToFile`, `sceneFromFile` | A scene exported as indented JSON (the save format). The map stays in Storage; the file holds its hash. Importing replaces the scene for everyone, after a confirmation. |
| **Schema version** | `v` | The version number stored with each entity's JSON, used to migrate old saves. |
| **Save format** | `Scene.format` | The version at the top of a scene's JSON, checked before any entity is parsed. |

### Entity or field?

Make something an entity when at least one of these holds:

- It is created or deleted on its own.
- It changes often, independently, and bundling it would resend too much.
- It needs its own visibility or owner.

Otherwise it's a field of some entity.

## Sync

| Term | Code | Meaning |
| --- | --- | --- |
| **Authority** | — | The session whose state is the truth. Always the GM session (ADR 002). |
| **Session** | `Session` (sealed) | One client's live connection to a room. `HostSession` (the GM) is the authority; `ClientSession` (a player) applies what it receives. |
| **Transport** | `Transport` | The interface that moves messages. Implemented by Supabase Realtime and by loopback. |
| **Loopback** | `LoopbackHub` | An in-memory transport for tests and solo play. |
| **Message** | `Message` (sealed) | Anything on the wire: `RequestSnapshot`, `Snapshot`, `PatchBatch`, `Heartbeat`, `Intent`, `RefusalMessage`. Each carries the protocol version `p`. |
| **Protocol version** | `protocolVersion` | Bumped on any incompatible message change. A client on another version can't join (`ProtocolMismatch`). |
| **Snapshot** | `Snapshot` | The whole player-filtered scene, sent on join or resync. |
| **Patch batch** | `PatchBatch` | The patches produced by one accepted command, sent under one sequence number. |
| **Sequence number** | `seq` | A counter on patch batches, owned by `chimera_sync`. A gap means a missed batch, and the player resyncs. Only compared within one epoch. |
| **Epoch** | `HostSession.epoch` | A random id for one run of the GM's session. A GM who reloads starts a new epoch with `seq` back at 0, and players resync when they see it change. |
| **Autosave** | — | The GM's scene saved locally (browser storage on web) a second after each change, so a GM reload resumes the room. |
| **Intent** | `Intent` | The message a player sends, carrying a command and a request id. The GM's own commands don't travel as intents. |
| **Request id** | `requestId` | Names one intent, so the batch or refusal answering it can be matched to the optimistic copy. |
| **Heartbeat** | `Heartbeat` | The GM's latest `seq`, sent every few seconds. Reveals a missed last batch, and expires intents that got no answer. |
| **Resync** | `RequestSnapshot` | A player asking for a fresh snapshot after a gap or a reconnect. |
| **Presence** | `Presence` | Who is connected, their role and their cursor, as `({String player, bool gm, Point? cursor})`. Comes from Realtime presence. |
| **Optimistic move** | `ClientSession.request` | A player's own command, shown at once and snapped back if refused, or if no answer comes within two heartbeats. |
| **Asset** | `AssetId` | An uploaded file, usually an image. Its id is the SHA-256 of its bytes (ADR 006). |

## Rules

| Term | Code | Meaning |
| --- | --- | --- |
| **Tactical engine** | `tactical_engine` | The pure-Dart rules package: topology, regions, measurement, sight and tag effects. It knows no game system. |
| **System pack** | `SystemPack` | A data file defining a game system: conditions, tags, range bands, trackers, sheet fields. |
| **Topology** | `Topology` (sealed) | How space is divided: `SquareGrid` or `Gridless` today; hex grids and freeform zones later. The pack picks the kind, the scene supplies the scale. |
| **Step** | `Topology.steps` | The topology's unit of distance: one cell, or one cell size on a gridless map. A pack converts steps to its own unit with `unitsPerStep`. |
| **Diagonal rule** | `DiagonalRule` | How a square grid counts diagonals: `chebyshev` (all 1), `manhattan` (all 2), `alternating` (1, 2, 1…). |
| **Region** | `Region` | An area that carries tags: a sector, zone, or spell area. |
| **Sector** | — | A region holding sector tags. In Solaris Arcanum, one 20 ft grid cell. |
| **Zone** | — | A freeform region used by zone-based systems. |
| **Tag** | `Tag` | A named property on a region or entity, with an optional value, as the record `({String name, int? value})`, for example Heavy Cover or Darkness (2). Defined in a pack by a `TagDef`. |
| **Sector tag** | — | A tag whose definition has the `sector` flag, so it applies to a sector. |
| **Condition** | — | A tag on a token, optionally with a value, for example Darkness (2). |
| **Tag effect** | `Effect` (sealed) | What a tag does, built from data building blocks (ADR 012): `RollModifier`, `MoveCost`, `BlocksSight`, `OccupantLimit`, `EntryCheck`. Anything the blocks can't express stays as rules text. |
| **Shape** | `Shape` (sealed) | A region's area: `Polygon` or `Circle`. |
| **Sight** | `canSee` | Line of sight. A region with `BlocksSight` stops sight through it, not into or out of it, and grazing its edge doesn't count. |
| **Range band** | `RangeBand` | A named distance bracket defined by a pack, for example Point Blank or Far. |
| **Precise movement** | — | Solaris' option to use exact positions inside sectors. |

## Project

| Term | Code | Meaning |
| --- | --- | --- |
| **Workspace** | root `pubspec.yaml` | The monorepo's pub workspace. One lockfile, shared resolution. |
| **Workspace member** | `resolution: workspace` | A package that belongs to the workspace: `app`, `chimera_core`, `chimera_sync` and `tactical_engine`. |
| **Core** | `chimera_core` | The pure-Dart domain package. |
| **Sync package** | `chimera_sync` | Transport, protocol and sessions. |
| **ADR** | — | An architecture decision record: one numbered decision in the plan's decision log. |
| **POC** | — | The phase 0 proof of concept. |

## Words to avoid

| Don't say | Say | Why |
| --- | --- | --- |
| record (for scene state) | **entity** | "Record" is a Dart language feature (`(1, 2)`, `({x, y})`). Use "record" only for that. |
| object, item, element | **entity** | Too vague. |
| event (for a player's request) | **intent** or **command** | "Event" suggests something that already happened. A request can be refused. |
| update (for a change on the wire) | **patch** | "Update" is used for too many things. |
| user | **GM** or **player** | Roles matter more than accounts. "User" is fine when talking about Supabase Auth. |
| server | **authority** or **GM session** | There is no server of our own. Supabase only relays. |
