import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      debugPrint('无法打开链接: $urlString');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于开发者'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.lightBlue.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.computer, size: 64, color: Colors.lightGreen),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Bamlax',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(
            child: Text(
              'TreeNotes 核心开发者',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
          const SizedBox(height: 40),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('GitHub'),
            subtitle: const Text('Bamlax'),
            trailing: const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
            onTap: () => _launchUrl('https://github.com/Bamlax'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('联系邮箱'),
            subtitle: const Text('Bamlax@163.com'),
            trailing: const Icon(Icons.open_in_new, size: 18, color: Colors.grey),
            onTap: () => _launchUrl('mailto:Bamlax@163.com?subject=关于 TreeNotes 的反馈'),
          ),
        ],
      ),
    );
  }
}