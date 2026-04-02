import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../models/player.dart';
import '../models/question.dart';
import '../services/game_service.dart';
import '../services/supabase_service.dart';
import '../services/local_data_service.dart';
import '../utils/responsive_utils.dart';
import '../config/app_theme.dart';
import 'result_screen.dart';

// 游戏阶段（存储在 session.answers['_phase']）：
//   'setup'     → 出题者正在设置题目和答案
//   'answering' → 出题者已设置，其他人答题中（倒计时运行）
//   'revealed'  → 揭晓答案阶段
class QuizGameScreen extends ConsumerStatefulWidget {
  final Room room;
  final Player currentPlayer;
  final List<Player> allPlayers;

  const QuizGameScreen({
    super.key,
    required this.room,
    required this.currentPlayer,
    required this.allPlayers,
  });

  @override
  ConsumerState<QuizGameScreen> createState() => _QuizGameScreenState();
}

class _QuizGameScreenState extends ConsumerState<QuizGameScreen> {
  final _gameService = GameService();

  // ── Supabase session 数据 ──
  Map<String, dynamic>? _session; // 直接存原始 map，方便读取 answers['_phase']
  int _currentRound = 1;
  String _phase = 'setup'; // 'setup' | 'answering' | 'revealed'
  String _currentQuestion = '';
  String? _questionerId;
  Map<String, dynamic> _answers = {};

  // ── 本地 UI 状态 ──
  String? _myAnswer;
  bool _hasStartedCountdown = false;
  int _timeLeft = 30;
  bool _navigating = false;
  int _revealCountdown = 6;
  Timer? _revealTimer;

  // ── 出题者设置 UI ──
  final _customQuestionCtrl = TextEditingController();
  final _answerCtrl = TextEditingController();
  bool _isCustomMode = false;
  Question? _presetQuestion;

  Timer? _syncTimer;
  Timer? _countdownTimer;

  // ── 派生状态 ──
  Player get _questioner {
    final idx = (_currentRound - 1) % widget.allPlayers.length;
    return widget.allPlayers[idx];
  }

  bool get _isQuestioner => _questioner.id == widget.currentPlayer.id;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _countdownTimer?.cancel();
    _revealTimer?.cancel();
    _customQuestionCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────
  //  初始化
  // ────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    // 获取或创建 session
    var session = await _gameService.getActiveSession(widget.room.id);
    session ??= await _gameService.createSession(widget.room.id);

    // 出题者负责初始化第一轮状态
    final questionerIdx = (session.currentRound - 1) % widget.allPlayers.length;
    final isQuestioner = widget.allPlayers[questionerIdx].id == widget.currentPlayer.id;

    if (isQuestioner) {
      final q = await LocalDataService.randomQuestion();
      await SupabaseService.client.from('game_sessions').update({
        'current_question': q.text,
        'questioner_id': widget.currentPlayer.id,
        'answers': {'_phase': 'setup'},
        'guesses': {},
        'drawing_actions': [],
      }).eq('id', session.id);
      if (mounted) setState(() => _presetQuestion = q);
    }

    await _fetchAndApplySession();

