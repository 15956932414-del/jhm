import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// 加密工具类 — DESede(K1=K2=K3) 等价单DES，兼容 C# DESCryptoServiceProvider
class RegisterHelper {
  /// DES 加密 — CBC 模式，IV=key — 兼容 C# CreateEncryptor(key, key)
  static String encrypt(String key, String str) {
    final keyBytes = _unicodeEncode(key);
    final dataBytes = _unicodeEncode(str);

    final desKey = _padKey8(keyBytes);
    // DESede key = 8字节key重复3次 → K1=K2=K3 等价单DES
    final desedeKey = Uint8List.fromList([...desKey, ...desKey, ...desKey]);
    final iv = desKey;

    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(DESedeEngine()),
    );
    cipher.init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(desedeKey), Uint8List.fromList(iv)),
        null,
      ),
    );

    final encrypted = cipher.process(Uint8List.fromList(dataBytes));
    return base64Encode(encrypted);
  }

  /// DES 解密 — CBC 模式，IV=key
  static String decrypt(String key, String str) {
    final keyBytes = _unicodeEncode(key);
    final dataBytes = base64Decode(str);

    final desKey = _padKey8(keyBytes);
    final desedeKey = Uint8List.fromList([...desKey, ...desKey, ...desKey]);
    final iv = desKey;

    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(DESedeEngine()),
    );
    cipher.init(
      false,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(desedeKey), Uint8List.fromList(iv)),
        null,
      ),
    );

    final decrypted = cipher.process(Uint8List.fromList(dataBytes));
    return _unicodeDecode(decrypted);
  }

  /// 根据机器码生成激活码
  static String createRegisterCode(
      String key, String machineCode, DateTime overTime) {
    final finalCode =
        '$machineCode&${_formatSortable(overTime)}&${_formatSortable(DateTime.now())}';
    return encrypt(key, finalCode);
  }

  /// 解密激活码
  static String decryptRegisterCode(String key, String registerCode) {
    return decrypt(key, registerCode);
  }

  // ---- 内部 ----

  /// 取前8字节，不足则补零
  static Uint8List _padKey8(List<int> bytes) {
    final key = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      key[i] = i < bytes.length ? bytes[i] : 0;
    }
    return key;
  }

  /// C# DateTime.ToString("s") 格式: yyyy-MM-ddTHH:mm:ss
  static String _formatSortable(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:$s';
  }

  /// Unicode 编码 (Little Endian UTF-16) — 兼容 C# Encoding.Unicode
  static Uint8List _unicodeEncode(String str) {
    final bytes = <int>[];
    for (var codeUnit in str.codeUnits) {
      bytes.add(codeUnit & 0xFF);
      bytes.add((codeUnit >> 8) & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }

  /// Unicode 解码 (Little Endian UTF-16)
  static String _unicodeDecode(Uint8List bytes) {
    final codeUnits = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(codeUnits);
  }
}
