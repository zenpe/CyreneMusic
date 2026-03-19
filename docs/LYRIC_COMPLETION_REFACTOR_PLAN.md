# 歌词补全重构方案

> 本文档只解决一件事：把歌词从“播放副作用”改成“独立子系统”。

## 1. 目标

要同时满足 4 个目标：

- 切歌主链路不等待歌词
- 歌词补全失败不影响播放
- 歌词一旦补全成功，当前界面一定刷新
- 歌词有独立缓存，不再依赖音频缓存是否完整

当前结构最大的问题不是“歌词接口慢”，而是：

- 歌词补全挂在 `PlaybackService` 的缓存补全副作用里
- 歌词缓存依附于音频缓存元数据
- UI 还在用 `lyrics.isEmpty` 猜测状态

这会直接导致：

- 歌曲已经播了，但歌词状态不稳定
- 音频缓存命中，歌词仍可能重复请求
- 状态遗漏时，界面会一直停在“歌词加载中”

## 2. 重构原则

歌词系统后续必须遵守 5 条原则：

- `PlaybackService` 不负责歌词请求细节
- `LyricService` 独立维护歌词状态
- 歌词缓存与音频缓存解耦
- UI 只消费显式歌词状态，不做推断
- 所有异步歌词结果都必须校验当前 track/token

## 3. 目标结构

建议拆成 3 层。

### 3.1 `PlaybackService`

职责只保留：

- 完成切歌事务
- `commitPresentation` 后发起歌词请求
- 消费当前歌词快照做悬浮歌词或页面展示

明确禁止：

- 在 `PlaybackService` 内自己维护歌词补全状态机
- 在 `PlaybackService` 内直接决定歌词缓存读写策略
- 在歌词补全链路里复用“歌曲缓存补全”语义

### 3.2 `LyricService`

这是新的一等公民服务，负责：

- 当前歌词状态
- 当前歌词快照
- 请求去重
- token / track 校验
- 内存缓存
- 本地缓存
- 后台远端补全
- 结果通知

建议接口：

```dart
class LyricService extends ChangeNotifier {
  LyricSnapshot? get currentSnapshot;
  LyricLoadState get currentState;

  Future<void> requestLyrics({
    required Track track,
    required SongDetail? song,
    required int playbackToken,
    required String reason,
  });

  Future<void> prefetchLyrics(Track track, {String? title, String? artist});

  void bindCurrentTrack({
    required Track track,
    required int playbackToken,
    SongDetail? song,
  });

  void clearCurrent();
}
```

### 3.3 `LyricRepository`

只负责“歌词从哪来、往哪存”。

职责：

- 读内存缓存
- 读本地歌词缓存
- 请求远端歌词接口
- 写本地歌词缓存

不要让 repository 持有播放器状态。

## 4. 状态模型

歌词状态不能继续靠 `lyrics.isEmpty` 推断。

统一状态：

```dart
enum LyricLoadState {
  idle,
  loading,
  ready,
  empty,
  failed,
}
```

并且要有统一快照对象：

```dart
class LyricSnapshot {
  final String trackKey;
  final int playbackToken;
  final LyricLoadState state;
  final List<LyricLine> lines;
  final String lyric;
  final String tlyric;
  final String yrc;
  final String ytlrc;
  final String qrc;
  final String qrcTrans;
  final DateTime updatedAt;
  final String? error;
}
```

UI 规则必须固定：

- `loading` -> 显示“歌词加载中”
- `ready` -> 渲染歌词
- `empty` -> 显示“暂无歌词”
- `failed` -> 显示“歌词加载失败”

## 5. 缓存设计

## 5.1 当前问题

现在歌词跟在 `CacheMetadata` 里，属于“附带缓存”。

优点：

- 已缓存歌曲可以顺带带出歌词

缺点更大：

- 音频缓存失败，歌词也无法单独落盘
- 旧缓存只要歌词字段不完整，就会反复补全
- 没法单独做歌词 TTL、统计、清理

## 5.2 目标方案

新增独立歌词缓存层。

建议目录：

```text
lyrics_cache/
  lyric_index.json
  netease_3351217533_standard.json
  qq_001YKMzC4aXMN9_standard.json
```

单条缓存结构建议：

```json
{
  "trackKey": "netease_3351217533",
  "quality": "standard",
  "source": "netease",
  "title": "xxx",
  "artist": "xxx",
  "lyric": "...",
  "tlyric": "...",
  "yrc": "...",
  "ytlrc": "...",
  "qrc": "...",
  "qrcTrans": "...",
  "hasContent": true,
  "fetchedAt": "2026-03-19T17:18:16.000Z",
  "expiresAt": "2026-03-26T17:18:16.000Z"
}
```

读取优先级固定为：

1. 当前内存缓存
2. 本地歌词缓存
3. 音频缓存元数据里的歌词字段
4. 远端歌词接口

