import 'dart:async';
import 'package:flutter/material.dart';
import '../models/draw_action.dart';
import '../config/app_colors.dart';
import '../config/app_theme.dart';

class DrawingBoard extends StatefulWidget {
  final bool isDrawer;
  final List<DrawAction> remoteActions;
  final void Function(List<DrawAction> actions) onActionsAdded;
  final void Function(List<DrawAction> stroke)? onStrokeEnd; // called once per stroke for DB persistence

  const DrawingBoard({
    super.key,
    required this.isDrawer,
    required this.remoteActions,
    required this.onActionsAdded,
    this.onStrokeEnd,
  });

  @override
  State<DrawingBoard> createState() => DrawingBoardState();
}

class DrawingBoardState extends State<DrawingBoard> {
  final List<DrawAction> _localActions = [];
  final List<DrawAction> _pendingSync = [];
  final List<DrawAction> _currentStroke = []; // tracks points in current stroke for DB persistence
  Color _color = Colors.black;
  double _strokeWidth = 5.0;
  bool _isEraser = false;
  Timer? _syncTimer;
  Size _canvasSize = Size.zero;

  @override
  void initState() {
    super.initState();
    if (widget.isDrawer) {
      _syncTimer = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => _flushPending(),
      );
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  void _flushPending() {
    if (_pendingSync.isNotEmpty) {
      widget.onActionsAdded(List.from(_pendingSync));
      _pendingSync.clear();
    }
  }

  void clearBoard() {
    _currentStroke.clear();
    final action = DrawAction(
      type: 'clear',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      _localActions.clear();
      _localActions.add(action);
    });
    _pendingSync.add(action);
  }

  void undo() {
    if (_localActions.isEmpty) return;
    final action = DrawAction(
      type: 'undo',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() {
      // 移除最后一笔（找到最后一条 draw 的起始点前的所有点）
      if (_localActions.isNotEmpty) _localActions.removeLast();
    });
    _pendingSync.add(action);
  }

  @override
  void didUpdateWidget(DrawingBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isDrawer &&
        widget.remoteActions.length != oldWidget.remoteActions.length) {
      setState(() {});
    }
  }

  List<DrawAction> get _displayActions =>
      widget.isDrawer ? _localActions : widget.remoteActions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                onPanStart: widget.isDrawer
                    ? (d) => _addPoint(d.localPosition, isStart: true)
                    : null,
                onPanUpdate: widget.isDrawer
                    ? (d) => _addPoint(d.localPosition)
                    : null,
                onPanEnd: widget.isDrawer ? (_) => _addEndMarker() : null,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: _DrawingPainter(actions: _displayActions),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.isDrawer) _buildToolbar(),
      ],
    );
  }

  void _addPoint(Offset point, {bool isStart = false}) {
    // Normalize to [0,1] relative to canvas size so coordinates are
    // device-independent when rendered on different screen sizes
    final nx = _canvasSize.width > 0 ? point.dx / _canvasSize.width : 0.0;
    final ny = _canvasSize.height > 0 ? point.dy / _canvasSize.height : 0.0;
    final action = DrawAction(
      type: isStart ? 'draw_start' : 'draw',
      point: Offset(nx, ny),
      color: _isEraser ? Colors.white : _color,
      strokeWidth: _isEraser ? 20.0 : _strokeWidth,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    if (isStart) _currentStroke.clear();
    _currentStroke.add(action);
    setState(() => _localActions.add(action));
    _pendingSync.add(action);
  }

  void _addEndMarker() {
    final action = DrawAction(
      type: 'draw_end',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    setState(() => _localActions.add(action));
    _pendingSync.add(action);
    _currentStroke.add(action);
    // Notify parent to persist this complete stroke to DB
    if (widget.onStrokeEnd != null && _currentStroke.length > 1) {
      widget.onStrokeEnd!(List.from(_currentStroke));
    }
    _currentStroke.clear();
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          // 颜色选择
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: AppColors.drawingColors.map((c) {
                final isSelected = !_isEraser && _color == c;
                return GestureDetector(
                  onTap: () => setState(() {
                    _color = c;
                    _isEraser = false;
                  }),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isSelected ? 36 : 28,
                    height: isSelected ? 36 : 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : Colors.grey,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 橡皮擦
              IconButton(
                icon: Icon(
                  Icons.auto_fix_high,
                  color: _isEraser ? AppTheme.primary : Colors.grey,
                ),
                onPressed: () => setState(() => _isEraser = !_isEraser),
              ),
              // 粗细
              Expanded(
                child: Slider(
                  value: _strokeWidth,
                  min: 2,
                  max: 20,
                  onChanged: (v) => setState(() => _strokeWidth = v),
                ),
              ),
              // 撤销
              IconButton(
                icon: const Icon(Icons.undo),
                onPressed: undo,
              ),
              // 清屏
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: clearBoard,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<DrawAction> actions;

  _DrawingPainter({required this.actions});

  Offset _scale(Offset p, Size size) =>
      Offset(p.dx * size.width, p.dy * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    Paint? currentPaint;
    Offset? lastPoint;
    bool isDrawing = false;

    for (final action in actions) {
      if (action.type == 'clear') {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..color = Colors.white,
        );
        lastPoint = null;
        isDrawing = false;
      } else if (action.type == 'draw_start') {
        currentPaint = Paint()
          ..color = action.color ?? Colors.black
          ..strokeWidth = action.strokeWidth ?? 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        lastPoint = action.point != null ? _scale(action.point!, size) : null;
        isDrawing = true;
      } else if (action.type == 'draw' && isDrawing && lastPoint != null) {
        if (action.point != null && currentPaint != null) {
          final scaledPoint = _scale(action.point!, size);
          canvas.drawLine(lastPoint, scaledPoint, currentPaint);
          lastPoint = scaledPoint;
        }
      } else if (action.type == 'draw_end') {
        isDrawing = false;
        lastPoint = null;
      }
    }
  }

  @override
  bool shouldRepaint(_DrawingPainter old) => old.actions.length != actions.length;
}
