import 'dart:convert';
import 'dart:typed_data';

/// 加密工具类 — 与 C# DESCryptoServiceProvider (CBC, IV=key) 完全兼容
class RegisterHelper {
  /// DES 加密 — CBC 模式，IV=密钥前8字节 — 兼容 C# DESCryptoServiceProvider
  static String encrypt(String key, String str) {
    try {
      // Unicode 编码（Little Endian UTF-16）— 兼容 C# Encoding.Unicode
      final keyBytes = _unicodeEncode(key);
      final dataBytes = _unicodeEncode(str);

      // DES 密钥和 IV 均为前 8 字节（兼容 C# CreateEncryptor(key, key)）
      final desKey = keyBytes.sublist(0, 8);
      final iv = keyBytes.sublist(0, 8);

      // PKCS7 填充
      final paddedData = _pkcs7Pad(dataBytes, 8);

      // CBC 模式加密
      final encrypted = _cbcEncrypt(desKey, iv, paddedData);

      return base64Encode(encrypted);
    } catch (e) {
      throw Exception('加密失败: $e');
    }
  }

  /// DES 解密 — CBC 模式，IV=密钥前8字节 — 兼容 C# DESCryptoServiceProvider
  static String decrypt(String key, String str) {
    try {
      // Unicode 编码（Little Endian UTF-16）
      final keyBytes = _unicodeEncode(key);
      final dataBytes = base64Decode(str);

      // DES 密钥和 IV 均为前 8 字节
      final desKey = keyBytes.sublist(0, 8);
      final iv = keyBytes.sublist(0, 8);

      // CBC 模式解密
      final decrypted = _cbcDecrypt(desKey, iv, dataBytes);

      // 移除 PKCS7 填充
      final unpadded = _pkcs7Unpad(decrypted);

      return _unicodeDecode(unpadded);
    } catch (e) {
      throw Exception('解密失败: $e');
    }
  }

  /// 根据机器码生成激活码
  /// 格式：机器码&过期时间&注册时间 → DES CBC 加密 → Base64
  static String createRegisterCode(
      String key, String machineCode, DateTime overTime) {
    // 使用 C# DateTime.ToString("s") 格式: yyyy-MM-ddTHH:mm:ss（无毫秒）
    final finalCode =
        '$machineCode&${_formatSortable(overTime)}&${_formatSortable(DateTime.now())}';
    return encrypt(key, finalCode);
  }

  /// 格式化为 C# DateTime.ToString("s") 兼容格式 (yyyy-MM-ddTHH:mm:ss)
  static String _formatSortable(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:$s';
  }

  /// CBC 模式加密（底层使用 ECB 分组密码）
  static Uint8List _cbcEncrypt(List<int> key, List<int> iv, Uint8List data) {
    final cipher = DESBlockCipher();
    cipher.init(true, key);

    final result = Uint8List(data.length);
    var previous = Uint8List.fromList(iv);

    for (var i = 0; i < data.length; i += 8) {
      final block = data.sublist(i, i + 8);
      // XOR with previous ciphertext (or IV for first block)
      final xored = Uint8List(8);
      for (var j = 0; j < 8; j++) {
        xored[j] = block[j] ^ previous[j];
      }
      final encryptedBlock = cipher.processBlock(xored);
      result.setRange(i, i + 8, encryptedBlock);
      previous = encryptedBlock;
    }
    return result;
  }

  /// CBC 模式解密（底层使用 ECB 分组密码）
  static Uint8List _cbcDecrypt(List<int> key, List<int> iv, Uint8List data) {
    final cipher = DESBlockCipher();
    cipher.init(false, key);

    final result = Uint8List(data.length);
    var previous = Uint8List.fromList(iv);

    for (var i = 0; i < data.length; i += 8) {
      final block = data.sublist(i, i + 8);
      final decryptedBlock = cipher.processBlock(block);
      // XOR with previous ciphertext (or IV for first block)
      for (var j = 0; j < 8; j++) {
        result[i + j] = decryptedBlock[j] ^ previous[j];
      }
      previous = block; // use ciphertext, not plaintext
    }
    return result;
  }

  /// 解密激活码，返回明文内容
  static String decryptRegisterCode(String key, String registerCode) {
    return decrypt(key, registerCode);
  }

