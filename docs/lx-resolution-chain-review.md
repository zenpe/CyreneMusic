# LX 解析链路对照审查

审查日期：2026-11-16。对照目录：`F:/lx-music-desktop`，本地版本 2.12.6，HEAD `323e4bac`。此次只审查并做隔离复现，没有修改 LX 或客户端生产代码。

## 1. 源码中的主链路

```text
搜索 / 榜单 / 歌单生成完整歌曲信息
  → 按当前脚本能力与歌曲音质选择 quality
  → 查询客户端 URL 缓存
  → toOldMusicInfo 保留 LX 脚本协议字段
  → 当前用户脚本的 musicUrl 处理器
  → IPC → Electron 隔离环境 → lx.request → Needle HTTP
  → 脚本返回 URL → 保存 URL 缓存 → audio.src
```

证据位置：

- `F:/lx-music-desktop/src/renderer/utils/musicSdk/tx/musicSearch.js:106`：QQ 搜索结果保留 `interval`、`songId`、`songmid`、`strMediaMid`、`albumId`、`albumMid`、`types`、`_types`。
- `F:/lx-music-desktop/src/common/utils/tools.ts:58`：`toOldMusicInfo` 将歌曲信息转换成脚本参数，继续保留上述字段。QQ 的 `songmid` 是 MID，`songId` 是数字 ID，`strMediaMid` 是媒体 ID，三者分开保存。
- `F:/lx-music-desktop/src/renderer/core/music/online.ts:41`：先读 URL 缓存；刷新时绕过缓存。原歌曲和最终匹配的其他平台歌曲可以分别保存 URL。
- `F:/lx-music-desktop/src/renderer/core/music/utils.ts:291`：调用 `musicSdk[source].getMusicUrl(toOldMusicInfo(musicInfo), targetQuality)`。
- `F:/lx-music-desktop/src/renderer/core/useApp/useInitUserApi.ts:41`：发给当前脚本的结构为 `{source, action:'musicUrl', info:{type, musicInfo}}`。
- `F:/lx-music-desktop/src/main/modules/userApi/renderer/preload.js:68`：调用当前脚本回调，只检查返回值是有效长度的 HTTP(S) URL，并未统一确认歌曲内容或完整时长。
- `F:/lx-music-desktop/src/renderer/plugins/player/index.ts:395`：最终设置 `audio.src`，由 Chromium 音频引擎加载。此入口没有按原歌曲平台附加 QQ Referer 的逻辑。

## 2. “自动换源”的实际含义

`F:/lx-music-desktop/src/renderer/core/music/utils.ts:291` 捕获原平台解析失败后，调用 `getOtherSource`。后者交给 `musicSdk.findMusic`，搜索其他平台的同曲。

`F:/lx-music-desktop/src/renderer/utils/musicSdk/index.js:75` 的匹配逻辑使用歌名、歌手、专辑、时长和版本关键词。时长已知时，候选一般需满足相差不超过 5 秒；缺少时长时会放宽这一条件。匹配有多级规则，不能理解成严格的歌曲身份认证。

`F:/lx-music-desktop/src/renderer/core/music/utils.ts:237` 再依次尝试候选平台：

1. 跳过已尝试平台。
2. 跳过当前脚本不支持的平台与候选没有的目标音质。
3. 继续调用当前选中脚本，只更换歌曲的平台及对应歌曲信息。
4. 候选失败继续尝试；限流错误停止轮询。

因此，这条播放恢复路径切换的是其他平台的歌曲候选，不能理解成轮换多个已导入的 JS 脚本。脚本内部自己的多接口并发和备用线路，是另一层机制。

## 3. 与本客户端的明确差异

