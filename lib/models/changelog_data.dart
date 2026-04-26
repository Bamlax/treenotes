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
    version: 'v0.7.0',
    date: '2026-04-26',
    changes: [
      '新增文件夹改名功能',
      '新增双列缩略图显示',
      '优化打开时的文件显示逻辑',
    ],
  ),
  ChangelogEntry(
    version: 'v0.6.1',
    date: '2026-04-11',
    changes: [
      '优化文件夹的打开动画',
      '修复文件改名时同步旧文件的bug',
      '修复文件改名读取失败的bug',
    ],
  ),
    ChangelogEntry(
    version: 'v0.6.0',
    date: '2026-04-10',
    changes: [
      '新增双链功能',
      '新增目录内容的提示',
      '修复文件夹动画不触发的问题',
      '更正设置底部版本号的调用逻辑',
    ],
  ),
    ChangelogEntry(
    version: 'v0.5.0',
    date: '2026-04-08',
    changes: [
      '新增文件夹打开动画',
      '新增搜索功能',
      '优化同步逻辑',
      '美化UI',
      '修复新建文件时按回车报错的bug',
    ],
  ),
    ChangelogEntry(
    version: 'v0.4.0',
    date: '2026-04-07',
    changes: [
      '新增删除同步功能',
      '新增markdown代办可被完成',
      '新增同步中的提示',
      '新增默认显示编辑或者阅读视图',
      '新增是否显示自定义yaml',
      '修复无法换行的问题',
      '优化待办事项的对齐问题',
    ],
  ),
    ChangelogEntry(
    version: 'v0.3.0',
    date: '2026-04-06',
    changes: [
      '新增工具栏功能',
      '新增markdown代办可被完成',
      '优化阅读和编辑界面视图',
      '优化新建文件和文件夹逻辑',
      '优化修改文件名逻辑',
    ],
  ),
  ChangelogEntry(
    version: 'v0.2.0',
    date: '2026-04-06',
    changes: [
      '新增同步链接测试功能',
      '新增文件自定义位置存放',
      '修复无法同步的bug',
    ],
  ),
  ChangelogEntry(
    version: 'v0.1.0',
    date: '2026-04-06',
    changes: [
      '初始版本发布',
      '支持 Markdown 笔记与文件夹的创建、修改和删除',
      '增加扁平化的 YAML 自定义属性编辑功能',
      '支持基于坚果云等 WebDAV 协议的双向同步',
      '增加基于系统时间和 YAML 时间的多维度排序',
      '加入笔记字符统计与详细信息查看',
    ],
  ),
];