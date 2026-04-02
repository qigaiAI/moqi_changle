class AppConfig {
  // 游戏配置
  static const int defaultRounds = 3;
  static const int defaultDrawingTime = 80; // 秒
  static const int answerTimeLimit = 30; // 秒
  static const int minPlayers = 2;
  static const int maxPlayers = 10;

  // 重连配置
  static const int maxReconnectAttempts = 3;
  static const int reconnectWindowSeconds = 600; // 10分钟

  // 历史记录最多保存场数
  static const int maxHistoryRecords = 10;

  // 画板批量发送间隔（毫秒）
  static const int drawBatchIntervalMs = 50;

  // 判断平板的最小短边宽度（dp）
  static const double tabletBreakpoint = 600.0;
}
