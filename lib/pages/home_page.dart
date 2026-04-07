import 'dart:io';
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
  List<FileSystemEntity> _files = [];
  
  Map<String, String> _thumbnails = {};
  Map<String, DateTime> _createdTimes = {};
  Map<String, DateTime> _modifiedTimes = {};
  
  bool _isLoading = true;
  SortMethod _currentSort = SortMethod.nameAsc;

  final Set<String> _selectedPaths = {};
  bool get _isSelectionMode => _selectedPaths.isNotEmpty;

  // ==== 新增：同步状态指示 ====
  bool _isSyncing = false;
  String _syncMessage = '';

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
        _isLoading = true; 
      });
      await _loadFiles(_currentPath);
    }
  }

  void _sortFiles() {
    _files.sort((a, b) {
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
    setState(() {});
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

      for (var entity in entities) {
        if (entity is File) {
          try {
            String content = await entity.readAsString();
            Map<String, String> props = NoteUtil.parseFrontmatter(content);
            
            DateTime? created = NoteUtil.getYamlTime(content, 'created');
            DateTime? modified = NoteUtil.getYamlTime(content, 'modified');
            if (created != null) _createdTimes[entity.path] = created;
            if (modified != null) _modifiedTimes[entity.path] = modified;

            String textOnly = NoteUtil.extractBody(content).replaceAll('\n', ' ').trim();
            
            // ========== 根据设置决定是否将属性拼入缩略图 ==========
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
      _selectedPaths.clear(); 
      _sortFiles();
      _isLoading = false;
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

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
      // ========== 修复：删除本地时，一并尝试删除云端 ==========
      final prefs = await SharedPreferences.getInstance();
      String davUrl = prefs.getString('dav_url') ?? '';
      String davUser = prefs.getString('dav_user') ?? '';
      String davPwd = prefs.getString('dav_pwd') ?? '';
      
      webdav.Client? client;
      if (davUrl.isNotEmpty && davUser.isNotEmpty && davPwd.isNotEmpty) {
        client = webdav.newClient(davUrl, user: davUser, password: davPwd);
      }

      for (String path in _selectedPaths) {
        String relativePath = path.replaceFirst(_rootPath, '');
        String remotePath = '/TreeNotes$relativePath';

        if (FileSystemEntity.isDirectorySync(path)) {
          Directory(path).deleteSync(recursive: true);
        } else {
          File(path).deleteSync();
        }
        
        // 尝试从云端删除
        if (client != null) {
          try {
            await client.removeAll(remotePath);
          } catch (_) {} 
        }
      }
      
      _loadFiles(_currentPath);
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
    ).then((targetPath) {
      if (targetPath != null) {
        for (String path in _selectedPaths) {
          FileSystemEntity entity = FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);
          String name = path.split('/').last;
          String newPath = '$targetPath/$name';
          
          if (path != newPath && !targetPath.toString().startsWith(path)) {
            entity.renameSync(newPath);
          }
        }
        _loadFiles(_currentPath);
      }
    });
  }

  Future<void> _uploadDirectory(Directory dir, String remotePath, webdav.Client client) async {
    var entities = dir.listSync();
    for (var entity in entities) {
      String name = entity.path.split('/').last;
      String currentRemotePath = '$remotePath/$name';
      
      if (mounted) setState(() => _syncMessage = '正在上传: $name');

      if (entity is Directory) {
        try { await client.mkdir(currentRemotePath); } catch (_) {} 
        await _uploadDirectory(entity, currentRemotePath, client);
      } else if (entity is File && name.endsWith('.md')) {
        var data = await entity.readAsBytes();
        await client.write(currentRemotePath, data);
      }
    }
  }

  Future<void> _downloadDirectory(String remotePath, String localPath, webdav.Client client) async {
    var list = await client.readDir(remotePath);
    for (var file in list) {
      String name = file.name ?? '';
      if (name.isEmpty) continue;
      String currentLocalPath = '$localPath/$name';

      if (mounted) setState(() => _syncMessage = '正在下载: $name');

      if (file.isDir == true) {
        Directory(currentLocalPath).createSync(recursive: true);
        await _downloadDirectory(file.path!, currentLocalPath, client);
      } else if (name.endsWith('.md')) {
        var data = await client.read(file.path!);
        await File(currentLocalPath).writeAsBytes(data);
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
      
      await _uploadDirectory(Directory(_rootPath), '/TreeNotes', client);
      await _downloadDirectory('/TreeNotes', _rootPath, client);
      await _updateAllSyncedTimes(Directory(_rootPath));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同步成功！')));
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
      ).then((_) => _loadFiles(_currentPath));
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
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade50, foregroundColor: Colors.amber.shade900, elevation: 0),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  void _goBack() {
    if (_currentPath != _rootPath) {
      setState(() => _currentPath = Directory(_currentPath).parent.path);
      _loadFiles(_currentPath);
    }
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

    return PopScope(
      canPop: !canGoBack && !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_isSelectionMode) {
            setState(() => _selectedPaths.clear()); 
          } else if (canGoBack) {
            _goBack(); 
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedPaths.clear()))
              : (canGoBack ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBack) : null),
          title: Text(_isSelectionMode ? '已选择 ${_selectedPaths.length} 项' : (canGoBack ? _currentPath.split('/').last : 'TreeNotes')),
          backgroundColor: _isSelectionMode ? Colors.lightGreen.shade100 : Theme.of(context).colorScheme.primaryContainer,
          actions: _isSelectionMode 
            ? [
                IconButton(icon: const Icon(Icons.drive_file_move, color: Colors.green), tooltip: '移动', onPressed: _moveSelected),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: '删除', onPressed: _deleteSelected),
              ]
            : [
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
              ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _syncCloud,
                      child: _files.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [SizedBox(height: 200), Center(child: Text('这里空空如也，向下拉动可同步，或点击右下角新建！'))],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _files.length,
                              itemBuilder: (context, index) {
                                FileSystemEntity entity = _files[index];
                                bool isDirectory = entity is Directory;
                                String name = entity.path.split('/').last;
                                bool isSelected = _selectedPaths.contains(entity.path);

                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: Colors.green.shade50,
                                  leading: isDirectory ? const Icon(Icons.folder, color: Colors.amber, size: 40) : null,
                                  title: Text(isDirectory ? name : name.replaceAll('.md', ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  subtitle: isDirectory ? null : Text(_thumbnails[entity.path] ?? '无内容', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  trailing: _isSelectionMode ? Checkbox(
                                    activeColor: Colors.lightGreen,
                                    value: isSelected, onChanged: (v) {
                                    setState(() {
                                      if (v == true) _selectedPaths.add(entity.path);
                                      else _selectedPaths.remove(entity.path);
                                    });
                                  }) : null,
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
                                        setState(() => _currentPath = entity.path);
                                        _loadFiles(_currentPath);
                                      } else {
                                        Navigator.push(context, MaterialPageRoute(builder: (context) => NoteEditorPage(file: entity as File))).then((_) => _loadFiles(_currentPath));
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                    ),
            ),
            // ========== 新增：底部同步状态栏 ==========
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
        floatingActionButton: _isSelectionMode 
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