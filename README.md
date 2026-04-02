# 默契挑战 App

多人在线默契游戏，支持 Android 和 iOS。

## 功能特性

- 🎮 默契问答模式：测试玩家之间的了解程度
- 🎨 你画我猜模式：实时画板同步
- 👥 2-10 人在线联机
- 📱 手机和平板完美适配

## 技术栈

- Flutter 3.35.5
- Riverpod 状态管理
- Supabase 实时后端

## 配置 Supabase

1. 在 Supabase 中执行 `../supabase_schema.sql` 创建数据库表
2. 配置已写入 `lib/config/supabase_config.dart`

当前配置：
- URL: http://122.51.83.184:8000

## 运行项目

```bash
flutter pub get
flutter run
```

## 打包

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

## 开发进度

### ✅ 阶段 0：环境准备（已完成）
- [x] 项目初始化
- [x] Supabase 配置
- [x] 基础页面

### ⏳ 待完成
- 阶段 2：房间系统完善
- 阶段 3：默契问答模式
- 阶段 4：你画我猜模式
