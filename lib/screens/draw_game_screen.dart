import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room.dart';
import '../models/player.dart';
import '../models/word.dart';
import '../models/draw_action.dart';
import '../services/game_service.dart';
import '../services/supabase_service.dart';
import '../services/local_data_service.dart';
import '../utils/responsive_utils.dart';
import '../config/app_theme.dart';
import '../widgets/drawing_board.dart';
import 'result_screen.dart';

// Phase 存储在 session.answers['_phase']:
//   'selecting'  → 作画者选词
//   'drawing'    → 作画 + 猜词，计时中
//   'revealed'   → 本轮结束，展示结果 6 秒后自动跳转
class DrawGameScreen extends StatefulWidget {
  final Room room;
  final Player currentPlayer;
  final List<Player> allPlayers;

  const DrawGameScreen({
    super.key,
    required this.room,
    required this.currentPlayer,
    required this.allPlayers,
  });

  @override
  State<DrawGameScreen> createState() => _DrawGameScreenState();
}

class _DrawGameScreenState extends State<DrawGameScreen> {
  final _gameService = GameService();
  final _guessCtrl = TextEditingController();
  final _boardKey = GlobalKey<DrawingBoardState>();

  Map<String, dynamic>? _session;
  int _currentRound = 1;
  int _timeLeft = 80;
  int _revealCountdown = 6;
  bool _navigating = false;
  bool _myGuessCorrect = false;
  List<Word> _wordChoices = [];
  List<DrawAction> _remoteActions = [];
  bool _drawerTimerStarted = false;

  Timer? _syncTimer;
  Timer? _drawingTimer;
  Timer? _revealTimer;
  RealtimeChannel? _drawChannel;   // Broadcast channel for low-latency drawing sync
  RealtimeChannel? _sessionChannel; // Postgres Changes for instant phase/round sync
  bool _syncing = false; // prevents concurrent _sync() calls

  // ── 派生属性 ──
  String get _phase {
    if (_session == null) return 'loading';
    final a = Map<String, dynamic>.from(_session!['answers'] as Map? ?? {});
    return a['_phase'] as String? ?? 'selecting';
  }

  Player get _drawer {
    final idx = (_currentRound - 1) % widget.allPlayers.length;
    return widget.allPlayers[idx];
  }

  bool get _isDrawer => _drawer.id == widget.currentPlayer.id;

  String? get _currentWord => _session?['current_word'] as String?;