注意：

- 音频缓存元数据以后只能是“冗余副本”，不再是主来源

## 6. 请求生命周期

切歌后歌词流程应固定为：

1. `PlaybackService.commitPresentation`
2. `LyricService.bindCurrentTrack(...)`
3. `LyricService.requestLyrics(...)`
4. 命中内存缓存则立即 `ready`
5. 命中本地歌词缓存则立即 `ready`
6. 命中音频缓存歌词字段则立即 `ready`，并异步回填独立歌词缓存
7. 全部未命中才请求远端
8. 远端成功则：
   - 解析
   - 写独立歌词缓存
   - 更新内存缓存
   - 若 token 仍匹配当前歌曲，则发布 `ready`
9. 远端返回空歌词则发布 `empty`
10. 请求失败则发布 `failed`

## 7. token 设计

歌词 token 必须和播放 token 绑定，但不能完全复用播放事务内部状态。

建议：

- `PlaybackService` 生成 `activePlaybackToken`
- `LyricService` 保存当前 `trackKey + playbackToken`
- 任意歌词异步返回时，先校验：
  - `trackKey` 是否仍是当前歌曲
  - `playbackToken` 是否仍是当前展示 token

旧结果一律丢弃，不允许覆盖当前歌词。

## 8. 预取设计

歌词也要预取，但必须独立预取。

触发建议：

- 当前歌曲稳定播放 3 到 5 秒
- 对下一首调用 `prefetchLyrics(nextTrack)`

预取规则：

- 只拉歌词，不拉播放 URL
- 只写缓存，不更新当前 UI
- 命中已有独立歌词缓存则跳过

目标是：

- 用户切到下一首时，歌词优先从本地命中

## 9. UI 改造要求

所有歌词页统一改成消费 `LyricService`，不要再各自解析一遍 `currentSong`。

包括但不限于：

- 全屏桌面歌词页
- 全屏移动端歌词页
- 流体云歌词页
- 沉浸式歌词页
- 桌面悬浮歌词
- Android 悬浮歌词

统一模式：

- 页面只关心 `LyricSnapshot`
- 页面不直接决定“是否请求歌词”
- 页面不直接根据 `SongDetail` 推断 `empty/loading`

## 10. 日志与观测

歌词链路必须有独立日志前缀，例如 `[LyricService]`。

至少保留：

- `request start`
- `memory hit`
- `disk hit`
- `cache-metadata hit`
- `remote fetch start`
- `remote fetch success`
- `remote fetch empty`
- `remote fetch failed`
- `stale discard`
- `cache write success`
- `cache write failed`

这样才能区分到底是：

- 缓存没命中
- 接口慢
- 结果为空
- token 丢弃
- 还是缓存写失败

## 11. 落地实施顺序

建议按 4 个包做，不要乱序。

### 包 1：抽出歌词状态模型

目标：

- 新增 `LyricLoadState`
- 新增 `LyricSnapshot`
- UI 统一消费显式状态

改动范围：

- `lib/services/player_service.dart`
- 新增 `lib/services/lyric/lyric_snapshot.dart`
- 各歌词页面组件

验收：

- 不再因为 `lyrics.isEmpty` 误显示“暂无歌词”

### 包 2：新增 `LyricService`

目标：

- 把当前歌词请求与状态从 `PlaybackService` 移出

改动范围：

- 新增 `lib/services/lyric/lyric_service.dart`
- `PlaybackService` 只保留调用入口

验收：

- `PlaybackService` 内不再直接维护歌词补全状态

### 包 3：新增独立歌词缓存

目标：

- 歌词持久化不再依赖音频缓存

改动范围：

- 新增 `lib/services/lyric/lyric_repository.dart`
- 新增 `lib/services/lyric/lyric_cache_service.dart`

验收：

- 即使音频缓存失败，下次进入同一首歌仍可本地命中歌词

### 包 4：补全预取与收口旧逻辑

目标：

- 支持下一首歌词预取
- 删除 `PlaybackService` 里遗留的歌词补全分支

验收：

- 切歌后歌词多数情况直接命中本地
- 旧的 `_bgUpdateCachedMetadata()` 不再承担歌词系统职责

## 12. 明确不推荐的方向

这轮不要优先做这些：

- 继续在 `PlaybackService` 里补更多歌词状态分支
- 继续把歌词字段塞进更多播放缓存逻辑
- 继续靠 UI 加更多 loading 文案遮掩状态错位

这些只能继续打补丁，不会把结构做对。

## 13. 结论

歌词补全的最终正确形态应该是：

- 播放链路独立
- 歌词链路独立
- 缓存链路独立
- UI 只读显式歌词状态

也就是说，歌词不应该再是“播放完成后的顺带处理”，而应该成为一个独立、可观测、可缓存、可预取的子系统。
