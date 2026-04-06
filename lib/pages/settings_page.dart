import 'package:flutter/material.dart';
import 'webdav_settings_page.dart';
import 'changelog_page.dart'; 
import 'about_page.dart'; 

class SettingsPage extends StatelessWidget {
  final Future<void> Function() onSync;

  const SettingsPage({super.key, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        children: [
          ListTile(
            // ======= 改为浅绿色 =======
            leading: const Icon(Icons.cloud_sync, color: Colors.lightGreen),
            title: const Text('WebDAV 同步', style: TextStyle(fontSize: 16)),
            subtitle: const Text('配置云端网盘及执行同步'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => WebDavSettingsPage(onSync: onSync)),
              );
            },
          ),
          const Divider(height: 1),
          
          ListTile(
            leading: const Icon(Icons.update, color: Colors.green),
            title: const Text('更新日志', style: TextStyle(fontSize: 16)),
            subtitle: const Text('查看历史版本更新信息'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChangelogPage()),
              );
            },
          ),
          const Divider(height: 1),

          ListTile(
            leading: const Icon(Icons.person, color: Colors.amber),
            title: const Text('关于开发者', style: TextStyle(fontSize: 16)),
            subtitle: const Text('Bamlax'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
              );
            },
          ),
          const Divider(height: 1),

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