  /// Unicode 编码（Little Endian UTF-16）— 兼容 C# Encoding.Unicode
  static Uint8List _unicodeEncode(String str) {
    final bytes = <int>[];
    for (var codeUnit in str.codeUnits) {
      bytes.add(codeUnit & 0xFF);
      bytes.add((codeUnit >> 8) & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }

  /// Unicode 解码（Little Endian UTF-16）
  static String _unicodeDecode(Uint8List bytes) {
    final codeUnits = <int>[];
    for (var i = 0; i < bytes.length; i += 2) {
      if (i + 1 < bytes.length) {
        codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
      }
    }
    return String.fromCharCodes(codeUnits);
  }

  /// PKCS7 填充
  static Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLen);
    padded.setRange(0, data.length, data);
    for (var i = data.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    return padded;
  }

  /// 移除 PKCS7 填充
  static Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLen = data.last;
    if (padLen > 0 && padLen <= 8) {
      // 验证填充是否有效
      var valid = true;
      for (var i = data.length - padLen; i < data.length; i++) {
        if (data[i] != padLen) {
          valid = false;
          break;
        }
      }
      if (valid) {
        return data.sublist(0, data.length - padLen);
      }
    }
    return data;
  }
}

/// DES 块加密器实现
class DESBlockCipher {
  static const List<int> _ip = [
    57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3, 61, 53, 45,
    37,
    29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7, 56, 48, 40, 32, 24, 16, 8,
    0,
    58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4, 62, 54, 46,
    38, 30, 22, 14, 6
  ];

  static const List<int> _fp = [
    39, 7, 47, 15, 55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45,
    13,
    53, 21, 61, 29, 36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59,
    27,
    34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25, 32, 0, 40, 8,
    48, 16, 56, 24
  ];

