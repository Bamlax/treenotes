import 'package:flutter/material.dart';
import '../models/changelog_data.dart'; // 引入专门记录更新数据的文件

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更新日志'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: changelogData.length,
        itemBuilder: (context, index) {
          final entry = changelogData[index];
          return _buildLogItem(
            version: entry.version,
            date: entry.date,
            changes: entry.changes,
            isLatest: index == 0, // ====== 核心逻辑：第一个项自动标记为“最新” ======
          );
        },
      ),
    );
  }

  Widget _buildLogItem({
    required String version,
    required String date,
    required List<String> changes,
    bool isLatest = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                version,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.lightGreen),
              ),
              const SizedBox(width: 8),
              if (isLatest)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
                  child: const Text('最新', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              const Spacer(),
              Text(date, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          ...changes.map((change) => Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    Expanded(child: Text(change, style: const TextStyle(fontSize: 15, height: 1.5))),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    );
  }
}