# QuickJS Dart 绑定评估

评估日期：2026-11-10。范围：替换当前本地 `flutter_js` 绑定是否能降低维护成本，
同时保留 LX 运行时的执行保护。此次只评估，未更改应用依赖或运行时。

## 决策

当前保留本地绑定与 quickjs-ng 0.18.0。现有方案需要继续维护，但本次核查的第三方
绑定均不能直接接入并保留全部保护；更换包名暂时不能消除维护补丁的责任。

`qjs` 是后续替代的首选候选。它的同步回调、动态 deadline 和不暴露引擎内部标签的
C ABI 符合需求，但需要先解决进入 JS 时的栈顶刷新问题，再验证跨平台构建和 LX
集成。`gg_quickjs` 也有参考价值，不过本轮复现了异常转换绕过中断的问题。

这不是对现有绑定永远更稳定的保证；结论只针对当前版本、项目需求和已取得的证据。

## 替代必须保留的契约

- JS 同步调用同一 worker 内的 Dart 工具，AES/RSA 返回普通值，不能变成 Promise。
- 初始化与普通执行使用不同期限；期限还受调用者剩余预算约束。
- 一次外层操作的嵌套调用、结果/异常转换、Promise 队列共享单调时钟 deadline。
- 有内存和栈限制。Dart isolate 可能更换 OS 线程，外层入口需要刷新 JS 栈顶，
  重入回调不能反复重置该边界。
- 显式释放上下文、回调和数值句柄；活动音源与候选音源能够独立存在。
- 保留现有串行调度、HTTP 桥接、成功后保留脚本状态、取消后重建以及候选激活语义。
- 原生构建可固定版本并核查来源，平台支持必须落实到构建产物。

任何候选依然需要原生桥接。C、C++、Rust 和 native assets 是实现/分发方式，
本身不是稳定性的证明。音源 HTTP 520、服务器返回失效链接也不会因换绑定自动修好。

## 版本比较

包版本来自本轮获取的 pub.dev 元数据与发布归档，不只依据 README。

