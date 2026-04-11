import 'dart:io';
import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:file_picker/file_picker.dart';

import '../models/sort_method.dart';
import '../utils/note_util.dart';
import 'note_editor_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _rootPath = '';
  String _currentPath = '';
  String _renderedPath = ''; 
  
  List<FileSystemEntity> _files = [];
  
  bool _isSearching = false;
  bool _isSearchingLoading = false;
  List<FileSystemEntity> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Map<String, String> _searchThumbnails = {}; 

  Map<String, String> _thumbnails = {};
  Map<String, DateTime> _createdTimes = {};
  Map<String, DateTime> _modifiedTimes = {};
  
  Map<String, String> _dirItemCounts = {};
  
  bool _isLoading = true;
  SortMethod _currentSort = SortMethod.nameAsc;

  final Set<String> _selectedPaths = {};
  bool get _isSelectionMode => _selectedPaths.isNotEmpty;

  bool _isSyncing = false;
  String _syncMessage = '';
  
  bool _isGoingBack = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _loadSortMethod();
    await _requestPermissions();
    await _initRootDirectory();
  }

  Future<void> _loadSortMethod() async {
    final prefs = await SharedPreferences.getInstance();
    int? sortIndex = prefs.getInt('sort_method');
    if (sortIndex != null && sortIndex >= 0 && sortIndex < SortMethod.values.length) {
      _currentSort = SortMethod.values[sortIndex];
    }
  }

  Future<void> _saveSortMethod(SortMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sort_method', method.index);
    setState(() => _currentSort = method);
    _sortFiles();
  }

  Future<void> _requestPermissions() async {
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    if (await Permission.storage.isDenied) {
      await Permission.storage.request();
    }
  }

  Future<void> _initRootDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedPath = prefs.getString('root_path');

    if (savedPath != null && Directory(savedPath).existsSync()) {
      setState(() {
        _rootPath = savedPath;
        _currentPath = savedPath;
        _renderedPath = savedPath; 
      });
      await _loadFiles(_currentPath);
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickRootDirectory() async {
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('root_path', selectedDirectory);

      setState(() {
        _rootPath = selectedDirectory;
        _currentPath = selectedDirectory;
        _renderedPath = selectedDirectory;
        _isLoading = true; 
      });
      await _loadFiles(_currentPath);
    }
  }

  void _sortFileArray(List<FileSystemEntity> list) {
    list.sort((a, b) {
      bool aIsDir = a is Directory;
      bool bIsDir = b is Directory;

      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;

      String aName = a.path.split('/').last.toLowerCase();
      String bName = b.path.split('/').last.toLowerCase();

      switch (_currentSort) {
        case SortMethod.nameAsc: return aName.compareTo(bName);
        case SortMethod.nameDesc: return bName.compareTo(aName);
        case SortMethod.createdDesc:
        case SortMethod.createdAsc:
          DateTime aTime = _createdTimes[a.path] ?? a.statSync().changed;
          DateTime bTime = _createdTimes[b.path] ?? b.statSync().changed;
          return _currentSort == SortMethod.createdDesc ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
        case SortMethod.modifiedDesc:
        case SortMethod.modifiedAsc:
          DateTime aTime = _modifiedTimes[a.path] ?? a.statSync().modified;
          DateTime bTime = _modifiedTimes[b.path] ?? b.statSync().modified;
          return _currentSort == SortMethod.modifiedDesc ? bTime.compareTo(aTime) : aTime.compareTo(bTime);
      }
    });
  }

  void _sortFiles() {
    _sortFileArray(_files);
    _sortFileArray(_searchResults);
    setState(() {});
  }

  String _getDirCountText(Directory dir) {
    try {
      int dCount = 0;
      int fCount = 0;
      for (var child in dir.listSync()) {
        if (child is Directory) {
          dCount++;
        } else if (child is File && child.path.toLowerCase().endsWith('.md')) {
          fCount++;
        }
      }
      List<String> labels = [];
      if (dCount > 0) labels.add('$dCount 目录');
      if (fCount > 0) labels.add('$fCount 笔记');
      return labels.isEmpty ? '空' : labels.join(' · ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _loadFiles(String path) async {
    setState(() => _isLoading = true); 
    final prefs = await SharedPreferences.getInstance();
    bool showYaml = prefs.getBool('show_yaml_in_thumbnail') ?? false;

    try {
      Directory dir = Directory(path);
      List<FileSystemEntity> entities = dir.listSync();

      entities.retainWhere((entity) {
        return entity is Directory || entity.path.toLowerCase().endsWith('.md');
      });

      _thumbnails.clear();
      _createdTimes.clear();
      _modifiedTimes.clear();
      _dirItemCounts.clear(); 

      for (var entity in entities) {
        if (entity is Directory) {
          _dirItemCounts[entity.path] = _getDirCountText(entity);
        } else if (entity is File) {
          try {
            String content = await entity.readAsString();
            Map<String, String> props = NoteUtil.parseFrontmatter(content);
            
            DateTime? created = NoteUtil.getYamlTime(content, 'created');
            DateTime? modified = NoteUtil.getYamlTime(content, 'modified');
            if (created != null) _createdTimes[entity.path] = created;
            if (modified != null) _modifiedTimes[entity.path] = modified;

            String textOnly = NoteUtil.extractBody(content).replaceAll('\n', ' ').trim();
            
            if (showYaml) {
              String yamlSummary = '';
              props.forEach((k, v) {
                if (k != 'created' && k != 'modified' && k != 'synced' && v.isNotEmpty) {
                  yamlSummary += '[$k: $v] ';
                }
              });
              textOnly = yamlSummary + textOnly;
            }
            
            _thumbnails[entity.path] = textOnly.length > 50 ? '${textOnly.substring(0, 50)}...' : textOnly;
          } catch (e) {
            _thumbnails[entity.path] = "无法读取内容";
          }
        }
      }

      _files = entities;
      _renderedPath = path; 
      _selectedPaths.clear(); 
      _sortFiles();
      _isLoading = false;
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _searchThumbnails.clear();
        _isSearchingLoading = false;
      });
      return;
    }
    
    setState(() => _isSearchingLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    bool showYaml = prefs.getBool('show_yaml_in_thumbnail') ?? false;

    String lowerQuery = query.toLowerCase();
    List<FileSystemEntity> results = [];
    _searchThumbnails.clear(); 
    
    try {
      Directory dir = Directory(_rootPath);
      var allEntities = dir.listSync(recursive: true);
      
      for (var entity in allEntities) {
        if (entity is Directory) {
          _dirItemCounts[entity.path] = _getDirCountText(entity);
          
          String name = entity.path.split('/').last.toLowerCase();
          if (name.contains(lowerQuery)) results.add(entity);
        } else if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
          String name = entity.path.split('/').last.toLowerCase();
          bool matches = name.contains(lowerQuery); 
          
          String content = '';
          try { content = await entity.readAsString(); } catch (_) {}

          if (!matches && content.toLowerCase().contains(lowerQuery)) {
            matches = true;
          }
          
          if (matches) {
            results.add(entity);
            try {
              Map<String, String> props = NoteUtil.parseFrontmatter(content);
              DateTime? created = NoteUtil.getYamlTime(content, 'created');
              DateTime? modified = NoteUtil.getYamlTime(content, 'modified');
              if (created != null) _createdTimes[entity.path] = created;
              if (modified != null) _modifiedTimes[entity.path] = modified;

              String textOnly = NoteUtil.extractBody(content).replaceAll('\n', ' ').trim();
              String displaySnippet = textOnly;
              
              int matchIdx = textOnly.toLowerCase().indexOf(lowerQuery);
              if (matchIdx != -1) {
                int start = (matchIdx - 15).clamp(0, textOnly.length);
                int end = (matchIdx + lowerQuery.length + 20).clamp(0, textOnly.length);
                displaySnippet = (start > 0 ? '...' : '') + textOnly.substring(start, end) + (end < textOnly.length ? '...' : '');
              } else {
                displaySnippet = textOnly.length > 50 ? '${textOnly.substring(0, 50)}...' : textOnly;
              }
              
              if (showYaml) {
                String yamlSummary = '';
                props.forEach((k, v) {
                  if (k != 'created' && k != 'modified' && k != 'synced' && v.isNotEmpty) {
                    yamlSummary += '[$k: $v] ';
                  }
                });
                displaySnippet = yamlSummary + displaySnippet;
              }
              
              _searchThumbnails[entity.path] = displaySnippet;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    if (mounted && _searchController.text == query) {
      _sortFileArray(results);
      setState(() {
        _searchResults = results;
        _isSearchingLoading = false;
      });
    }
  }

  void _cancelSearch() {
    setState(() {
      _isSearching = false;
      _isGoingBack = true; 
      _searchController.clear();
      _searchResults.clear();
      _searchThumbnails.clear();
    });
  }

  Widget _buildHighlightedText(String text, String query, {TextStyle? style, int? maxLines, TextOverflow? overflow}) {
    if (query.isEmpty) return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (!lowerText.contains(lowerQuery)) return Text(text, style: style, maxLines: maxLines, overflow: overflow);

    final List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;

    while ((indexOfMatch = lowerText.indexOf(lowerQuery, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(TextSpan(text: text.substring(start, indexOfMatch), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: style?.copyWith(
          backgroundColor: Colors.yellow.shade300, 
          color: Colors.black87,
        ) ?? TextStyle(
          backgroundColor: Colors.yellow.shade300, 
          color: Colors.black87,
        ),
      ));
      start = indexOfMatch + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }

    return Text.rich(
      TextSpan(children: spans, style: style), 
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.ellipsis,
    );
  }

  // ================= 修复：提取一个共用的待删除记录方法 =================
  Future<void> _recordPendingDelete(String path) async {
    String relPath = path.replaceFirst(_rootPath, '');
    final prefs = await SharedPreferences.getInstance();
    List<String> deletes = prefs.getStringList('pending_deletes') ?? [];
    if (!deletes.contains(relPath)) {
      deletes.add(relPath);
      await prefs.setStringList('pending_deletes', deletes);
    }
  }
  // =================================================================

  void _deleteSelected() async {
    bool? confirmed = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除选中项'),
        content: Text('确定要永久删除选中的 ${_selectedPaths.length} 个项目吗？（开启云同步时也会从云端删除）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      String davUrl = prefs.getString('dav_url') ?? '';
      String davUser = prefs.getString('dav_user') ?? '';
      String davPwd = prefs.getString('dav_pwd') ?? '';
      
      webdav.Client? client;
      if (davUrl.isNotEmpty && davUser.isNotEmpty && davPwd.isNotEmpty) {
        client = webdav.newClient(davUrl, user: davUser, password: davPwd);
      }

      for (String path in _selectedPaths) {
        await _recordPendingDelete(path); // 记录本地删除以便同步

        String relativePath = path.replaceFirst(_rootPath, '');
        String remotePath = '/TreeNotes$relativePath';

        if (FileSystemEntity.isDirectorySync(path)) {
          Directory(path).deleteSync(recursive: true);
        } else {
          File(path).deleteSync();
        }
        
        if (client != null) {
          try { await client.removeAll(remotePath); } catch (_) {} 
        }
      }
      _loadFiles(_currentPath);
      if (_isSearching) _performSearch(_searchController.text);
    }
  }

  void _moveSelected() {
    List<Directory> dirs = [];
    void getDirs(Directory d) {
      dirs.add(d);
      try {
        for (var e in d.listSync()) {
          if (e is Directory) getDirs(e);
        }
      } catch (_) {}
    }
    getDirs(Directory(_rootPath));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移动到...'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: dirs.length,
            itemBuilder: (c, i) {
              String dirName = dirs[i].path == _rootPath ? 'TreeNotes (根目录)' : dirs[i].path.replaceFirst('$_rootPath/', '');
              return ListTile(
                leading: const Icon(Icons.folder, color: Colors.amber),
                title: Text(dirName),
                onTap: () => Navigator.pop(ctx, dirs[i].path),
              );
            },
          ),
        ),
      ),
    ).then((targetPath) async {
      if (targetPath != null) {
        for (String path in _selectedPaths) {
          FileSystemEntity entity = FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);
          String name = path.split('/').last;
          String newPath = '$targetPath/$name';
          
          if (path != newPath && !targetPath.toString().startsWith(path)) {
            await _recordPendingDelete(path); // 记录移动前的旧路径
            entity.renameSync(newPath);
          }
        }
        _loadFiles(_currentPath);
        if (_isSearching) _performSearch(_searchController.text);
      }
    });
  }

  Future<void> _uploadDirectory(Directory dir, String remotePath, webdav.Client client) async {
    var entities = dir.listSync();
    for (var entity in entities) {
      String name = entity.path.split('/').last;
      String currentRemotePath = '$remotePath/$name';

      if (entity is Directory) {
        try { await client.mkdir(currentRemotePath); } catch (_) {} 
        await _uploadDirectory(entity, currentRemotePath, client);
      } else if (entity is File && name.endsWith('.md')) {
        bool needsUpload = true;
        try {
          String content = await entity.readAsString();
          DateTime? modified = NoteUtil.getYamlTime(content, 'modified');
          DateTime? synced = NoteUtil.getYamlTime(content, 'synced');
          
          if (modified != null && synced != null) {
            if (!modified.isAfter(synced)) {
              needsUpload = false; 
            }
          }
        } catch (_) {}

        if (needsUpload) {
          if (mounted) setState(() => _syncMessage = '正在上传: $name');
          var data = await entity.readAsBytes();
          await client.write(currentRemotePath, data);
        }
      }
    }
  }

  Future<void> _downloadDirectory(String remotePath, String localPath, webdav.Client client) async {
    var list = await client.readDir(remotePath);
    for (var file in list) {
      String name = file.name ?? '';
      if (name.isEmpty) continue;
      String currentLocalPath = '$localPath/$name';

      if (file.isDir == true) {
        Directory(currentLocalPath).createSync(recursive: true);
        await _downloadDirectory(file.path!, currentLocalPath, client);
      } else if (name.endsWith('.md')) {
        bool needsDownload = true;
        File localFile = File(currentLocalPath);
        
        if (localFile.existsSync()) {
          try {
            String content = await localFile.readAsString();
            DateTime? synced = NoteUtil.getYamlTime(content, 'synced');
            DateTime? remoteTime = file.mTime;
            
            if (remoteTime != null && synced != null) {
              if (remoteTime.difference(synced).inSeconds <= 60) {
                needsDownload = false;
              }
            }
          } catch (_) {}
        }

        if (needsDownload) {
          if (mounted) setState(() => _syncMessage = '正在下载: $name');
          var data = await client.read(file.path!);
          await localFile.writeAsBytes(data);
        }
      }
    }
  }

  Future<void> _updateAllSyncedTimes(Directory dir) async {
    try {
      var entities = dir.listSync(recursive: true);
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.md')) {
          await NoteUtil.updateFileSyncedTime(entity);
        }
      }
    } catch (_) {}
  }

  Future<void> _syncCloud() async {
    final prefs = await SharedPreferences.getInstance();
    String davUrl = prefs.getString('dav_url') ?? '';
    String davUser = prefs.getString('dav_user') ?? '';
    String davPwd = prefs.getString('dav_pwd') ?? '';

    if (davUrl.isEmpty || davUser.isEmpty || davPwd.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置中配置 WebDAV 账号')));
      return;
    }

    if (mounted) setState(() { _isSyncing = true; _syncMessage = '连接服务器...'; });

    try {
      var client = webdav.newClient(davUrl, user: davUser, password: davPwd);
      await client.ping();
      try { await client.mkdir('/TreeNotes'); } catch (_) {}
      
      // ================= 修复：同步前清理掉本地被重命名、移动或删除的幽灵文件 =================
      List<String> deletes = prefs.getStringList('pending_deletes') ?? [];
      for (String relPath in deletes) {
        if (mounted) setState(() => _syncMessage = '清理云端失效文件...');
        try { await client.removeAll('/TreeNotes$relPath'); } catch (_) {}
      }
      await prefs.setStringList('pending_deletes', []); 
      // ==============================================================================

      await _uploadDirectory(Directory(_rootPath), '/TreeNotes', client);
      await _downloadDirectory('/TreeNotes', _rootPath, client);
      await _updateAllSyncedTimes(Directory(_rootPath));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同步完成！')));
        await _loadFiles(_currentPath); 
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('同步失败: $e')));
    } finally {
      if (mounted) setState(() { _isSyncing = false; _syncMessage = ''; });
    }
  }

  Future<void> _quickCreateNote() async {
    int index = 1;
    String newFileName = '新建$index.md';
    
    while (File('$_currentPath/$newFileName').existsSync()) {
      index++;
      newFileName = '新建$index.md';
    }

    File newFile = File('$_currentPath/$newFileName');
    await newFile.writeAsString(NoteUtil.generateInitialContent());
    
    await _loadFiles(_currentPath);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NoteEditorPage(file: newFile)),
      ).then((_) {
        _loadFiles(_currentPath);
        if (_isSearching) _performSearch(_searchController.text);
      });
    }
  }

  void _showCreateFolderDialog() {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新建文件夹', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '请输入文件夹名称', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            autofocus: true,
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), style: TextButton.styleFrom(foregroundColor: Colors.grey), child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.isNotEmpty) {
                  String name = controller.text.trim();
                  await Directory('$_currentPath/$name').create();
                  if (context.mounted) Navigator.pop(context);
                  _loadFiles(_currentPath);
                  if (_isSearching) _performSearch(_searchController.text);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreen.shade50, foregroundColor: Colors.green.shade800, elevation: 0),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _goBack() {
    if (_currentPath != _rootPath) {
      setState(() {
        _isGoingBack = true; 
        _currentPath = Directory(_currentPath).parent.path;
      });
      _loadFiles(_currentPath);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rootPath.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('欢迎使用 TreeNotes'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_special, size: 80, color: Colors.lightGreen),
              const SizedBox(height: 24),
              const Text('请选择一个本地文件夹\n用来存放你所有的 Markdown 笔记', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _pickRootDirectory,
                icon: const Icon(Icons.create_new_folder),
                label: const Text('选择笔记存储目录', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: Colors.lightGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    bool canGoBack = _currentPath != _rootPath;
    List<FileSystemEntity> currentList = _isSearching ? _searchResults : _files;

    return PopScope(
      canPop: !canGoBack && !_isSelectionMode && !_isSearching,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isSelectionMode) {
            setState(() => _selectedPaths.clear()); 
          } else if (_isSearching) {
            _cancelSearch();
          } else if (canGoBack) {
            _goBack(); 
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedPaths.clear()))
              : (_isSearching 
                  ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _cancelSearch)
                  : (canGoBack ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack) : null)),
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: '搜索标题、属性或正文...',
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
                      _performSearch(val);
                    });
                  },
                )
              : Text(_isSelectionMode ? '已选择 ${_selectedPaths.length} 项' : (canGoBack ? _currentPath.split('/').last : 'TreeNotes')),
          backgroundColor: _isSelectionMode ? Colors.lightGreen.shade100 : Theme.of(context).colorScheme.primaryContainer,
          actions: _isSelectionMode 
            ? [
                IconButton(icon: const Icon(Icons.drive_file_move, color: Colors.green), tooltip: '移动', onPressed: _moveSelected),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: '删除', onPressed: _deleteSelected),
              ]
            : (_isSearching
                ? [
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _performSearch('');
                      },
                    )
                  ]
                : [
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: '搜索',
                      onPressed: () => setState(() { _isSearching = true; _isGoingBack = false; }), 
                    ),
                    PopupMenuButton<SortMethod>(
                      icon: const Icon(Icons.sort),
                      tooltip: '自定义排序',
                      onSelected: _saveSortMethod,
                      itemBuilder: (context) => <PopupMenuEntry<SortMethod>>[
                        CheckedPopupMenuItem(value: SortMethod.nameAsc, checked: _currentSort == SortMethod.nameAsc, child: const Text('名称 (A-Z)')),
                        CheckedPopupMenuItem(value: SortMethod.nameDesc, checked: _currentSort == SortMethod.nameDesc, child: const Text('名称 (Z-A)')),
                        CheckedPopupMenuItem(value: SortMethod.modifiedDesc, checked: _currentSort == SortMethod.modifiedDesc, child: const Text('修改时间 (最新)')),
                        CheckedPopupMenuItem(value: SortMethod.modifiedAsc, checked: _currentSort == SortMethod.modifiedAsc, child: const Text('修改时间 (最旧)')),
                        CheckedPopupMenuItem(value: SortMethod.createdDesc, checked: _currentSort == SortMethod.createdDesc, child: const Text('创建时间 (最新)')),
                        CheckedPopupMenuItem(value: SortMethod.createdAsc, checked: _currentSort == SortMethod.createdAsc, child: const Text('创建时间 (最旧)')),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      tooltip: '设置',
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SettingsPage(onSync: _syncCloud))).then((_) => _loadFiles(_currentPath)),
                    ),
                  ]),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: _syncCloud,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350), 
                      switchInCurve: Curves.easeOutQuart,
                      switchOutCurve: Curves.easeOutQuart,
                      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                        return Stack(
                          alignment: Alignment.topCenter,
                          children: <Widget>[
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        final Key currentKey = _isSearching 
                            ? (currentList.isEmpty ? const ValueKey('empty_search') : const ValueKey('search_list'))
                            : (currentList.isEmpty ? ValueKey('empty_$_renderedPath') : ValueKey('list_$_renderedPath'));
                            
                        final bool isEntering = child.key == currentKey;
                        
                        Offset beginOffset;
                        if (_isGoingBack) {
                          beginOffset = isEntering ? const Offset(-1.0, 0.0) : const Offset(1.0, 0.0);
                        } else {
                          beginOffset = isEntering ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0);
                        }

                        return SlideTransition(
                          position: Tween<Offset>(begin: beginOffset, end: Offset.zero).animate(animation),
                          child: child,
                        );
                      },
                      child: Container(
                        key: ValueKey(_isSearching 
                            ? (currentList.isEmpty ? 'empty_search' : 'search_list')
                            : (currentList.isEmpty ? 'empty_$_renderedPath' : 'list_$_renderedPath')),
                        width: double.infinity,
                        height: double.infinity,
                        color: Theme.of(context).scaffoldBackgroundColor, 
                        child: currentList.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  if (_isSearching)
                                    Container(
                                      height: 200,
                                      alignment: Alignment.center,
                                      child: Text(
                                        _searchController.text.trim().isEmpty ? '输入关键字进行全局搜索' : '没有找到相关内容',
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    )
                                ], 
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: currentList.length,
                                itemBuilder: (context, index) {
                                  FileSystemEntity entity = currentList[index];
                                  bool isDirectory = entity is Directory;
                                  String name = entity.path.split('/').last;
                                  bool isSelected = _selectedPaths.contains(entity.path);

                                  String titleStr = isDirectory ? name : name.replaceAll('.md', '');
                                  String subtitleStr = _isSearching 
                                      ? (_searchThumbnails[entity.path] ?? '无内容') 
                                      : (_thumbnails[entity.path] ?? '无内容');
                                  String query = _isSearching ? _searchController.text.trim() : '';

                                  return ListTile(
                                    selected: isSelected,
                                    selectedTileColor: Colors.green.shade50,
                                    leading: isDirectory ? const Icon(Icons.folder, color: Colors.amber, size: 40) : null,
                                    title: _buildHighlightedText(
                                      titleStr, 
                                      query, 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                                    ),
                                    subtitle: isDirectory 
                                        ? null 
                                        : _buildHighlightedText(
                                            subtitleStr, 
                                            query, 
                                            maxLines: 1, 
                                            overflow: TextOverflow.ellipsis, 
                                            style: const TextStyle(color: Colors.grey)
                                          ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                    trailing: _isSelectionMode 
                                        ? Checkbox(
                                            activeColor: Colors.lightGreen,
                                            value: isSelected, 
                                            onChanged: (v) {
                                              setState(() {
                                                if (v == true) _selectedPaths.add(entity.path);
                                                else _selectedPaths.remove(entity.path);
                                              });
                                            }) 
                                        : (isDirectory 
                                            ? Text(
                                                _dirItemCounts[entity.path] ?? '', 
                                                style: const TextStyle(color: Colors.grey, fontSize: 13)
                                              ) 
                                            : null),
                                    onLongPress: () {
                                      setState(() => _selectedPaths.add(entity.path));
                                    },
                                    onTap: () {
                                      if (_isSelectionMode) {
                                        setState(() {
                                          if (isSelected) _selectedPaths.remove(entity.path);
                                          else _selectedPaths.add(entity.path);
                                        });
                                      } else {
                                        if (isDirectory) {
                                          setState(() {
                                            _isGoingBack = false; 
                                            _currentPath = entity.path;
                                            if (_isSearching) {
                                              _cancelSearch(); 
                                            }
                                          });
                                          _loadFiles(_currentPath);
                                        } else {
                                          Navigator.push(context, MaterialPageRoute(builder: (context) => NoteEditorPage(file: entity as File))).then((_) {
                                            _loadFiles(_currentPath);
                                            if (_isSearching) _performSearch(_searchController.text);
                                          });
                                        }
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                  if ((_isSearching && _isSearchingLoading) || (!_isSearching && _isLoading))
                    const Positioned(
                      top: 0, left: 0, right: 0,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.lightGreen),
                      ),
                    ),
                ],
              ),
            ),
            if (_isSyncing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: Colors.lightGreen.shade50,
                child: Row(
                  children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_syncMessage, style: TextStyle(color: Colors.green.shade800), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
        ),
        floatingActionButton: (_isSelectionMode || _isSearching)
          ? null 
          : GestureDetector(
              onLongPress: _showCreateFolderDialog, 
              child: FloatingActionButton(
                onPressed: _quickCreateNote, 
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.add),
              ),
            ),
      ),
    );
  }
}