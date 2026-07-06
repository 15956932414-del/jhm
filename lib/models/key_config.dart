import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 单个密钥项
class KeyItem {
  String name;
  String value;

  KeyItem({required this.name, required this.value});

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  factory KeyItem.fromJson(Map<String, dynamic> json) {
    return KeyItem(name: json['name'] ?? '', value: json['value'] ?? '');
  }

  @override
  String toString() => name;
}

/// 密钥配置管理
class KeyConfig {
  List<KeyItem> keys;
  String selectedKeyName;

  KeyConfig({required this.keys, required this.selectedKeyName});

  /// 从本地存储加载配置
  static Future<KeyConfig> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('key_config');

      if (jsonStr != null) {
        final Map<String, dynamic> json = jsonDecode(jsonStr);
        final keys = (json['keys'] as List)
            .map((item) => KeyItem.fromJson(item))
            .toList();
        if (keys.isNotEmpty) {
          return KeyConfig(
            keys: keys,
            selectedKeyName: json['selectedKeyName'] ?? '',
          );
        }
      }
    } catch (e) {
      // 加载失败时使用默认配置
    }

    // 首次运行：创建默认配置
    final defaultConfig = KeyConfig(
      keys: [KeyItem(name: 'gbox', value: 'gbox')],
      selectedKeyName: 'gbox',
    );
    await defaultConfig.saveToStorage();
    return defaultConfig;
  }

  /// 保存配置到本地存储
  Future<void> saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      'keys': keys.map((k) => k.toJson()).toList(),
      'selectedKeyName': selectedKeyName,
    };
    await prefs.setString('key_config', jsonEncode(json));
  }

  /// 获取当前选中的密钥值
  String getCurrentKeyValue() {
    final selected = keys.where((k) => k.name == selectedKeyName).firstOrNull;
    return selected?.value ?? '';
  }
}
