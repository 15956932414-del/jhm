import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/key_config.dart';
import '../helpers/register_helper.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  KeyConfig _keyConfig = KeyConfig(keys: [], selectedKeyName: '');
  final TextEditingController _deviceCodeController = TextEditingController();
  final TextEditingController _newKeyNameController = TextEditingController();
  final TextEditingController _newKeyValueController = TextEditingController();
  DateTime? _expireDate;
  String _activationCode = '';
  String? _verifyMachineCode;
  String? _verifyOverTime;
  String? _verifyRegisterTime;
  String? _verifyMatchResult;
  bool _verifyPanelVisible = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    _keyConfig = await KeyConfig.loadFromStorage();
    setState(() {});
  }

  String _getCurrentKey() {
    return _keyConfig.getCurrentKeyValue();
  }

  Future<void> _saveKey() async {
    final name = _newKeyNameController.text.trim();
    final value = _newKeyValueController.text.trim();

    if (name.isEmpty) {
      _showMessage('请输入密钥名称');
      return;
    }
    if (value.isEmpty) {
      _showMessage('请输入密钥值');
      return;
    }

    final existing = _keyConfig.keys.where((k) => k.name == name).firstOrNull;
    if (existing != null) {
      final confirm = await _showConfirm('密钥 "$name" 已存在，是否覆盖？');
      if (!confirm) return;
      existing.value = value;
    } else {
      _keyConfig.keys.add(KeyItem(name: name, value: value));
    }

    _keyConfig.selectedKeyName = name;
    await _keyConfig.saveToStorage();

    _newKeyNameController.clear();
    _newKeyValueController.clear();

    setState(() {});
    _showMessage('密钥 "$name" 已保存');
  }

  Future<void> _deleteKey() async {
    final selected = _keyConfig.keys
        .where((k) => k.name == _keyConfig.selectedKeyName)
        .firstOrNull;
    if (selected == null) {
      _showMessage('请先选择要删除的密钥');
      return;
    }
    if (_keyConfig.keys.length <= 1) {
      _showMessage('至少保留一个密钥');
      return;
    }

    final confirm = await _showConfirm('确定要删除密钥 "${selected.name}" 吗？');
    if (!confirm) return;

    _keyConfig.keys.remove(selected);
    if (_keyConfig.selectedKeyName == selected.name) {
      _keyConfig.selectedKeyName = _keyConfig.keys.first.name;
    }
    await _keyConfig.saveToStorage();
    setState(() {});
  }

  Future<void> _generateCode() async {
    final key = _getCurrentKey();
    if (key.isEmpty) {
      _showMessage('请先选择或添加加密密钥');
      return;
    }

    final deviceCode = _deviceCodeController.text.trim();
    if (deviceCode.isEmpty) {
      _showMessage('请输入设备码');
      return;
    }

    if (deviceCode.length != 24) {
      final confirm = await _showConfirm('设备码长度似乎不正确（应为24位数字），是否继续？');
      if (!confirm) return;
    }

    if (_expireDate == null) {
      _showMessage('请选择到期时间');
      return;
    }

    try {
      final overTime = DateTime(
        _expireDate!.year,
        _expireDate!.month,
        _expireDate!.day,
        23,
        59,
        59,
      );

      final activationCode =
          RegisterHelper.createRegisterCode(key, deviceCode, overTime);
      setState(() {
        _activationCode = activationCode;
      });

      _verifyCode(activationCode, deviceCode);
    } catch (e) {
      _showMessage('生成失败：$e');
    }
  }

  void _verifyCode(String activationCode, String expectedMachineCode) {
    final key = _getCurrentKey();
    try {
      final decrypted = RegisterHelper.decryptRegisterCode(key, activationCode);
      final parts = decrypted.split('&');

      setState(() {
        _verifyPanelVisible = true;
        if (parts.length == 3) {
          _verifyMachineCode = '设备码: ${parts[0]}';
          _verifyOverTime = '到期时间: ${parts[1]}';
          _verifyRegisterTime = '注册时间: ${parts[2]}';

          if (parts[0] == expectedMachineCode) {
            _verifyMatchResult = '✓ 设备码匹配，激活码有效';
          } else {
            _verifyMatchResult = '✗ 设备码不匹配！请检查输入的设备码';
          }
        } else {
          _verifyMatchResult = '解密成功但格式异常（分段数=${parts.length}）：$decrypted';
        }
      });
    } catch (e) {
      setState(() {
        _verifyPanelVisible = true;
        _verifyMatchResult = '✗ 解密失败：$e';
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expireDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null) {
      setState(() {
        _expireDate = picked;
      });
    }
  }

  void _copyToClipboard() {
    if (_activationCode.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _activationCode));
      _showMessage('激活码已复制到剪贴板');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _showConfirm(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('激活码生成器'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            const Text(
              '激活码生成器',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '输入设备码和到期时间，生成激活码',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // 密钥选择
            const Text(
              '加密密钥',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _keyConfig.selectedKeyName.isNotEmpty
                        ? _keyConfig.selectedKeyName
                        : null,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: _keyConfig.keys.map((key) {
                      return DropdownMenuItem(
                        value: key.name,
                        child: Text(key.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _keyConfig.selectedKeyName = value;
                        });
                        _keyConfig.saveToStorage();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _deleteKey,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4D4F),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('删除'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newKeyNameController,
                    decoration: const InputDecoration(
                      hintText: '密钥名称',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _newKeyValueController,
                    decoration: const InputDecoration(
                      hintText: '密钥值',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saveKey,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1677FF),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 设备码
            const Text(
              '设备码',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _deviceCodeController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),

            // 到期时间
            const Text(
              '到期时间',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                child: Text(
                  _expireDate != null
                      ? DateFormat('yyyy-MM-dd').format(_expireDate!)
                      : '选择日期',
                  style: TextStyle(
                    color: _expireDate != null ? Colors.black : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // 生成按钮
            ElevatedButton(
              onPressed: _generateCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1677FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('生成激活码'),
            ),
            const SizedBox(height: 20),

            // 结果
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '生成的激活码',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0958D9),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF91CAFF)),
                    ),
                    child: Text(
                      _activationCode.isEmpty ? '等待生成...' : _activationCode,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          if (_activationCode.isNotEmpty) {
                            _verifyCode(
                              _activationCode,
                              _deviceCodeController.text.trim(),
                            );
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF52C41A),
                        ),
                        child: const Text('验证解密'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _copyToClipboard,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1677FF),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('复制激活码'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 验证结果
            if (_verifyPanelVisible) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '解密验证结果',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD48806),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_verifyMachineCode != null)
                      Text(
                        _verifyMachineCode!,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF595959)),
                      ),
                    if (_verifyOverTime != null)
                      Text(
                        _verifyOverTime!,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF595959)),
                      ),
                    if (_verifyRegisterTime != null)
                      Text(
                        _verifyRegisterTime!,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF595959)),
                      ),
                    if (_verifyMatchResult != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _verifyMatchResult!,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _verifyMatchResult!.startsWith('✓')
                              ? const Color(0xFF52C41A)
                              : const Color(0xFFFF4D4F),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _deviceCodeController.dispose();
    _newKeyNameController.dispose();
    _newKeyValueController.dispose();
    super.dispose();
  }
}
