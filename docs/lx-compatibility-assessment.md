# LX 基础兼容改进：实施与验证

日期：2026-11-16。对照本地 LX Desktop 2.12.6 的 toOldMusicInfo、脚本宿主及其锁定的 Needle 版本。范围为 CyreneMusic 和 cyapi-go 的脚本输入与 HTTP 契约；自动跨平台同曲换源另行评估。

## 已实现

### 平台元数据

- 增加可选 lxMetadata，保留 QQ 数字歌曲 ID、媒体 MID、专辑 MID，以及真实可得的专辑 ID、封面与歌曲音质体积。不同 ID 不互相代替，不根据脚本能力虚构歌曲音质。
- 搜索、详情、歌单、收藏、历史、会话与 JSON 转换保留这些字段。QQ 旧记录在已有受限的播放资料补全流程中补充标识；普通列表不为这些标识额外逐首请求详情。
- 脚本参数传递 interval、img、typeUrl、types、_types 和平台专属字段；QQ songmid、songId、strMediaMid 保持各自含义。音质体积采用 LX 的格式，例如 4.00 MiB。
- URL 缓存和在途请求额外比较脚本输入的元数据快照。资料变化后不再复用旧输入结果；歌曲身份、收藏键与音频文件缓存键保持原有语义。
- 后端复用 source_ids_json 保存元数据，公开 API 分开返回 sourceIds 和 lxMetadata。目录更新与远程快照按字段合并，旧客户端或不完整数据不会擦除已保存的标识。
- 后台样例新增/刷新使用同一元数据映射；检测器标识为 goja-probe-v4。旧样例须通过现有管理界面的刷新动作补齐，旧检测报告不会自动变成新报告。

### HTTP、Buffer 与 multipart

- 客户端 QuickJS 和后台 Goja 的回调增加 raw、bytes，保留已有解析后的 body 和 response.body === body 行为。
- 按 LX 锁定的 Needle 实现，raw 与 bytes 表示解压、字符集转换前的响应字节；gzip 的 body 单独解压和解析。原始与解压后的内容均受预算限制。这里保留现有解析后的 body，不照搬 LX preload 中对压缩原始字节再次转字符串的特殊行为。
- 提供基于 Uint8Array 的 Buffer 兼容子集：常用字符串编码、切片、整数读取、相等比较与 JSON。raw 延迟恢复为 Buffer；不宣称实现完整 Node Buffer API。
- 支持常见标量 multipart 和内存文件字节；不允许借此读取本地文件路径。沿用请求取消、响应上限与运行时预算。
- http_parser 从已有间接依赖改为直接声明，未新增 Node 服务或运行时依赖。

## 保留的架构边界

- 播放调度、恢复次数、总时间预算、错误分类与引擎生命周期继续使用既有实现；没有照搬 LX 的 25 秒定时器或增加重试次数。
- 脚本内部缓存仍归脚本管理，不为清除它而普遍重建运行时。
- 同曲跨平台自动换源未引入。已有用户手动换源的数据映射保留元数据。
- 加密工具继续使用已有实现；没有新增音频解密器或原生依赖。

## 验证

- 客户端最终回归：183 项通过，包括实际 QuickJS DLL 与生产 HTTP 桥、gzip 原始字节、multipart、元数据持久化、缓存/在途输入变化、时长与播放恢复。
- 元数据对照 fixture 由本地 LX 官方 toOldMusicInfo 实际执行生成；客户端与后台使用相同输入和期望值。
- 后端 go test ./... 通过，覆盖 Goja 实际 HTTP 回调、样例映射、QQ 元数据与 SQLite 部分更新保留。
- PostgreSQL 合并路径已实现，但没有测试数据库 DSN，条件测试未执行；不能将 SQLite 通过等同于 PostgreSQL 实测通过。
- 静态分析无 error/warning，仅保留 proxy_service.dart 已有一条 info。Windows Release 构建成功，独立包位于 dist/windows-lx-contract-review/；使用包内 QuickJS DLL 的补充契约回归 16 项通过。构建后已恢复默认 CMake 输出配置。
- 测试与构建日志位于 .tmp/lx-contract-implementation/。

## 部署及实际故障的界限

本次元数据扩展不新增数据库迁移；先前时长改动的 0004_song_duration.sql 仍须按后端原有迁移流程执行。客户端和后端需要各自更新才能获得完整契约。仅更新客户端不能补出旧后端从未返回的字段。

HYW 的 .mgg/.mflac 和非标准文件头是加密资源的重要线索。元数据兼容修复不负责解密，也不能修复上游 502、额度不足或过期链接。单次未知格式不能据此判整个脚本失效；应保留样例、平台、资源证据及检测器版本。

本次测试使用本地受控数据及 HTTP 服务，没有用生产凭证重新验证 HYW，也没有据此改变线上推荐或发布版本。