| 项目 | LX 本地源码 | Cyrene 当前实现 | 影响 |
|---|---|---|---|
| 歌曲时长 | 保留 `interval` 并传入脚本 | `Track` 无时长；`buildLxMusicInfo` 不传时长 | 脚本的短片段检查、同曲匹配退化 |
| QQ 标识 | 分别保留 MID、数字歌曲 ID、媒体 MID | 主要提供 `songmid` | 依赖其他标识的脚本分支可能失败；不能伪造这些 ID |
| 专辑和音质信息 | 保留专辑 ID、MID、`types`、`_types` | 脚本参数明显更少 | 部分脚本无法获得所需上下文 |
| 解析失败恢复 | 客户端搜索其他平台同曲，用当前脚本继续尝试 | 此次失败链路主要依赖活动脚本自身的备用接口 | 用户看到的成功率可能不同 |
| 脚本 HTTP | Needle；支持 body、form、formData；回调提供 raw、bytes、body | Dart HTTP 桥；当前缺少同等完整的 formData / raw 回调适配 | 是进一步兼容审查项，尚未证明造成此次同地址返回 |

Cyrene 的对应位置是 `lib/models/track.dart:57`、`lib/services/lx_music_info.dart:6`、`lib/services/music_service.dart:641`、`lib/services/lx_http_bridge.dart` 和 `lib/services/lx_script_engine.dart`。

## 4. 本次短音频的隔离复现

使用下载留存的原推荐脚本 2.1.0，不改校验逻辑。HTTP 模拟返回同一份 HEAD 证据：`audio/mpeg`、171072 字节。

- 当前 Cyrene 歌曲信息：没有时长，脚本最低长度阈值为 128000 字节，因此接受。
- 从 LX 源码提取 `toOldMusicInfo`，输入带 `interval:'03:32'` 的歌曲信息：阈值变成 `212 × 3000 = 636000` 字节，因此拒绝。
- 之前的真实 QuickJS + HTTP 回环测试同样复现：当前生产元数据构造不传时长时接受；在新运行时补入 212 秒后拒绝。该测试中三首歌的实际出站 ID 与回传 URL 未串用。

证据文件：

- `.tmp/windows-recommendation-check/lx-metadata-contract-comparison.json`
- `.tmp/windows-recommendation-check/quickjs-wire-audit.json`
- `.tmp/windows-recommendation-check/gitcode-original-url-comparison.json`
- `.tmp/windows-recommendation-check/gitcode-cached-payload-audit.json`

这证明缺少时长可以让同一脚本产生不同决策。如果 LX 当时使用相同脚本且歌曲包含正常时长，这份短音频会被脚本拒绝，外层也就有机会进入其他平台候选。这解释了一个可复现的差异机制，不能替代用户当时 LX 的实际请求日志。

## 5. 超时与播放器恢复

- 脚本 HTTP：`preload.js:209` 使用 Needle 的 `response_timeout`，脚本指定的正值最多 60 秒，未指定默认 60 秒。这不是整个解析一定等待 60 秒。
- 用户脚本请求外层：`rendererEvent/rendererEvent.ts:137` 是 20 秒。
- 搜索其他平台候选：`core/music/utils.ts:56` 是 15 秒。
- 播放器加载超时：启用自动跳过错误歌曲时，`usePlayEvent.ts:19` 是 25 秒，先刷新 URL，再按状态跳下一首。
- 引擎错误：`usePlayEvent.ts:84` 对符合条件的错误刷新 URL，最多两次。
- 当前原推荐脚本自身仍设置约 3 秒单请求及 6 秒总预算。LX 外层较长不会覆盖脚本自己设置的期限。

所查的 URL 解析入口和播放器恢复路径，没有统一的“跨歌曲完整文件哈希判重”或“所有格式完整时长核验”。LX 能成功不能推出它具有这种检测能力。

## 6. 后续修改顺序

先补齐歌曲原始元数据到 LX 参数的兼容链路：从真实数据源保留时长和平台标识，经过模型、存储、播放与检测样例传递到脚本。未知字段保持未知，不能把 MID 复制成媒体 ID，也不能使用播放器刚读到的错误 7 秒时长充当目标歌曲时长。

随后做同脚本、同歌曲、同音质的差异回归，记录实际传入字段与胜出平台。当前脚本 GET 校验修复稿也仍依赖元数据，单独发布脚本不能填补上游丢失的时长。

后台检测的时长与重复短音频检查作为独立防线。跨平台自动换源属于新增播放行为，应在元数据兼容修复验证后单独设计，不能与这次基础兼容修改一起扩大播放状态机变更。