    // 每 2 秒轮询同步
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sync());
  }

  // ────────────────────────────────────────────────────────────────
  //  从 Supabase 同步状态
  // ────────────────────────────────────────────────────────────────

  Future<void> _fetchAndApplySession() async {
    if (!mounted || _navigating) return;
    final data = await SupabaseService.client
        .from('game_sessions')
        .select()
        .eq('room_id', widget.room.id)
        .isFilter('ended_at', null)
        .maybeSingle();
    if (data == null || !mounted) return;

    final answers = Map<String, dynamic>.from(data['answers'] as Map? ?? {});
    final newRound = data['current_round'] as int;
    final newPhase = answers['_phase'] as String? ?? 'setup';
    final newQuestion = data['current_question'] as String? ?? '';

    setState(() {
      _session = data;
      _currentRound = newRound;
      _phase = newPhase;
      _currentQuestion = newQuestion;
      _questionerId = data['questioner_id'] as String?;
      _answers = answers;
    });
  }

  Future<void> _sync() async {
    if (!mounted || _navigating) return;

    final data = await SupabaseService.client
        .from('game_sessions')
        .select()
        .eq('room_id', widget.room.id)
        .maybeSingle();

    if (data == null || !mounted || _navigating) return;

    // 游戏已结束
    if (data['ended_at'] != null) {
      _goToResult();
      return;
    }

    final newRound = data['current_round'] as int;
    final answers = Map<String, dynamic>.from(data['answers'] as Map? ?? {});
    final newPhase = answers['_phase'] as String? ?? 'setup';
    final newQuestion = data['current_question'] as String? ?? '';

    // ── 检测轮次变化 ──
    if (newRound != _currentRound) {
      _countdownTimer?.cancel();
      setState(() {
        _currentRound = newRound;
        _phase = 'setup';
        _currentQuestion = newQuestion;
        _answers = answers;
        _myAnswer = null;
        _hasStartedCountdown = false;
        _timeLeft = 30;
        _isCustomMode = false;
        _customQuestionCtrl.clear();
        _answerCtrl.clear();
        _session = data;
      });

      // 新轮次的出题者初始化题目
      if (_isQuestioner) {
        final q = await LocalDataService.randomQuestion();
        await SupabaseService.client.from('game_sessions').update({
          'current_question': q.text,
          'questioner_id': widget.currentPlayer.id,
          'answers': {'_phase': 'setup'},
        }).eq('id', data['id']);
        if (mounted) setState(() => _presetQuestion = q);
      }
      return;
    }

    // ── 阶段变化：setup → answering（非出题者开始倒计时）──
    if (newPhase == 'answering' && _phase == 'setup' && !_isQuestioner) {
      if (!_hasStartedCountdown) {
        setState(() {
          _phase = newPhase;
          _currentQuestion = newQuestion;
          _answers = answers;
          _session = data;
          _hasStartedCountdown = true;
        });
        _startCountdown();
        return;
      }
    }

    // ── 阶段变化：answering → revealed ──
    if (newPhase == 'revealed' && _phase != 'revealed') {
      _countdownTimer?.cancel();
      setState(() {
        _phase = newPhase;
        _answers = answers;
        _currentQuestion = newQuestion;
        _session = data;
      });
      _startRevealCountdown();
      return;
    }

    // 普通更新
    setState(() {
      _phase = newPhase;
      _answers = answers;
      _currentQuestion = newQuestion;
      _session = data;
    });

    // 出题者检测：所有人已作答 → 自动揭晓
    if (newPhase == 'answering' && _isQuestioner) {
      final realAnswers = answers.keys.where((k) => !k.startsWith('_')).length;
      if (realAnswers >= widget.allPlayers.length) {
        await _doReveal();
      }
    }
  }

  // ────────────────────────────────────────────────────────────────
  //  倒计时
  // ────────────────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _timeLeft = 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_timeLeft <= 0) {
        t.cancel();
        // 出题者负责触发揭晓
        if (_isQuestioner && _phase == 'answering') _doReveal();
      } else {
        setState(() => _timeLeft--);
      }
    });
  }

  // ────────────────────────────────────────────────────────────────
  //  动作
  // ────────────────────────────────────────────────────────────────

  /// 出题者提交题目和答案，开始出题
  Future<void> _submitSetup() async {
    if (_session == null) return;
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入你的答案')));
      return;
    }
    final questionText = _isCustomMode
        ? _customQuestionCtrl.text.trim()
        : (_presetQuestion?.text ?? '');
    if (questionText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入题目')));
      return;
    }

    await SupabaseService.client.from('game_sessions').update({
      'current_question': questionText,
      'questioner_id': widget.currentPlayer.id,
      'answers': {'_phase': 'answering', widget.currentPlayer.id: answer},
    }).eq('id', _session!['id']);

    setState(() {
      _phase = 'answering';
      _currentQuestion = questionText;
      _myAnswer = answer;
      _hasStartedCountdown = true;
      _answers = {'_phase': 'answering', widget.currentPlayer.id: answer};
    });
    _startCountdown();
  }

  /// 猜题者提交答案
  Future<void> _submitAnswer(String answer) async {
    if (_session == null || _myAnswer != null || _phase != 'answering') return;
    setState(() => _myAnswer = answer);

    final newAnswers = Map<String, dynamic>.from(_answers);
    newAnswers[widget.currentPlayer.id] = answer;
    await SupabaseService.client.from('game_sessions').update({
      'answers': newAnswers,
    }).eq('id', _session!['id']);
  }

  /// 揭晓答案 + 计算分数（由出题者执行）
  Future<void> _doReveal() async {
    if (_phase == 'revealed' || _session == null) return;
    _countdownTimer?.cancel();

    // 重新拉取最新 session 确保答案完整
    final fresh = await SupabaseService.client
        .from('game_sessions').select()
        .eq('id', _session!['id']).single();
    final freshAnswers = Map<String, dynamic>.from(fresh['answers'] as Map? ?? {});

    // 计算得分
    final questionerAnswer = freshAnswers[_questioner.id] as String? ?? '';
    for (final player in widget.allPlayers) {
      if (player.id == _questioner.id) continue;
      final ans = freshAnswers[player.id] as String? ?? '';
      if (ans.trim().toLowerCase() == questionerAnswer.trim().toLowerCase()) {
        await _gameService.updatePlayerScore(player.id, 1);
      }
    }

    // 更新阶段为 revealed
    freshAnswers['_phase'] = 'revealed';
    await SupabaseService.client.from('game_sessions').update({
      'answers': freshAnswers,
    }).eq('id', _session!['id']);

    if (mounted) {
      setState(() {
        _phase = 'revealed';
        _answers = freshAnswers;
      });
      _startRevealCountdown();
    }
  }

  /// 揭晓后 6 秒自动跳轮（出题者写 Supabase，其他人通过 _sync 检测）
  void _startRevealCountdown() {
    _revealTimer?.cancel();
    setState(() => _revealCountdown = 6);
    _revealTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_revealCountdown <= 1) {
        t.cancel();
        if (_isQuestioner) _nextRound();
      } else {
        setState(() => _revealCountdown--);
      }
    });
  }

  /// 房主进入下一轮
  Future<void> _nextRound() async {
    if (_session == null) return;
    final nextRound = _currentRound + 1;

    if (nextRound > widget.room.rounds) {
      await _gameService.endSession(_session!['id'] as String);
      _goToResult();
      return;
    }

    // 写入新轮次，出题者由 _sync() 检测到轮次变化后自动初始化
    await SupabaseService.client.from('game_sessions').update({
      'current_round': nextRound,
      'answers': {'_phase': 'setup'},
      'current_question': '',
      'questioner_id': null,
    }).eq('id', _session!['id']);
  }

  void _goToResult() async {
    if (_navigating || !mounted) return;
    setState(() => _navigating = true);
    _syncTimer?.cancel();
    _countdownTimer?.cancel();
    _revealTimer?.cancel();

    final data = await SupabaseService.client
        .from('players').select().eq('room_id', widget.room.id);
    final players = (data as List).map((e) => Player.fromJson(e)).toList();
    if (mounted) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => ResultScreen(
          players: players,
          gameMode: 'quiz',
          room: widget.room,
          currentPlayer: widget.currentPlayer,
        )));
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
              _countdownTimer?.cancel();
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

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text('默契问答 · 第$_currentRound/${widget.room.rounds}轮'),
          actions: [
            if (_phase == 'answering')
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
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case 'setup':
        return _isQuestioner
            ? _buildQuestionerSetup(context)
            : _buildWaiting(context, '等待 ${_questioner.name} 出题...');
      case 'answering':
        if (_isQuestioner) {
          return _buildWaiting(context,
              '等待玩家作答... ${_answers.keys.where((k) => !k.startsWith("_")).length - 1}/${widget.allPlayers.length - 1}\n剩余 $_timeLeft 秒',
              showTimer: true);
        }
        return _myAnswer != null
            ? _buildWaiting(context, '已提交答案: $_myAnswer\n等待其他人...\n剩余 $_timeLeft 秒', showTimer: true)
            : _buildAnswerView(context);
      case 'revealed':
        return _buildRevealView(context);
      default:
        return const Center(child: CircularProgressIndicator());
    }
  }

  Widget _buildWaiting(BuildContext context, String message, {bool showTimer = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionerSetup(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(50),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.star, color: Colors.amber),
              const SizedBox(width: 8),
              Text('你是第${_currentRound}轮出题者！',
                  style: Theme.of(context).textTheme.titleLarge),
            ]),
          ),
          const SizedBox(height: 24),
          Row(children: [
            const Text('预设题目'),
            Switch(
              value: _isCustomMode,
              onChanged: (v) => setState(() => _isCustomMode = v),
            ),
            const Text('自定义问题'),
          ]),
          const SizedBox(height: 8),
          if (_isCustomMode)
            TextField(
              controller: _customQuestionCtrl,
              decoration: const InputDecoration(
                labelText: '输入你的问题（让大家猜关于你的答案）',
                hintText: '例如：我最喜欢的明星？',
              ),
              maxLength: 50,
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('预设题目：', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Text(
                      _presetQuestion?.text ?? '加载中...',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          TextField(
            controller: _answerCtrl,
            decoration: const InputDecoration(
              labelText: '你的真实答案（只有你看得到）',
              hintText: '输入你的答案',
            ),
            maxLength: 30,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitSetup,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始出题，让大家答！'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnswerView(BuildContext context) {
    final isTablet = ResponsiveUtils.isTablet(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('出题者: ${_questioner.name}',
                  style: Theme.of(context).textTheme.bodyMedium),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _timeLeft <= 10 ? AppTheme.error : AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_timeLeft秒',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(
            _currentQuestion,
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              fontSize: isTablet ? 32 : 22,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          _AnswerInput(onSubmit: _submitAnswer),
        ],
      ),
    );
  }

  Widget _buildRevealView(BuildContext context) {
    final questionerAnswer = _answers[_questioner.id] as String? ?? '（未作答）';
    final isLastRound = _currentRound >= widget.room.rounds;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('揭晓答案！', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text('题目: $_currentQuestion',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Card(
            color: AppTheme.primary.withAlpha(40),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text('出题者 ${_questioner.name} 的答案：'),
                const SizedBox(height: 8),
                Text(questionerAnswer,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.success, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          ...widget.allPlayers.where((p) => p.id != _questioner.id).map((player) {
            final answer = _answers[player.id] as String? ?? '（未作答）';
            final correct = answer.trim().toLowerCase() ==
                questionerAnswer.trim().toLowerCase();
            return Card(
              child: ListTile(
                leading: Icon(correct ? Icons.check_circle : Icons.cancel,
                    color: correct ? AppTheme.success : AppTheme.error),
                title: Text(player.name),
                subtitle: Text('答案: $answer'),
                trailing: correct
                    ? const Text('+1',
                        style: TextStyle(
                            color: AppTheme.success, fontWeight: FontWeight.bold))
                    : null,
              ),
            );
          }),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text(
                isLastRound ? '$_revealCountdown 秒后查看排行榜' : '$_revealCountdown 秒后下一轮',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 答案输入组件（防止重复提交）
class _AnswerInput extends StatefulWidget {
  final void Function(String) onSubmit;
  const _AnswerInput({required this.onSubmit});

  @override
  State<_AnswerInput> createState() => _AnswerInputState();
}

class _AnswerInputState extends State<_AnswerInput> {
  final _ctrl = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          decoration: const InputDecoration(hintText: '输入你的答案...'),
          maxLength: 30,
          enabled: !_submitted,
          textInputAction: TextInputAction.done,
          onSubmitted: _submitted ? null : (_) => _submit(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitted ? null : _submit,
            child: Text(_submitted ? '✓ 已提交' : '提交答案'),
          ),
        ),
      ],
    );
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitted = true);
    widget.onSubmit(text);
  }
}
