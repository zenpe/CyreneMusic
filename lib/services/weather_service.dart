import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api/api_client.dart';

class WeatherService {
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  String? _cachedText;
  DateTime? _cachedAt;
  Duration _ttl = const Duration(minutes: 10);
  static const String _amapKey = 'ea2bc1b1ae9a513cf4e8d910623d26ea';

  static const Map<String, String> _provinceCapital = {
    '北京': '北京',
    '天津': '天津',
    '上海': '上海',
    '重庆': '重庆',
    '河北': '石家庄',
    '山西': '太原',
    '辽宁': '沈阳',
    '吉林': '长春',
    '黑龙江': '哈尔滨',
    '江苏': '南京',
    '浙江': '杭州',
    '安徽': '合肥',
    '福建': '福州',
    '江西': '南昌',
    '山东': '济南',
    '河南': '郑州',
    '湖北': '武汉',
    '湖南': '长沙',
    '广东': '广州',
    '海南': '海口',
    '四川': '成都',
    '贵州': '贵阳',
    '云南': '昆明',
    '陕西': '西安',
    '甘肃': '兰州',
    '青海': '西宁',
    '台湾': '台北',
    '内蒙古': '呼和浩特',
    '广西': '南宁',
    '西藏': '拉萨',
    '宁夏': '银川',
    '新疆': '乌鲁木齐',
    '香港': '香港',
    '澳门': '澳门',
  };

  Future<String?> fetchWeatherText() async {
    if (_cachedText != null && _cachedAt != null) {
      final now = DateTime.now();
      if (now.difference(_cachedAt!) < _ttl) return _cachedText;
    }

    final ipResult = await ApiClient().getJson(
      'https://drive-backend.cyrene.ltd/api/userip',
      auth: false,
      timeout: const Duration(seconds: 8),
    );
    if (!ipResult.ok) return null;
    final ipData = ipResult.data as Map<String, dynamic>;
    final loc = (ipData['location'] as Map<String, dynamic>?) ?? const {};
    final province = (loc['province'] ?? '').toString();
    String city = (loc['city'] ?? '').toString();
    if (city.isEmpty) {
      city = _provinceCapital[province] ?? province;
    }
    if (city.isEmpty) return null;

    // 优先：使用地理编码(geo)通过 省+市 解析城市级 adcode
    String? adcode = await _resolveAdcodeByGeo(province: province, city: city);
    // 回退：使用行政区(division)查询
    adcode ??= await _resolveAdcodeByDistrict(province: province, city: city);

    if (adcode == null || adcode.isEmpty) {
      // 无法可靠解析到城市级 adcode，则不展示，避免误命中"西安区"等同名区县
      return null;
    }

    final weatherResult = await ApiClient().getJson(
      '/weather',
      queryParameters: {'cityid': adcode},
      auth: false,
    );
    if (!weatherResult.ok) return null;
    final data = weatherResult.data as Map<String, dynamic>;
    if ((data['status'] as num?)?.toInt() != 200) return null;
    final d = data['data'] as Map<String, dynamic>?;
    final text = d?['text']?.toString();
    if (text != null && text.isNotEmpty) {
      _cachedText = text;
      _cachedAt = DateTime.now();
    }
    return text;
  }

