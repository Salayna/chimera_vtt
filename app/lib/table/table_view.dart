import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'fog_mask.dart';
import 'layers.dart';

enum Tool { move, fogBrush, fogRect }

/// The view's fast-changing state, outside the widget tree so it can change
/// every frame without rebuilds. Owned by whoever creates it.
class TableController {
  final view = ValueNotifier<Matrix4>(Matrix4.identity());
  final drag = ValueNotifier<TokenDrag?>(null);
  final fogPreview = ValueNotifier<FogPreview?>(null);
  final selected = ValueNotifier<TokenId?>(null);
  Tool tool = Tool.move;

  /// Dropped tokens snap to the grid. Holding Alt places one freely.
  bool snap = true;
  FogMode fogMode = FogMode.cover;
  double brushRadius = 48;
  Size _viewport = Size.zero;

  /// The scene point at the middle of the view, to place new things.
  Point get viewCenter {
    final c = MatrixUtils.transformPoint(
        Matrix4.inverted(view.value), _viewport.center(Offset.zero));
    return (x: c.dx, y: c.dy);
  }

  void dispose() {
    view.dispose();
    drag.dispose();
    fogPreview.dispose();
    selected.dispose();
  }
}

/// A scene as four layers, cheapest first, each repainting only when its
/// own input changes: map (never), grid (grid edits), tokens (drags and
/// token patches), fog (new fog ops and the stroke in progress).
class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.store,
    required this.controller,
    required this.gm,
    required this.self,
    required this.send,
    this.map,
    this.loadAsset,
    this.images = _noImages,
  });

  final SceneStore store;
  final TableController controller;
  final bool gm;
  final PlayerId self;
  final Outcome Function(Command) send;
  /// Shown while the scene has no map of its own.
  final ui.Image? map;

  /// Loads the scene's map ([SceneSettings.map]) when it has one.
  final Future<ui.Image> Function(AssetId)? loadAsset;
  final ui.Image? Function(AssetId) images;

  static ui.Image? _noImages(AssetId _) => null;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  /// Drags send at most this often; the drop is always sent.
  static const dragInterval = Duration(milliseconds: 66);

  late Scene _scene;
  StreamSubscription<Scene>? _subscription;
  final _mask = FogMask();
  Map<FogOpId, FogOp>? _maskedOps;
  int _fogRevision = 0;
  Timer? _bakeTimer;
  AssetId? _mapId;
  ui.Image? _mapImage;

  /// Pending fog ops bake after this long without a new one.
  static const bakeAfter = Duration(seconds: 1);
  Size? _fittedTo;

  // Gesture state.
  Offset? _grab;
  final _sinceSend = Stopwatch();
  bool _panning = false;
  Offset? _downAt;
  bool _moved = false;
  Offset? _fogStart;
  List<Point> _strokePoints = [];
  double _lastPanZoomScale = 1;

  TableController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(TableView old) {
    super.didUpdateWidget(old);
    if (old.store != widget.store) _listen();
  }

  void _listen() {
    _subscription?.cancel();
    _setScene(widget.store.scene);
    _subscription =
        widget.store.changes.listen((s) => setState(() => _setScene(s)));
  }

  void _setScene(Scene scene) {
    _scene = scene;
    final mapId = scene.settings.map;
    if (mapId != _mapId) {
      _mapId = mapId;
      _mapImage = null;
      if (mapId != null) {
        widget.loadAsset?.call(mapId).then((image) {
          if (mounted && _mapId == mapId) setState(() => _mapImage = image);
        }, onError: (Object e) {
          // ponytail: no retry UI; a reload retries.
          debugPrint('Map $mapId failed to load: $e');
        });
      }
    }
    if (!identical(scene.fogOps, _maskedOps)) {
      _maskedOps = scene.fogOps;
      if (_mask.sync(scene.settings, scene.fogInOrder)) _fogRevision++;
      _bakeTimer?.cancel();
      if (_mask.pending.isNotEmpty) {
        _bakeTimer = Timer(bakeAfter, () {
          _mask.bake();
          if (mounted) setState(() => _fogRevision++);
        });
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bakeTimer?.cancel();
    _mask.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _scene.settings;
    final size = Size(settings.width, settings.height);
    final layers = SizedBox.fromSize(
      size: size,
      child: Stack(children: [
        RepaintBoundary(
          child: switch (settings.map == null ? widget.map : _mapImage) {
            null => const ColoredBox(color: Color(0xFF2E3B2E)),
            final map => RawImage(
                  image: map,
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
          },
        ),
        RepaintBoundary(
          child: CustomPaint(size: size, painter: GridPainter(settings)),
        ),
        RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: TokenPainter(
              tokens: _scene.tokens,
              drag: _c.drag,
              selected: _c.selected,
              images: widget.images,
              gm: widget.gm,
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: FogPainter(
              mask: _mask,
              revision: _fogRevision,
              preview: _c.fogPreview,
              gm: widget.gm,
              naiveOps: FogPainter.naive ? _scene.fogInOrder : null,
              naiveRepaint: FogPainter.naive ? _c.drag : null,
            ),
          ),
        ),
      ]),
    );

    return LayoutBuilder(builder: (context, constraints) {
      _c._viewport = constraints.biggest;
      // Fit the map in view at first, and again when it changes size.
      if (_fittedTo != size &&
          constraints.hasBoundedWidth &&
          constraints.hasBoundedHeight) {
        _fittedTo = size;
        _c.view.value = _fit(constraints.biggest, size);
      }
      return ClipRect(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: (_) => _up(send: true),
          onPointerCancel: (_) => _up(send: false),
          onPointerSignal: _signal,
          onPointerPanZoomStart: (_) => _lastPanZoomScale = 1,
          onPointerPanZoomUpdate: _panZoom,
          child: ValueListenableBuilder(
            valueListenable: _c.view,
            builder: (context, matrix, child) =>
                Transform(transform: matrix, child: child),
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: layers,
            ),
          ),
        ),
      );
    });
  }

  static Matrix4 _fit(Size viewport, Size map) {
    final scale = math.min(viewport.width / map.width, viewport.height / map.height);
    return Matrix4.identity()
      ..translateByDouble((viewport.width - map.width * scale) / 2,
          (viewport.height - map.height * scale) / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  Offset _toScene(Offset local) =>
      MatrixUtils.transformPoint(Matrix4.inverted(_c.view.value), local);

  void _down(PointerDownEvent e) {
    final p = _toScene(e.localPosition);
    _downAt = e.localPosition;
    _moved = false;
    final tool = widget.gm ? _c.tool : Tool.move;
    if (e.buttons != kPrimaryButton || tool == Tool.move) {
      final token = e.buttons == kPrimaryButton ? _tokenAt(p) : null;
      if (token == null) {
        _panning = true;
      } else {
        final center = Offset(token.position.x, token.position.y);
        _grab = center - p;
        _c.drag.value = (id: token.id, position: center);
        _sinceSend
          ..reset()
          ..start();
      }
    } else if (tool == Tool.fogBrush) {
      _strokePoints = [(x: p.dx, y: p.dy)];
      _previewStroke();
    } else {
      _fogStart = p;
    }
  }

  void _move(PointerMoveEvent e) {
    final p = _toScene(e.localPosition);
    if (_downAt != null && (e.localPosition - _downAt!).distance > 4) {
      _moved = true;
    }
    if (_c.drag.value case (:final id, position: _)) {
      final position = p + _grab!;
      _c.drag.value = (id: id, position: position);
      if (_sinceSend.elapsed >= dragInterval) {
        _sinceSend.reset();
        widget.send(MoveToken(id, (x: position.dx, y: position.dy)));
      }
    } else if (_panning) {
      _c.view.value = Matrix4.translationValues(e.delta.dx, e.delta.dy, 0)
        ..multiply(_c.view.value);
    } else if (_fogStart != null) {
      _c.fogPreview.value = (
        shape: FogRect((x: _fogStart!.dx, y: _fogStart!.dy), (x: p.dx, y: p.dy)),
        mode: _c.fogMode,
      );
    } else if (_strokePoints.isNotEmpty) {
      final last = _strokePoints.last;
      // Skip points closer than a quarter brush: invisible, but they'd
      // bloat the op that every player receives.
      if ((Offset(last.x, last.y) - p).distance > _c.brushRadius / 4) {
        _strokePoints.add((x: p.dx, y: p.dy));
        _previewStroke();
      }
    }
  }

  void _up({required bool send}) {
    if (_c.drag.value case (:final id, :final position)) {
      if (send && _moved) {
        final Point to = (x: position.dx, y: position.dy);
        final token = _scene.tokens[id];
        final snap = _c.snap != HardwareKeyboard.instance.isAltPressed;
        widget.send(MoveToken(
            id,
            snap && token != null
                ? _scene.settings.grid.snap(to, token.size)
                : to));
      } else if (send) {
        _c.selected.value = id; // A click, not a drag.
      }
      _c.drag.value = null;
    } else if (_panning && send && !_moved) {
      _c.selected.value = null;
    } else if (_c.fogPreview.value case (:final shape, :final mode) when send) {
      widget.send(AddFogOp(FogOpId(newId()), mode, shape));
    }
    _c.fogPreview.value = null;
    _panning = false;
    _downAt = null;
    _fogStart = null;
    _strokePoints = [];
  }

  void _previewStroke() => _c.fogPreview.value = (
        shape: FogBrush(List.of(_strokePoints), _c.brushRadius),
        mode: _c.fogMode,
      );

  void _signal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      _zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 400));
    }
  }

  void _panZoom(PointerPanZoomUpdateEvent e) {
    _c.view.value = Matrix4.translationValues(e.panDelta.dx, e.panDelta.dy, 0)
      ..multiply(_c.view.value);
    _zoomAt(e.localPosition, e.scale / _lastPanZoomScale);
    _lastPanZoomScale = e.scale;
  }

  void _zoomAt(Offset focal, double factor) {
    final current = _c.view.value.getMaxScaleOnAxis();
    final clamped = (current * factor).clamp(0.05, 8.0) / current;
    _c.view.value = (Matrix4.translationValues(focal.dx, focal.dy, 0)
          ..scaleByDouble(clamped, clamped, 1, 1)
          ..translateByDouble(-focal.dx, -focal.dy, 0, 1))
        ..multiply(_c.view.value);
  }

  /// The topmost token at [p] this client may move.
  Token? _tokenAt(Offset p) {
    for (final token in _scene.tokens.values.toList().reversed) {
      final center = Offset(token.position.x, token.position.y);
      if ((center - p).distance <= token.size / 2 &&
          (widget.gm || token.owner == widget.self)) {
        return token;
      }
    }
    return null;
  }
}
