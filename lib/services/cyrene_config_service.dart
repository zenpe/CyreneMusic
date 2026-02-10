import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';

/// Cyrene 配置文件模型
class CyreneConfig {
  final String name;
  final String url;
  final String apiKey;

  CyreneConfig({
    required this.name,
    required this.url,
    required this.apiKey,
  });

  factory CyreneConfig.fromJson(Map<String, dynamic> json) {
    return CyreneConfig(
      name: json['name'] as String? ?? 'OmniParse',
      url: json['url'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'apiKey': apiKey,
  };
}

/// Cyrene 配置文件服务
/// 
/// 用于解析和解密 .cyrene 配置文件
class CyreneConfigService {
  // 单例模式
  static final CyreneConfigService _instance = CyreneConfigService._internal();
  factory CyreneConfigService() => _instance;
  CyreneConfigService._internal();

  // 加密密钥（32字节 = 256位）- 必须与后端密钥一致
  static final Uint8List _encryptionKey = Uint8List.fromList(
    'CyreneMusic2024SecretKey12345678'.codeUnits,
  );

  // 魔数标识
  static const List<int> _magicNumber = [0x43, 0x59, 0x52, 0x4E]; // "CYRN"

  // 支持的版本
  static const int _supportedVersion = 1;

  /// 解密 .cyrene 配置文件
  /// 
  /// [data] - .cyrene 文件的原始字节数据
  /// 
  /// 返回解密后的配置，如果解密失败则返回 null
  CyreneConfig? decrypt(Uint8List data) {
    try {
      // 验证文件格式
      if (!_validateFormat(data)) {
        return null;
      }

      // 解析文件结构
      // 魔数(4) + 版本(1) + IV(12) + 加密数据 + AuthTag(16)
      final iv = data.sublist(5, 17);
      final authTag = data.sublist(data.length - 16);
      final encryptedData = data.sublist(17, data.length - 16);

      // 使用 AES-256-GCM 解密
      final decryptedBytes = _aesGcmDecrypt(encryptedData, iv, authTag);
      if (decryptedBytes == null) {
        return null;
      }

      // 解析 JSON
      final jsonString = utf8.decode(decryptedBytes);
      final json = jsonDecode(jsonString) as Map<String, dynamic>;

      return CyreneConfig.fromJson(json);
    } catch (e) {
      print('CyreneConfigService: 解密失败 - $e');
      return null;
    }
  }

  /// 验证文件格式
  bool _validateFormat(Uint8List data) {
    // 最小文件大小: 魔数(4) + 版本(1) + IV(12) + 最小数据(1) + AuthTag(16) = 34 字节
    if (data.length < 34) {
      print('CyreneConfigService: 文件太小');
      return false;
    }

    // 检查魔数
    for (int i = 0; i < 4; i++) {
      if (data[i] != _magicNumber[i]) {
        print('CyreneConfigService: 魔数不匹配');
        return false;
      }
    }

    // 检查版本
    final version = data[4];
    if (version != _supportedVersion) {
      print('CyreneConfigService: 不支持的版本 $version');
      return false;
    }

    return true;
  }

  /// AES-256-GCM 解密
  Uint8List? _aesGcmDecrypt(Uint8List ciphertext, Uint8List iv, Uint8List authTag) {
    try {
      // 将 authTag 附加到密文末尾（PointyCastle 的 GCM 实现需要这样）
      final ciphertextWithTag = Uint8List(ciphertext.length + authTag.length);
      ciphertextWithTag.setAll(0, ciphertext);
      ciphertextWithTag.setAll(ciphertext.length, authTag);

      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(_encryptionKey),
        128, // authTag 长度（128 位 = 16 字节）
        iv,
        Uint8List(0), // 无额外认证数据
      );

      cipher.init(false, params); // false 表示解密

      final decrypted = Uint8List(cipher.getOutputSize(ciphertextWithTag.length));
      final len = cipher.processBytes(ciphertextWithTag, 0, ciphertextWithTag.length, decrypted, 0);
      cipher.doFinal(decrypted, len);

      // 去除填充的零字节
      int actualLength = decrypted.length;
      while (actualLength > 0 && decrypted[actualLength - 1] == 0) {
        actualLength--;
      }

      return decrypted.sublist(0, actualLength);
    } catch (e) {
      print('CyreneConfigService: AES-GCM 解密失败 - $e');
      return null;
    }
  }

  /// 检查是否为有效的 .cyrene 文件（仅检查格式，不解密）
  bool isValidCyreneFile(Uint8List data) {
    return _validateFormat(data);
  }
}
