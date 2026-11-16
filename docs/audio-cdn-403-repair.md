# GitCode 音频 403 本地修复记录

## 已确认的原因

歌曲 `qq_001sV0Ef3nASZb` 的脚本返回 GitCode CDN 地址。对同一个新地址保持 UA、Range 一致时，不带 QQ Referer 的 GET 返回 206，附加 `Referer: https://y.qq.com/` 返回 403。HEAD 返回 200 不能证明 GET 可读。

本结论仅解释这类资源下载失败。脚本停服、鉴权、人机验证和无播放权限仍应按各自证据排查。

## 修改边界

- 根据实际音频域名生成平台请求头。第三方 CDN 不附加 QQ/酷狗 Referer、Origin；官方音频域名保留对应请求头。
- Windows 本地代理、后台缓存和音频下载在每次重定向后重新计算请求头。保留 Range、超时、取消和重试预算。
- 刷新仍返回被拒绝的同一地址时，最终失败日志保留原始 HTTP 状态；新选曲清除旧错误证据。
- `scripts/audio_sources/qingliu.js` 为独立的 2.1.1 修复稿：GET 请求前 4096 字节，响应上限 64 KiB；校验实际字节及基本格式标记，缓存地址每次复用前重新检查。206 的完整长度从 Content-Range 获取。
- HTTP 桥新增显式选项 `audioResource: true`，仅用于音频 GET/HEAD 的逐跳请求头策略；`encoding: null` 返回字节数组；`maxResponseBytes` 只能缩小原有 8 MiB 上限。未设置这些选项的普通脚本请求沿用原路径。
- `F:/cyapi-go/internal/sourcecheck` 的资源 GET 使用相同域名策略与 UA，保留原有 SSRF、流量预算和重定向检查。检测器标识改为 `goja-probe-v3`，区分旧报告。

有限字节校验只能提供可读取和基本格式证据，不能证明解码成功、歌曲正确或完整时长。服务端忽略 Range 并超过读取上限时，该脚本候选会被拒绝。

## 验证与使用

1. 定向 Flutter 回归覆盖请求头、代理/缓存重定向、下载、桥接取消与限额、选曲恢复和原始 403 保留。
2. `node --test scripts/tests/qingliu.test.cjs`：脚本逻辑的离线回归；Node 仅为开发测试工具，不是应用或服务运行依赖。
3. 后端 `go test ./internal/sourcecheck`：资源请求策略、读取预算及实际 Goja worker 回归。
4. 本地 Windows Release 构建后，由用户使用原推荐源和原 QQ 歌曲验证。当前线上脚本即可验证客户端 Referer 修复。

本修复纳入客户端 v1.3.20 与后端 v0.0.17 的发布范围，不改线上推荐脚本。独立脚本修复稿使用了本次新增的桥接能力，**不能直接向旧客户端发布**；应在对应客户端及后端版本验收后，再单独安排脚本发布。已有检测报告不等于新策略的结果，部署后需重新检测。