| 包 | 发布版本 / 引擎 | 核查结果 | 本项目判断 |
| --- | --- | --- | --- |
| 当前本地绑定 | flutter_js 衍生 / NG 0.18.0 | 已有动态执行预算、外层栈顶刷新及应用集成回归 | 当前保留 |
| [qjs](https://pub.dev/packages/qjs/versions/0.2.3) | 0.2.3 / NG 0.17.0 | 同步回调、动态 deadline；Windows 探针通过；桥接没有栈顶刷新 | 首选后续候选，不能原样替换 |
| [gg_quickjs](https://pub.dev/packages/gg_quickjs/versions/0.1.0) | 0.1.0 / NG 0.17.0 | 同步回调和通常的执行限制有效；异常 getter 可绕过中断并挂住 | 当前不能直接替换 |
| [dart_qjs](https://pub.dev/packages/dart_qjs/versions/1.0.6) | 1.0.6 / NG 0.15.0 | CPU 时钟计时、每次微任务重置预算；构建时克隆 GitHub | 会退化当前保护和构建确定性 |
| [quickjs_engine](https://pub.dev/packages/quickjs_engine/versions/0.1.7) | 0.1.7 / NG 0.14.0 | 仍保留旧内部标签常量；桥接未安装执行中断处理器 | 不作为本次替代 |
| [fjs](https://pub.dev/packages/fjs/versions/3.3.2) | 3.3.2 / Rust rquickjs | 功能更广；现成 Dart 回调桥返回 Promise，引入 Rust/FRB 体系 | 与现有同步工具契约不匹配，迁移收益不足 |

另外检查了 `quickjs`、`quickjs_dart`、`quickjs_runtime`、`flutter_qjs_next`、`jsf`。
它们使用原版 QuickJS或属于旧绑定，不能视为 quickjs-ng 绑定的直接升级。
其中 `flutter_qjs_next`、`jsf` 使用较新的原版 QuickJS，不能笼统说它们都已停止维护。

## 实证与边界

### gg_quickjs 0.1.0

低层 `JsRuntime.registerFunction` 确实支持同步 Dart 回调。本轮用项目实际
`LxScriptUtils` 验证 AES 返回普通值，`isPromise=false`。跨 isolate 封装的异步
回调方式不应与低层接口混为一谈。

配置 100ms deadline、64MiB 内存、256KiB JS 栈后：普通死循环、结果 getter
死循环、无限 Promise 链均在约 100ms 中断，递归触发栈溢出异常，之后能继续执行
`1 + 1`。

但下面的异常在同样配置下超过 15 秒未返回，最后由外部监督进程终止：

```js
throw { get value() { while (true) {} } }
```

发布源码 `src/gg_quickjs.c` 中，`describe` 在序列化异常时设置
`describing=true`、`unlimited=true`；`interrupt_handler` 在 describing 状态直接
放行，而对象编码会调用 `JS_GetProperty` 执行 getter。拒绝原因的描述也使用了
相同模式。异常处理因此可能拖住整个解析 worker，Dart 自身的 Future 超时不能
打断这个同步原生调用。

此外，公开 options 固定于创建阶段，没有发现可直接实现当前分阶段预算的公开
timeout setter。其 NG 0.17 编译/OOM 策略也需单独评估，本轮没有证明任一候选
能安全承受所有 OOM 情况。

### qjs 0.2.3

在单独 Dart 项目中固定依赖版本，通过包自带 hook 下载并校验 Windows x64
预编译资产。此次没有验证 hook 的 MSVC 源码回退构建。

实测结果：

| 探针 | 结果 |
| --- | --- |
| 同步调用现有 AES 工具 | 普通返回值，与另一候选的密文一致 |
| `while (true)` | 约 102ms 中断 |
| `JSON.stringify` 访问无限 getter | 约 100ms 中断 |
| 抛出带无限 `message` getter 的对象，再格式化异常 | 约 100ms 返回兜底异常文本 |
| 无限 Promise 链，显式 drain | 约 101ms 中断 |
| 无限递归 | 栈溢出异常，进程正常存活 |
| 每次失败后清除 deadline，再计算 `1 + 1` | 通过 |
| 20 次 await 后的简单求值及释放 | 通过 |

`setDeadline` 会持续约束后续调用及微任务，直到显式清除或替换，适合现有预算模型。
同步 host callback 使用 `NativeCallable.isolateLocal`，可以留在现有 worker 中。

主要缺口来自源码核查：`src/qjs_dart.c` 的入口没有调用 `JS_UpdateStackTop`；
引擎仅在创建 runtime 时初始化栈顶，`JS_SetMaxStackSize` 也不会刷新栈顶。
因此 isolate 更换 OS 线程后，栈限制可能仍相对于旧线程地址计算，可能误报溢出或
失去预期保护。上述简单 await 探针没有证明 OS 线程确实发生切换，也未复现此问题；
这是有明确源码依据、尚未实测复现的集成风险。

构建 hook 优先下载有 SHA-256 的预编译资产，失败则编译附带源码。回退路径的
编译参数未区分 MSVC，也未显式启用其 C11 atomics；下载响应和响应体没有完整的
总时间限制。它们需要核实，不能因 Windows 预编译探针成功就认为离线构建及所有
目标都已通过。

### 其他候选的源码依据

- `dart_qjs/src/ffi.cpp` 的 interrupt 使用 `clock()`；`js_begin_call` 重置
  起点，执行每个 pending job 前再次调用。Dart 侧循环排空任务，所以逐个短任务
  可以绕开整批时间上限。`hook/build.dart` 在包目录删除/克隆/清理引擎目录，
  构建依赖 GitHub，多个目标同时构建还存在共享目录竞争风险，后者未复现。
- `quickjs_engine` 发布包确实附带原生源码，但 Dart 的 `JSTag` 仍包含旧的
  `BIG_INT=-10`，附带 NG 头文件则是 `-9`。未在应用桥接中找到用于执行预算的
  `JS_SetInterruptHandler`，引擎标准库中的相关调用不能替代桥接保护。
- `fjs` 并非完全没有同步求值 API；问题是现成的 host bridge 类型为
  `Fn(JsValue) -> DartFnFuture<JsResult>`，通过 `Promise::wrap_future` 返回 JS。
  未发现可直接替代当前同步 Dart 加密回调的公开接口。

## 实施含义

本轮不发起第二次绑定迁移。当前升级可以继续沿已有代码验证和交付，不需要等待
绑定选型。后续若采用 `qjs`，先解决外层入口/重入的栈边界，再保留现有
`LxScriptEngine` 接口完成适配，避免同时改调度、HTTP 和脚本状态模型。
只有替代包能覆盖这些契约、跨平台构建及现有 LX 回归后，才真正有机会降低维护成本。

重新评估的触发条件：现有桥接出现难以修复的原生稳定性问题，或 `qjs` 补齐栈顶
刷新且能在目标平台强制从源码构建。后者仍需通过上述契约、内存耗尽、回调释放
生命周期及 Android ABI / 16 KiB 页对齐检查；目前没有完成这些候选验证。

评估材料保存在本地 `.tmp/quickjs-bindings-review/`，包括固定版本源码、元数据、
隔离探针与日志。该目录是临时材料，未作为生产依赖。实际执行仅覆盖 Windows；
没有 Android 真机、Linux、Apple 的候选运行验证，也没有重跑完整应用测试。
