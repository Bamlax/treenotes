class ChangelogEntry {
  final String version;
  final String date;
  final List<String> changes;

  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  }); // 去掉了 isLatest
}

// 专门记录所有版本更新信息的列表
// 把最新的版本写在列表最前面，程序会自动将第一个元素标记为“最新”
const List<ChangelogEntry> changelogData = [
  ChangelogEntry(
    version: 'v0.2.0',
    date: '2026-04-06',
    changes: [
      '新增同步链接测试功能。',
      '新增文件自定义位置存放。',
      '修复无法同步的bug。',
    ],
  ),
  ChangelogEntry(
    version: 'v0.1.0',
    date: '2026-04-06',
    changes: [
      '初始版本发布。',
      '支持 Markdown 笔记与文件夹的创建、修改和删除。',
      '增加扁平化的 YAML 自定义属性编辑功能。',
      '支持基于坚果云等 WebDAV 协议的双向同步。',
      '增加基于系统时间和 YAML 时间的多维度排序。',
      '加入笔记字符统计与详细信息查看。',
    ],
  ),
];