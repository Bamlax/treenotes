import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WebDavSettingsPage extends StatefulWidget {
  final Future<void> Function() onSync;

  const WebDavSettingsPage({super.key, required this.onSync});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _pwdCtrl = TextEditingController();
  
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlCtrl.text = prefs.getString('dav_url') ?? '';
      _userCtrl.text = prefs.getString('dav_user') ?? '';
      _pwdCtrl.text = prefs.getString('dav_pwd') ?? '';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dav_url', _urlCtrl.text.trim());
    await prefs.setString('dav_user', _userCtrl.text.trim());
    await prefs.setString('dav_pwd', _pwdCtrl.text.trim());
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存')),
      );
    }
  }

  Future<void> _performSync() async {
    await _saveSettings();
    setState(() => _isSyncing = true);
    await widget.onSync();
    if (mounted) setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV 同步'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('请填写支持 WebDAV 的网盘信息', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: '服务器地址 (例如: https://dav.jianguoyun.com/dav/)', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: '账号', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: '密码 / 应用密码', border: OutlineInputBorder())),
          const SizedBox(height: 24),
          
          ElevatedButton(
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.grey.shade200, foregroundColor: Colors.black87),
            child: const Text('仅保存配置', style: TextStyle(fontSize: 16)),
          ),
          
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          
          const Text(
            '手动同步',
            // ======= 改为浅绿色 =======
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.lightGreen),
          ),
          const SizedBox(height: 8),
          const Text('点击下方按钮，将执行本地与云端的双向同步。你也可以在首页下拉进行同步。', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          
          ElevatedButton.icon(
            onPressed: _isSyncing ? null : _performSync,
            icon: _isSyncing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            label: Text(_isSyncing ? '正在同步...' : '立即同步', style: const TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              // ======= 改为浅绿色 =======
              backgroundColor: Colors.lightGreen,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}