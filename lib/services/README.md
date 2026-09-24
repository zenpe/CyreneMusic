# URL Service 使用指南

## 📡 概述

`UrlService` 是一个单例服务，用于管理应用的所有后端 API 地址。它支持官方源和自定义源切换。

## 🎯 功能特性

- ✅ 官方源/自定义源切换
- ✅ URL 格式验证
- ✅ 自动去除末尾斜杠
- ✅ 状态变化通知
- ✅ 集中管理所有 API 端点

## 📝 基本使用

### 1. 获取当前后端地址

```dart
import 'package:cyrene_music/services/url_service.dart';

// 获取基础 URL
final baseUrl = UrlService().baseUrl;
// 例如: http://127.0.0.1:4055
```

### 2. 获取具体 API 端点

```dart
// 网易云音乐搜索
final searchUrl = UrlService().searchUrl;
// 结果: http://127.0.0.1:4055/search

// Bilibili 播放链接
final biliUrl = UrlService().biliPlayurlUrl;
// 结果: http://127.0.0.1:4055/bili/playurl

// QQ 音乐搜索
final qqSearchUrl = UrlService().qqSearchUrl;
// 结果: http://127.0.0.1:4055/qq/search
```

### 3. 切换后端源

```dart
// 切换到官方源
UrlService().useOfficialSource();

// 切换到自定义源
UrlService().useCustomSource('http://example.com:4055');
```

### 4. 监听 URL 变化

```dart
class MyWidget extends StatefulWidget {
  @override
  void initState() {
    super.initState();
    UrlService().addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    UrlService().removeListener(_onUrlChanged);
    super.dispose();
  }

  void _onUrlChanged() {
    setState(() {
      // URL 已改变，更新 UI
    });
  }
}
```

## 🔌 可用的 API 端点

### Netease (网易云音乐)
```dart
UrlService().searchUrl        // POST /search
UrlService().songUrl          // POST /song
UrlService().toplistsUrl      // GET /toplists
```

### QQ Music
```dart
UrlService().qqSearchUrl      // GET /qq/search
UrlService().qqSongUrl        // GET /qq/song
```

### Kugou (酷狗)
```dart
UrlService().kugouSearchUrl   // GET /kugou/search
UrlService().kugouSongUrl     // GET /kugou/song
```

### Kuwo (酷我)
```dart
UrlService().kuwoSearchUrl    // GET /kuwo/search
UrlService().kuwoSongUrl      // GET /kuwo/song
```

### Bilibili
```dart
UrlService().biliRankingUrl       // GET /bili/ranking
UrlService().biliCidUrl           // GET /bili/cid
UrlService().biliPlayurlUrl       // GET /bili/playurl
UrlService().biliPgcSeasonUrl     // GET /bili/pgc_season
UrlService().biliPgcPlayurlUrl    // GET /bili/pgc_playurl
UrlService().biliDanmakuUrl       // GET /bili/danmaku
UrlService().biliSearchUrl        // GET /bili/search
UrlService().biliCommentsUrl      // GET /bili/comments
UrlService().biliProxyUrl         // GET /bili/proxy
```

### Douyin (抖音)
```dart
UrlService().douyinUrl        // GET /douyin
```

### Version (版本)
```dart
UrlService().versionLatestUrl // GET /version/latest
```

## 🌐 HTTP 请求示例

### 使用 http 包

```dart
import 'package:http/http.dart' as http;
import 'package:cyrene_music/services/url_service.dart';

Future<void> searchSongs(String keyword) async {
  final url = Uri.parse(UrlService().searchUrl);
  
  final response = await http.post(
    url,
    body: {
      'keywords': keyword,
      'limit': '20',
    },
  );
  
  if (response.statusCode == 200) {
    // 处理响应
    print(response.body);
  }
}
```

### 使用 dio 包

```dart
import 'package:dio/dio.dart';
import 'package:cyrene_music/services/url_service.dart';

final dio = Dio();

Future<void> searchSongs(String keyword) async {
  try {
    final response = await dio.post(
      UrlService().searchUrl,
      data: {
        'keywords': keyword,
        'limit': 20,
      },
    );
    
    // 处理响应
    print(response.data);
  } catch (e) {
    print('Error: $e');
  }
}
```

## ⚙️ 在设置页面配置

用户可以在设置页面中：

1. 进入 **设置** → **网络** → **后端源**
2. 选择 **官方源** 或 **自定义源**
3. 如果选择自定义源，输入兼容 Cyrene API 的后端地址
4. 点击 **测试连接** 验证后端是否可用

## 🔒 URL 验证

```dart
// 验证 URL 格式
final isValid = UrlService.isValidUrl('http://example.com:4055');
// true

final isValid2 = UrlService.isValidUrl('invalid-url');
// false
```

## 📋 Cyrene API 兼容要求

自定义后端源必须兼容当前 Cyrene API，提供以下端点：

- ✅ 所有网易云音乐 API
- ✅ 所有 QQ 音乐 API
- ✅ 所有酷狗音乐 API
- ✅ 所有 Bilibili API
- ✅ 抖音解析 API
- ✅ 版本检查 API

## 🔄 最佳实践

1. **始终使用 `UrlService` 获取 URL**
   ```dart
   // ✅ 正确
   final url = UrlService().searchUrl;
   
   // ❌ 错误 - 硬编码
   final url = 'http://localhost:4055/search';
   ```

2. **监听 URL 变化**
   ```dart
   // 如果 UI 依赖当前 URL，记得监听变化
   UrlService().addListener(yourCallback);
   ```

3. **错误处理**
   ```dart
   try {
     final response = await http.get(Uri.parse(UrlService().searchUrl));
     // 处理响应
   } catch (e) {
     // 处理网络错误
   }
   ```

## 🎨 状态查询

```dart
// 检查当前使用的源类型
final isOfficial = UrlService().isUsingOfficialSource;

// 获取源描述
final description = UrlService().getSourceDescription();
// 例如: "官方源 (http://127.0.0.1:4055)"

// 获取自定义源地址
final customUrl = UrlService().customBaseUrl;
```