  Future<String?> _resolveAdcodeByGeo({required String province, required String city}) async {
    try {
      final address = province.isNotEmpty ? '$province$city' : city;
      final url = Uri.parse('https://restapi.amap.com/v3/geocode/geo?address=${Uri.encodeQueryComponent(address)}&key=$_amapKey');
      final r = await http.get(url).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final m = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      if ((m['status']?.toString() ?? '0') != '1') return null;
      final gs = (m['geocodes'] as List?) ?? const [];
      if (gs.isEmpty) return null;

      String targetCity = _normalizeName(city);
      String targetProv = _normalizeName(province);

      String? best;
      for (final it in gs) {
        final g = it as Map<String, dynamic>;
        final gProv = _normalizeName((g['province'] ?? '').toString());
        final gCity = _normalizeName((g['city'] ?? '').toString());
        final level = (g['level'] ?? '').toString();
        final ad = (g['adcode'] ?? '').toString();

        // 规则：优先 level=city，且省匹配，并且 adcode 为城市级（..00 且不为 ..0000）
        final adIsCity = ad.endsWith('00') && !ad.endsWith('0000');
        final provOk = targetProv.isEmpty || gProv == targetProv;
        final cityOk = gCity.isEmpty ? (gProv == targetCity) : (gCity == targetCity);
        if (level == 'city' && provOk && cityOk && adIsCity) {
          return ad;
        }
        // 次优：level=city + 省匹配
        if (best == null && level == 'city' && provOk && adIsCity) {
          best = ad;
        }
      }

      return best;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveAdcodeByDistrict({required String province, required String city}) async {
    try {
      final target = _normalizeName(city);
      String? provAdcode;
      String provPrefix = '';

      // 1) 先以省为关键字，获取其下属城市列表，在 city 级别中精确匹配
      if (province.isNotEmpty) {
        final provUrl = Uri.parse('https://restapi.amap.com/v3/config/district?keywords=${Uri.encodeQueryComponent(province)}&level=province&subdistrict=1&key=$_amapKey');
        final pr = await http.get(provUrl).timeout(const Duration(seconds: 8));
        if (pr.statusCode == 200) {
          final pm = json.decode(utf8.decode(pr.bodyBytes)) as Map<String, dynamic>;
          if ((pm['status']?.toString() ?? '0') == '1') {
            final pds = (pm['districts'] as List?) ?? const [];
            if (pds.isNotEmpty) {
              final p0 = pds.first as Map<String, dynamic>;
              provAdcode = (p0['adcode'] ?? '').toString();
              if (provAdcode != null && provAdcode.length >= 2) {
                provPrefix = provAdcode.substring(0, 2);
              }
              final children = (p0['districts'] as List?) ?? const [];
              for (final it in children) {
                final m = it as Map<String, dynamic>;
                final level = (m['level'] ?? '').toString();
                if (level != 'city') continue; // 只接受地级市
                final name = (m['name'] ?? '').toString();
                if (_normalizeName(name) == target || name == city) {
                  final ad = (m['adcode'] ?? '').toString();
                  if (ad.isNotEmpty) return ad;
                }
              }
            }
          }
        }
      }

      // 2) 回退：限定城市级别搜索（省+市）
      {
        final kw = (province.isNotEmpty ? '$province$city' : city);
        final url = Uri.parse('https://restapi.amap.com/v3/config/district?keywords=${Uri.encodeQueryComponent(kw)}&level=city&subdistrict=0&key=$_amapKey');
        final r = await http.get(url).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final m = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          if ((m['status']?.toString() ?? '0') == '1') {
            final ds = (m['districts'] as List?) ?? const [];
            for (final it in ds) {
              final mm = it as Map<String, dynamic>;
              final level = (mm['level'] ?? '').toString();
              if (level != 'city') continue;
              final name = (mm['name'] ?? '').toString();
              final ad = (mm['adcode'] ?? '').toString();
              final okName = (_normalizeName(name) == target || name == city);
              final okProv = provPrefix.isEmpty ? true : (ad.startsWith(provPrefix));
              if (okName && okProv && ad.isNotEmpty) return ad;
            }
            // 尝试加上“市”后再次精确匹配
            final altTarget = _normalizeName('$city市');
            for (final it in ds) {
              final mm = it as Map<String, dynamic>;
              final level = (mm['level'] ?? '').toString();
              if (level != 'city') continue;
              final name = (mm['name'] ?? '').toString();
              final ad = (mm['adcode'] ?? '').toString();
              if (_normalizeName(name) == altTarget && (provPrefix.isEmpty || ad.startsWith(provPrefix))) {
                if (ad.isNotEmpty) return ad;
              }
            }
          }
        }
      }

      // 3) 最后回退：仅以城市名限定到 city 级别
      {
        final url = Uri.parse('https://restapi.amap.com/v3/config/district?keywords=${Uri.encodeQueryComponent(city)}&level=city&subdistrict=0&key=$_amapKey');
        final r = await http.get(url).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final m = json.decode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
          if ((m['status']?.toString() ?? '0') == '1') {
            final ds = (m['districts'] as List?) ?? const [];
            for (final it in ds) {
              final mm = it as Map<String, dynamic>;
              final level = (mm['level'] ?? '').toString();
              if (level != 'city') continue;
              final name = (mm['name'] ?? '').toString();
              final ad = (mm['adcode'] ?? '').toString();
              final okName = (_normalizeName(name) == target || name == city);
              final okProv = provPrefix.isEmpty ? true : (ad.startsWith(provPrefix));
              if (okName && okProv && ad.isNotEmpty) return ad;
            }
            // 次优回退：若有省前缀匹配的城市，返回第一个
            if (provPrefix.isNotEmpty) {
              for (final it in ds) {
                final mm = it as Map<String, dynamic>;
                final level = (mm['level'] ?? '').toString();
                if (level != 'city') continue;
                final ad = (mm['adcode'] ?? '').toString();
                if (ad.startsWith(provPrefix) && ad.isNotEmpty) return ad;
              }
            }
          }
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  String _normalizeName(String s) {
    var x = s.trim();
    if (x.endsWith('市')) x = x.substring(0, x.length - 1);
    if (x.endsWith('地区')) x = x.substring(0, x.length - 2);
    if (x.endsWith('自治州')) x = x.substring(0, x.length - 3);
    if (x.endsWith('特别行政区')) x = x.substring(0, x.length - 5);
    if (x.endsWith('盟')) x = x.substring(0, x.length - 1);
    if (x.endsWith('县')) x = x.substring(0, x.length - 1);
    if (x.endsWith('区')) x = x.substring(0, x.length - 1);
    return x;
  }
}
