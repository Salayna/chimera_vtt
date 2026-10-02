import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'fog_mask.dart';
import 'layers.dart';

enum Tool { move, fogBrush, fogRect, gridFit }

/// The view's fast-changing state, outside the widget tree so it can change
/// every frame without rebuilds. Owned by whoever creates it. Notifies when
/// a tool option changes, for the chrome around the view.
class TableController extends ChangeNotifier {
  final view = ValueNotifier<Matrix4>(Matrix4.identity());
  final drag = ValueNotifier<TokenDrag?>(null);
  final fogPreview = ValueNotifier<FogPreview?>(null);

  /// The grid fitted to the box being drawn with [Tool.gridFit].
  final gridFit = ValueNotifier<Grid?>(null);
  final selected = ValueNotifier<TokenId?>(null);

  Tool get tool => _tool;
  Tool _tool = Tool.move;
  set tool(Tool value) => _set(() => _tool = value);

  /// Dropped tokens snap to the grid. Holding Alt places one freely.
  bool get snap => _snap;
  bool _snap = true;
  set snap(bool value) => _set(() => _snap = value);

  FogMode get fogMode => _fogMode;
  FogMode _fogMode = FogMode.cover;
  set fogMode(FogMode value) => _set(() => _fogMode = value);

  /// The GM's grid panel is open. Closing it puts away the fit tool.
  bool get gridOptions => _gridOptions;
  bool _gridOptions = false;
  void toggleGridOptions() => _set(() {
        _gridOptions = !_gridOptions;
        if (!_gridOptions && _tool == Tool.gridFit) _tool = Tool.move;
      });

  double get brushRadius => _brushRadius;
  double _brushRadius = 48;
  set brushRadius(double value) => _set(() => _brushRadius = value);

  void _set(void Function() change) {
    change();
    notifyListeners();
  }

  Size _viewport = Size.zero;
  Size _map = Size.zero;

  /// The scene point at the middle of the view, to place new things.
  Point get viewCenter {
    final c = MatrixUtils.transformPoint(
        Matrix4.inverted(view.value), _viewport.center(Offset.zero));
    return (x: c.dx, y: c.dy);
  }

  /// Screen pixels per map pixel. (Not getMaxScaleOnAxis: z stays 1, so
  /// that never reads below 100%.)
  double get zoom => view.value.entry(0, 0);

  /// Zooms by [factor] around [focal], or the middle of the view.
  void zoomBy(double factor, [Offset? focal]) {
    final f = focal ?? _viewport.center(Offset.zero);
    final clamped = (zoom * factor).clamp(0.05, 8.0) / zoom;
    view.value = (Matrix4.translationValues(f.dx, f.dy, 0)
          ..scaleByDouble(clamped, clamped, 1, 1)
          ..translateByDouble(-f.dx, -f.dy, 0, 1))
        ..multiply(view.value);
  }

  /// The whole map in view.
  void fit() {
    if (_viewport.isEmpty || _map.isEmpty) return;
    final scale = math.min(
        _viewport.width / _map.width, _viewport.height / _map.height);
    view.value = Matrix4.identity()
      ..translateByDouble((_viewport.width - _map.width * scale) / 2,
          (_viewport.height - _map.height * scale) / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// Puts [p] in the middle of the view, at no less than 100%.
  // ponytail: jumps; the design eases over CvMotion.pan.
  void centerOn(Point p) {
    final z = math.max(zoom, 1.0);
    final c = _viewport.center(Offset.zero);
    view.value = Matrix4.identity()
      ..translateByDouble(c.dx - p.x * z, c.dy - p.y * z, 0, 1)
      ..scaleByDouble(z, z, 1, 1);
  }

  /// Where scene point [p] is on screen.
  Offset toScreen(Point p) =>
      MatrixUtils.transformPoint(view.value, Offset(p.x, p.y));

  @override
  void dispose() {
    view.dispose();
    drag.dispose();
    fogPreview.dispose();
    gridFit.dispose();
    selected.dispose();
    super.dispose();
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
  Offset? _fitStart;
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
            null => const ColoredBox(color: CvColors.bgSunken),
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
          child: CustomPaint(
              size: size,
              painter: GridPainter(settings, widget.gm ? _c : null)),
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
              self: widget.self,
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
      _c._map = size;
      // Fit the map in view at first, and again when it changes size.
      if (_fittedTo != size &&
          constraints.hasBoundedWidth &&
          constraints.hasBoundedHeight) {
        _fittedTo = size;
        // After the frame: fit() notifies view, which can't be dirtied mid-build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _c.fit();
        });
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
    } else if (tool == Tool.fogRect) {
      _fogStart = p;
    } else {
      _fitStart = p;
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
    } else if (_fitStart case final start?) {
      _c.gridFit.value =
          Grid.fitted((x: start.dx, y: start.dy), (x: p.dx, y: p.dy));
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
    } else if (_c.gridFit.value case final grid? when send && grid.valid) {
      widget.send(UpdateSettings(_scene.settings.copyWith(grid: grid)));
      _c.tool = Tool.move;
    }
    _c.fogPreview.value = null;
    _c.gridFit.value = null;
    _fitStart = null;
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
      _c.zoomBy(math.exp(-e.scrollDelta.dy / 400), e.localPosition);
    }
  }

  void _panZoom(PointerPanZoomUpdateEvent e) {
    _c.view.value = Matrix4.translationValues(e.panDelta.dx, e.panDelta.dy, 0)
      ..multiply(_c.view.value);
    _c.zoomBy(e.scale / _lastPanZoomScale, e.localPosition);
    _lastPanZoomScale = e.scale;
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
