import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart'; // 引入插件
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
  
  // ================= 新增：存放版本号的变量 =================
  String _appVersion = ''; 

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAppVersion(); // 初始化时加载版本信息
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _showYamlInThumbnail = prefs.getBool('show_yaml_in_thumbnail') ?? false;
      _defaultIsPreview = prefs.getBool('default_is_preview') ?? false;
    });
  }

  // ================= 新增：异步获取应用版本号 =================
  Future<void> _loadAppVersion() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = packageInfo.version; 
        // 注：如果你想连构建号一起显示，可以写成 '${packageInfo.version}+${packageInfo.buildNumber}'
      });
    } catch (e) {
      setState(() {
        _appVersion = '1.0.0'; // 如果获取失败，给个默认值兜底
      });
    }
  }
  // =======================================================

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

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0),
            child: Center(
              child: Text(
                // ================= 动态显示版本号 =================
                _appVersion.isEmpty ? '加载中...' : 'TreeNotes v$_appVersion',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          )
        ],
      ),
    );
  }
}