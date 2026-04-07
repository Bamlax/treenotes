import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'webdav_settings_page.dart';
import 'changelog_page.dart'; 
import 'about_page.dart'; 

class SettingsPage extends StatefulWidget {
  final Future<void> Function() onSync;

  const SettingsPage({super.key, required this.onSync});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _showYamlInThumbnail = false;
  bool _defaultIsPreview = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showYamlInThumbnail = prefs.getBool('show_yaml_in_thumbnail') ?? false;
      _defaultIsPreview = prefs.getBool('default_is_preview') ?? false;
    });
  }

  Future<void> _updateYamlSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_yaml_in_thumbnail', value);
    setState(() => _showYamlInThumbnail = value);
  }

  Future<void> _updatePreviewSetting(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('default_is_preview', value);
    setState(() => _defaultIsPreview = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        children: [
          // ================= 新增：样式设置 =================
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text('偏好设置', style: TextStyle(color: Colors.lightGreen, fontWeight: FontWeight.bold)),
          ),
          SwitchListTile(
            title: const Text('默认开启阅读视图'),
            subtitle: const Text('打开笔记时直接进入预览模式'),
            value: _defaultIsPreview,
            activeColor: Colors.lightGreen,
            onChanged: _updatePreviewSetting,
          ),
          SwitchListTile(
            title: const Text('在首页显示自定义属性'),
            subtitle: const Text('列表缩略图前会附带 YAML 属性'),
            value: _showYamlInThumbnail,
            activeColor: Colors.lightGreen,
            onChanged: _updateYamlSetting,
          ),
          const Divider(),
          // =================================================

          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text('同步', style: TextStyle(color: Colors.lightGreen, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync, color: Colors.lightGreen),
            title: const Text('WebDAV 同步', style: TextStyle(fontSize: 16)),
            subtitle: const Text('配置云端网盘及执行同步'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => WebDavSettingsPage(onSync: widget.onSync)));
            },
          ),
          const Divider(),
          
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Text('其他', style: TextStyle(color: Colors.lightGreen, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.update, color: Colors.green),
            title: const Text('更新日志', style: TextStyle(fontSize: 16)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangelogPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.amber),
            title: const Text('关于开发者', style: TextStyle(fontSize: 16)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AboutPage()));
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Center(
              child: Text(
                'TreeNotes v1.0.0',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          )
        ],
      ),
    );
  }
}