  Map<String, dynamic> get _answers =>
      Map<String, dynamic>.from(_session?['answers'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _drawingTimer?.cancel();
    _revealTimer?.cancel();
    _drawChannel?.unsubscribe();
    _sessionChannel?.unsubscribe();
    _guessCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────
  //  初始化：只有作画者负责建立/重置 session
  // ────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    if (_isDrawer) {
      var session = await _gameService.getActiveSession(widget.room.id);
      session ??= await _gameService.createSession(widget.room.id);
      final words = await LocalDataService.drawWords();
      await SupabaseService.client.from('game_sessions').update({
        'drawer_id': _drawer.id,
        'answers': {'_phase': 'selecting'},
        'guesses': {},
        'drawing_actions': [],
        'current_word': null,
      }).eq('id', session.id);
      if (mounted) setState(() => _wordChoices = words);
    }
    await _fetchAndApply();
    // 500ms fallback polling — Postgres Changes is the primary trigger
    _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => _sync());
  }

  // ────────────────────────────────────────────────────────────────
  //  从 Supabase 同步状态
  // ────────────────────────────────────────────────────────────────

  Future<void> _fetchAndApply() async {
    if (!mounted || _navigating) return;
    final data = await SupabaseService.client
        .from('game_sessions')
        .select()
        .eq('room_id', widget.room.id)
        .isFilter('ended_at', null)
        .maybeSingle();
    if (data == null || !mounted) return;
    _applyData(data);
    if (_drawChannel == null) _setupBroadcastChannel();
    // Postgres Changes: triggers _sync() instantly whenever game_sessions row changes.
    // This replaces sync_now broadcasts and eliminates the 1-second polling delay
    // for all phase transitions (selecting→drawing→revealed→next round).
    if (_sessionChannel == null) _setupSessionSync(data['id'] as String);
  }

  // Postgres Changes subscription — fires on any game_sessions UPDATE
  void _setupSessionSync(String sessionId) {
    _sessionChannel?.unsubscribe();
    _sessionChannel = SupabaseService.client
        .channel('session:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'game_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: sessionId,
          ),
          callback: (_) { if (mounted && !_navigating) _sync(); },
        )
        .subscribe();
  }

  // Broadcast channel: drawing sync only (no sync_now — Postgres Changes handles that)
  void _setupBroadcastChannel() {
    _drawChannel?.unsubscribe();
    _drawChannel = SupabaseService.client.channel('drawing:${widget.room.id}');
    if (!_isDrawer) {
      _drawChannel!.onBroadcast(
        event: 'draw_actions',
        callback: (payload) {
          if (!mounted || _navigating) return;
          final rawActions = payload['actions'] as List? ?? [];
          if (rawActions.isEmpty) return;
          final actions = rawActions
              .map((e) => DrawAction.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          setState(() => _remoteActions.addAll(actions));
        },
      );
    }
    _drawChannel!.subscribe();
  }

  void _applyData(Map<String, dynamic> data) {    final newRound = data['current_round'] as int;
    // Only replace remoteActions from DB if DB has MORE items than what Broadcast delivered.
    // This recovers from missed Broadcast messages without overwriting real-time state.
    if (!_isDrawer) {
      final rawActions = data['drawing_actions'] as List? ?? [];
      if (rawActions.length > _remoteActions.length) {
        final actions = rawActions
            .map((e) => DrawAction.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        setState(() => _remoteActions = actions);
      }
    }
    setState(() {
      _session = data;
      _currentRound = newRound;
    });
  }

  Future<void> _sync() async {
    if (!mounted || _navigating || _syncing) return;
    _syncing = true;
    try {
    final data = await SupabaseService.client
        .from('game_sessions')
        .select()
        .eq('room_id', widget.room.id)
        .maybeSingle();
    if (data == null || !mounted || _navigating) return;

    // Ensure channels are set up (idempotent)
    if (_drawChannel == null) _setupBroadcastChannel();
    if (_sessionChannel == null) _setupSessionSync(data['id'] as String);

    if (data['ended_at'] != null) {
      _goToResult();
      return;
    }

    final newRound = data['current_round'] as int;
    final answers = Map<String, dynamic>.from(data['answers'] as Map? ?? {});
    final newPhase = answers['_phase'] as String? ?? 'selecting';
    final prevPhase = _phase;

    // ── 轮次变化 ──
    if (newRound != _currentRound) {
      _drawingTimer?.cancel();
      _revealTimer?.cancel();
      // Update round first so _isDrawer reflects new role
      setState(() {
        _currentRound = newRound;
        _session = data;
        _myGuessCorrect = false;
        _remoteActions = [];
        _wordChoices = [];
        _timeLeft = widget.room.drawingTime;
        _revealCountdown = 6;
        _drawerTimerStarted = false;
      });
      // Re-setup Broadcast channel as drawer role may have changed
      _setupBroadcastChannel();
      if (_isDrawer) {
        _boardKey.currentState?.clearBoard();
        final words = await LocalDataService.drawWords();
        await SupabaseService.client.from('game_sessions').update({
          'drawer_id': _drawer.id,
          'answers': {'_phase': 'selecting'},
          'guesses': {},
          'drawing_actions': [],
          'current_word': null,
        }).eq('id', data['id']);
        if (mounted) setState(() => _wordChoices = words);
      }
      return;
    }

    // ── selecting → drawing（猜词方开始计时）──
    if (newPhase == 'drawing' && prevPhase == 'selecting') {
      _applyData(data);
      if (!_isDrawer) _startGuesserTimer();
      return;
    }

    // ── drawing → revealed ──
    if (newPhase == 'revealed' && prevPhase != 'revealed') {
      _drawingTimer?.cancel();
      _applyData(data);
      _startRevealTimer();
      return;
    }

    // 所有人猜对 → 作画者触发揭晓
    if (newPhase == 'drawing' && _isDrawer) {
      final correctCount = answers.entries
          .where((e) => !e.key.startsWith('_') && (e.value as Map?)?['correct'] == true)
          .length;
      if (correctCount >= widget.allPlayers.length - 1) {
        await _doReveal();
        return;
      }
    }

    _applyData(data);
    } finally {
      _syncing = false;
    }
  }

  // ────────────────────────────────────────────────────────────────
  //  计时器
  // ────────────────────────────────────────────────────────────────

  void _startGuesserTimer() {
    _drawingTimer?.cancel();
    setState(() => _timeLeft = widget.room.drawingTime);
    _drawingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_timeLeft <= 0) {
        t.cancel();
      } else {
        setState(() => _timeLeft--);
      }
    });
  }

  void _startDrawerTimer() {
    if (_drawerTimerStarted) return;
    _drawerTimerStarted = true;
    _drawingTimer?.cancel();
    setState(() => _timeLeft = widget.room.drawingTime);
    _drawingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_timeLeft <= 0) {
        t.cancel();
        _doReveal();
      } else {
        setState(() => _timeLeft--);
      }
    });
  }

  void _startRevealTimer() {
    _revealTimer?.cancel();
    setState(() => _revealCountdown = 6);
    _revealTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_revealCountdown <= 1) {
        t.cancel();
        if (_isDrawer) _advanceRound();
      } else {
        setState(() => _revealCountdown--);
      }
    });
  }

  // ────────────────────────────────────────────────────────────────
  //  动作
  // ────────────────────────────────────────────────────────────────

  Future<void> _selectWord(Word word) async {
    if (_session == null || !_isDrawer) return;
    _boardKey.currentState?.clearBoard();
    await SupabaseService.client.from('game_sessions').update({
      'current_word': word.text,
      'answers': {'_phase': 'drawing'},
      'drawing_actions': [],
    }).eq('id', _session!['id']);
    setState(() => _wordChoices = []);
    _applyData({
      ..._session!,
      'current_word': word.text,
      'answers': {'_phase': 'drawing'},
      'drawing_actions': [],
    });
    _startDrawerTimer();
  }

  Future<void> _doReveal() async {
    if (_session == null) return;
    _drawingTimer?.cancel();

    // 重新拉取最新数据（防止 answers 不是最新的）
    final fresh = await SupabaseService.client
        .from('game_sessions')
        .select()
        .eq('id', _session!['id'])
        .single();
    final freshAnswers = Map<String, dynamic>.from(fresh['answers'] as Map? ?? {});
    if (freshAnswers['_phase'] == 'revealed') {
      _applyData(fresh);
      if (_phase != 'revealed') _startRevealTimer();
      return;
    }

    // 作画者得分：2 + 猜对人数（最多 +2）
    final correctCount = freshAnswers.values
        .where((v) => v is Map && v['correct'] == true)
        .length;
    if (correctCount > 0) {
      await _gameService.updatePlayerScore(_drawer.id, 2 + correctCount.clamp(0, 2));
    }

    freshAnswers['_phase'] = 'revealed';
    await SupabaseService.client.from('game_sessions').update({
      'answers': freshAnswers,
    }).eq('id', _session!['id']);

    if (mounted) {
      _applyData({...fresh, 'answers': freshAnswers});
      _startRevealTimer();
    }
  }

  Future<void> _submitGuess() async {
    if (_myGuessCorrect || _session == null) return;
    final guess = _guessCtrl.text.trim();
    if (guess.isEmpty) return;

    final word = _currentWord ?? '';
    final correct = guess.trim().toLowerCase() == word.trim().toLowerCase();

    if (correct) {
      _guessCtrl.clear();
      // Optimistic update: show ✅ immediately, write to DB in background
      setState(() => _myGuessCorrect = true);

      final ts = DateTime.now().millisecondsSinceEpoch;
      final newAnswers = Map<String, dynamic>.from(_answers);
      newAnswers[widget.currentPlayer.id] = {'correct': true, 'time': ts};
      await SupabaseService.client.from('game_sessions').update({
        'answers': newAnswers,
      }).eq('id', _session!['id']);

      // 第 1 个猜对 +3，第 2 个 +2，之后 +1
      final idx = newAnswers.keys.where((k) => !k.startsWith('_')).length;
      final score = idx <= 1 ? 3 : idx == 2 ? 2 : 1;
      await _gameService.updatePlayerScore(widget.currentPlayer.id, score);
    } else {
      _guessCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('不对，继续猜！'), duration: Duration(seconds: 1)));
      }
    }
  }

  Future<void> _onDrawActionsAdded(List<DrawAction> actions) async {
    // Broadcast immediately for real-time sync — no DB write, no growing payload
    await _drawChannel?.sendBroadcastMessage(
      event: 'draw_actions',
      payload: {'actions': actions.map((a) => a.toJson()).toList()},
    );
    // Clear action: also reset DB so late-joining guessers see blank board
    if (actions.any((a) => a.type == 'clear') && _session != null) {
      await SupabaseService.client.from('game_sessions').update({
        'drawing_actions': [],
      }).eq('id', _session!['id']);
    }
  }

  // Called once per completed stroke — writes to DB for persistence only
  Future<void> _onStrokeEnd(List<DrawAction> stroke) async {
    if (_session == null) return;
    await _gameService.appendDrawActions(
      _session!['id'] as String,
      stroke.map((a) => a.toJson()).toList(),
    );
  }

  Future<void> _advanceRound() async {
    if (_navigating || _session == null || _phase != 'revealed') return;
    final nextRound = _currentRound + 1;
    if (nextRound > widget.room.rounds) {
      await _gameService.endSession(_session!['id'] as String);
      _goToResult();
    } else {
      // Clear drawing_actions atomically with the round increment so no client
      // ever sees old drawing data after _applyData runs on the new round.
      await SupabaseService.client.from('game_sessions').update({
        'current_round': nextRound,
        'answers': {'_phase': 'selecting'},
        'current_word': null,
        'drawing_actions': [],
      }).eq('id', _session!['id']);
    }
  }

  void _goToResult() async {
    if (_navigating || !mounted) return;
    setState(() => _navigating = true);
    _syncTimer?.cancel();
    _drawingTimer?.cancel();
    _revealTimer?.cancel();

    final data = await SupabaseService.client
        .from('players')
        .select()
        .eq('room_id', widget.room.id);
    final players = (data as List).map((e) => Player.fromJson(e)).toList();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            players: players,
            gameMode: 'draw',
            room: widget.room,
            currentPlayer: widget.currentPlayer,
          ),
        ),
      );
    }
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出游戏'),
        content: const Text('确定要退出游戏回到主页吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _syncTimer?.cancel();
              _drawingTimer?.cancel();
              _revealTimer?.cancel();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────
  //  UI
  // ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final phase = _phase;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('你画我猜 · 第$_currentRound/${widget.room.rounds}轮 · ${_drawer.name}作画'),
          actions: [
            if (phase == 'drawing')
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _timeLeft <= 10 ? AppTheme.error : AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_timeLeft秒',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: _confirmExit,
              tooltip: '退出游戏',
            ),
          ],
        ),
        body: _buildBody(context, phase),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String phase) {
    switch (phase) {
      case 'selecting':
        return _isDrawer
            ? _buildWordSelection(context)
            : _buildWaiting(context, '等待 ${_drawer.name} 选词...');
      case 'drawing':
        return ResponsiveUtils.isTablet(context)
            ? _buildTabletDrawing(context)
            : _buildPhoneDrawing(context);
      case 'revealed':
        return _buildReveal(context);
      default:
        return _buildWaiting(context, '加载中...');
    }
  }

  Widget _buildWaiting(BuildContext context, String msg) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(msg, style: Theme.of(context).textTheme.titleMedium),
      ]),
    );
  }

  Widget _buildWordSelection(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('选择要画的词', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 32),
          if (_wordChoices.isEmpty)
            const CircularProgressIndicator()
          else
            ..._wordChoices.map((word) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _selectWord(word),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(word.text, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    _DifficultyChip(word.difficulty),
                  ]),
                ),
              ),
            )),
        ]),
      ),
    );
  }

  Widget _buildPhoneDrawing(BuildContext context) {
    return Column(children: [
      // 状态栏
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppTheme.primary.withAlpha(20),
        child: Row(children: [
          if (_isDrawer && _currentWord != null)
            Text('词语: ${_currentWord!}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
          else
            Text(
              '${_currentWord != null ? "${_currentWord!.length}个字 · " : ""}${_drawer.name} 正在作画',
              style: const TextStyle(fontSize: 14),
            ),
          const Spacer(),
          if (_isDrawer)
            Text('$_timeLeft秒',
                style: TextStyle(
                    color: _timeLeft <= 10 ? AppTheme.error : null,
                    fontWeight: FontWeight.bold))
          else if (_myGuessCorrect)
            const Text('✅ 猜对！',
                style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold))
          else
            Text('$_timeLeft秒',
                style: TextStyle(color: _timeLeft <= 10 ? AppTheme.error : null)),
        ]),
      ),
      // 画板
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DrawingBoard(
            key: _boardKey,
            isDrawer: _isDrawer,
            remoteActions: _remoteActions,
            onActionsAdded: _onDrawActionsAdded,
            onStrokeEnd: _onStrokeEnd,
          ),
        ),
      ),
      // 猜词输入（仅猜词方显示）
      if (!_isDrawer)
        _myGuessCorrect
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Text('✅ 猜对了！等待其他人...',
                    style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold)))
            : Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _guessCtrl,
                      decoration:
                          const InputDecoration(hintText: '输入你的猜测...', isDense: true),
                      onSubmitted: (_) => _submitGuess(),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.send), onPressed: _submitGuess),
                ]),
              ),
    ]);
  }

  Widget _buildTabletDrawing(BuildContext context) {
    return Row(children: [
      Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            if (_isDrawer && _currentWord != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('词语: ${_currentWord!}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  Text('$_timeLeft秒',
                      style: TextStyle(
                          color: _timeLeft <= 10 ? AppTheme.error : null, fontSize: 18)),
                ]),
              ),
            Expanded(
              child: DrawingBoard(
                key: _boardKey,
                isDrawer: _isDrawer,
                remoteActions: _remoteActions,
                onActionsAdded: _onDrawActionsAdded,
                onStrokeEnd: _onStrokeEnd,
              ),
            ),
          ]),
        ),
      ),
      if (!_isDrawer)
        SizedBox(width: 280, child: _buildGuesserPanel()),
    ]);
  }

  Widget _buildGuesserPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${_drawer.name} 正在作画',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        if (_currentWord != null)
          Text('提示：${_currentWord!.length}个字',
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
        Text('$_timeLeft秒',
            style: TextStyle(color: _timeLeft <= 10 ? AppTheme.error : null)),
        const Spacer(),
        if (!_myGuessCorrect) ...[
          TextField(
            controller: _guessCtrl,
            decoration: const InputDecoration(hintText: '输入猜测...', isDense: true),
            onSubmitted: (_) => _submitGuess(),
          ),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _submitGuess, child: const Text('提交猜测')),
        ] else
          const Text('✅ 猜对了！',
              style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildReveal(BuildContext context) {
    final word = _currentWord ?? '?';
    final correctGuessers = widget.allPlayers.where((p) {
      if (p.id == _drawer.id) return false;
      final val = _answers[p.id];
      return val is Map && val['correct'] == true;
    }).toList();
    final isLastRound = _currentRound >= widget.room.rounds;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('本轮结束！', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              const Text('词语是：', style: TextStyle(color: Colors.grey)),
              Text(word,
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(color: AppTheme.primary)),
            ]),
          ),
          const SizedBox(height: 16),
          Text('作画者：${_drawer.name}'),
          const SizedBox(height: 8),
          if (correctGuessers.isEmpty)
            const Text('无人猜对')
          else ...[
            const Text('猜对了：'),
            ...correctGuessers.map((p) =>
                Text('✅ ${p.name}', style: const TextStyle(color: AppTheme.success))),
          ],
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(
              isLastRound ? '$_revealCountdown 秒后查看排行榜' : '$_revealCountdown 秒后下一轮',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ]),
        ]),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final String difficulty;
  const _DifficultyChip(this.difficulty);

  @override
  Widget build(BuildContext context) {
    final colors = {
      'easy': AppTheme.success,
      'medium': AppTheme.warning,
      'hard': AppTheme.error,
    };
    final labels = {'easy': '简单', 'medium': '中等', 'hard': '困难'};
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors[difficulty] ?? Colors.grey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        labels[difficulty] ?? difficulty,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
    );
  }
}