  // S-Boxes
  static const List<List<List<int>>> _sboxes = [
    // S1
    [
      [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
      [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
      [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
      [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
    ],
    // S2
    [
      [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
      [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
      [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
      [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
    ],
    // S3
    [
      [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
      [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
      [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
      [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
    ],
    // S4
    [
      [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
      [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
      [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
      [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
    ],
    // S5
    [
      [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
      [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
      [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
      [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
    ],
    // S6
    [
      [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
      [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
      [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
      [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
    ],
    // S7
    [
      [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
      [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
      [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
      [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
    ],
    // S8
    [
      [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
      [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
      [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
      [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
    ],
  ];

  static const List<int> _p = [
    15, 6, 19, 20, 28, 11, 27, 16, 0, 14, 22, 25, 4, 17, 30, 9, 1, 7, 23, 13,
    31, 26, 2, 8, 18, 12, 29, 5, 21, 10, 3, 24
  ];

  static const List<int> _e = [
    31, 0, 1, 2, 3, 4, 3, 4, 5, 6, 7, 8, 7, 8, 9, 10, 11, 12, 11, 12, 13, 14,
    15, 16, 15, 16, 17, 18, 19, 20, 19, 20, 21, 22, 23, 24, 23, 24, 25, 26, 27,
    28, 27, 28, 29, 30, 31, 0
  ];

  static const List<int> _pc1 = [
    56, 48, 40, 32, 24, 16, 8, 0, 57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42,
    34, 26, 18, 10, 2, 59, 51, 43, 35, 62, 54, 46, 38, 30, 22, 14, 6, 61, 53,
    45, 37, 29, 21, 13, 5, 60, 52, 44, 36, 28, 20, 12, 4, 27, 19, 11, 3
  ];

  static const List<int> _pc2 = [
    13, 16, 10, 23, 0, 4, 2, 27, 14, 5, 20, 9, 22, 18, 11, 3, 25, 7, 15, 6,
    26, 19, 12, 1, 40, 51, 30, 36, 46, 54, 29, 39, 50, 44, 32, 47, 43, 48, 38,
    55, 33, 52, 45, 41, 49, 35, 28, 31
  ];

  static const List<int> _shifts = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

  late List<List<int>> _subKeys;
  bool _forEncryption = false;

  void init(bool forEncryption, List<int> key) {
    _forEncryption = forEncryption;
    _subKeys = _generateSubKeys(key);
  }

  Uint8List processBlock(Uint8List input) {
    final block = Uint8List(8);
    block.setRange(0, 8, input);

    // 初始置换
    final permuted = _permute(block, _ip, 64);

    // 16 轮 Feistel
    var left = _getInt32(permuted, 0);
    var right = _getInt32(permuted, 4);

    if (_forEncryption) {
      for (var i = 0; i < 16; i++) {
        final newRight = left ^ _feistel(right, _subKeys[i]);
        left = right;
        right = newRight;
      }
    } else {
      for (var i = 15; i >= 0; i--) {
        final newRight = left ^ _feistel(right, _subKeys[i]);
        left = right;
        right = newRight;
      }
    }

    // 交换左右
    final result = Uint8List(8);
    _putInt32(result, 0, right);
    _putInt32(result, 4, left);

    // 最终置换
    return _permute(result, _fp, 64);
  }

  List<List<int>> _generateSubKeys(List<int> key) {
    // PC-1 置换
    final permutedKey = _permute(
      Uint8List.fromList(key),
      _pc1,
      64,
    );

    var c = _getInt28(permutedKey, 0);
    var d = _getInt28(permutedKey, 3);

    final subKeys = <List<int>>[];
    for (var i = 0; i < 16; i++) {
      // 左移
      c = _leftShift28(c, _shifts[i]);
      d = _leftShift28(d, _shifts[i]);

      // 合并并PC-2置换
      final combined = Uint8List(7);
      _putInt28(combined, 0, c);
      _putInt28(combined, 3, d);

      final subKey = _permute(combined, _pc2, 56);
      subKeys.add(subKey.toList());
    }
    return subKeys;
  }

  int _feistel(int right, List<int> subKey) {
    // E扩展置换
    final expanded = _expand(right);

    // 与子密钥异或
    for (var i = 0; i < subKey.length; i++) {
      expanded[i] ^= subKey[i];
    }

    // S-盒替换
    var output = 0;
    for (var i = 0; i < 8; i++) {
      final bitOffset0 = i * 6;
      final bitOffset5 = i * 6 + 5;
      final row = ((expanded[bitOffset0 ~/ 8] >> (7 - (bitOffset0 % 8))) & 1) << 1 |
          ((expanded[bitOffset5 ~/ 8] >> (7 - (bitOffset5 % 8))) & 1);
      var col = 0;
      for (var j = 1; j <= 4; j++) {
        final bitOffset = i * 6 + j;
        col = (col << 1) |
            ((expanded[bitOffset ~/ 8] >> (7 - (bitOffset % 8))) & 1);
      }
      output = (output << 4) | _sboxes[i][row][col];
    }

    // P置换
    final pInput = Uint8List(4);
    _putInt32(pInput, 0, output);
    final pOutput = _permute(pInput, _p, 32);
    return _getInt32(pOutput, 0);
  }

  List<int> _expand(int right) {
    final input = Uint8List(4);
    _putInt32(input, 0, right);
    final output = Uint8List(6);
    for (var i = 0; i < 48; i++) {
      final bitPos = _e[i];
      final bytePos = bitPos ~/ 8;
      final bitOffset = bitPos % 8;
      if (input[bytePos] & (1 << (7 - bitOffset)) != 0) {
        output[i ~/ 8] |= (1 << (7 - (i % 8)));
      }
    }
    return output.toList();
  }

  Uint8List _permute(Uint8List input, List<int> table, int inputBits) {
    final output = Uint8List(table.length ~/ 8);
    for (var i = 0; i < table.length; i++) {
      final bitPos = table[i];
      if (bitPos < inputBits) {
        final bytePos = bitPos ~/ 8;
        final bitOffset = bitPos % 8;
        if (bytePos < input.length &&
            input[bytePos] & (1 << (7 - bitOffset)) != 0) {
          output[i ~/ 8] |= (1 << (7 - (i % 8)));
        }
      }
    }
    return output;
  }

  int _getInt32(Uint8List data, int offset) {
    return data[offset] << 24 |
        data[offset + 1] << 16 |
        data[offset + 2] << 8 |
        data[offset + 3];
  }

  void _putInt32(Uint8List data, int offset, int value) {
    data[offset] = (value >> 24) & 0xFF;
    data[offset + 1] = (value >> 16) & 0xFF;
    data[offset + 2] = (value >> 8) & 0xFF;
    data[offset + 3] = value & 0xFF;
  }

  int _getInt28(Uint8List data, int byteOffset) {
    // 从3字节中提取28位
    var value = 0;
    for (var i = 0; i < 28; i++) {
      final pos = byteOffset * 8 + i;
      final bytePos = pos ~/ 8;
      final bitOffset = pos % 8;
      if (bytePos < data.length &&
          data[bytePos] & (1 << (7 - bitOffset)) != 0) {
        value |= (1 << (27 - i));
      }
    }
    return value;
  }

  void _putInt28(Uint8List data, int byteOffset, int value) {
    for (var i = 0; i < 28; i++) {
      if (value & (1 << (27 - i)) != 0) {
        final pos = byteOffset * 8 + i;
        final bytePos = pos ~/ 8;
        final bitOffset = pos % 8;
        if (bytePos < data.length) {
          data[bytePos] |= (1 << (7 - bitOffset));
        }
      }
    }
  }

  int _leftShift28(int value, int shift) {
    return ((value << shift) | (value >> (28 - shift))) & 0x0FFFFFFF;
  }
}
