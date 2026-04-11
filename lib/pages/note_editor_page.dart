import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/note_util.dart';

class _PropEntry {
  final TextEditingController keyCtrl;
  final TextEditingController valCtrl;

  _PropEntry(String key, String val)
      : keyCtrl = TextEditingController(text: key),
        valCtrl = TextEditingController(text: val);

  void dispose() {
    keyCtrl.dispose();
    valCtrl.dispose();
  }
}

class NoteEditorPage extends StatefulWidget {
  final File file;

  const NoteEditorPage({super.key, required this.file});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late File _currentFile; 
  final TextEditingController _bodyController = TextEditingController();
  
  late TextEditingController _titleController;
  final FocusNode _titleFocusNode = FocusNode();
  bool _isEditingTitle = false;
  
  // 新增：拦截退出防抖锁
  bool _isExiting = false;

  final Map<String, String> _timeProps = {};
  final List<_PropEntry> _customProps = [];
  
  bool _isPreviewMode = false;
  bool _isLoading = true;

  Timer? _autoSaveTimer;
  
  // 新增：任务锁，防止并发保存和重命名冲突
  Future<void>? _saveFuture;
  Future<void>? _renameFuture;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.file;
    
    String initialTitle = _currentFile.path.split('/').last.replaceAll('.md', '');
    _titleController = TextEditingController(text: initialTitle);
    
    _titleFocusNode.addListener(() {
      if (!_titleFocusNode.hasFocus && _isEditingTitle) {
        _commitRename();
      }
    });

    _loadSettingsAndContent();
  }

  Future<void> _loadSettingsAndContent() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isPreviewMode = prefs.getBool('default_is_preview') ?? false;
    });

    try {
      String content = await _currentFile.readAsString();
      Map<String, String> parsedProps = NoteUtil.parseFrontmatter(content);
      
      _timeProps['created'] = parsedProps['created'] ?? '';
      _timeProps['modified'] = parsedProps['modified'] ?? '';
      _timeProps['synced'] = parsedProps['synced'] ?? '';

      _customProps.clear();
      parsedProps.forEach((key, value) {
        if (key != 'created' && key != 'modified' && key != 'synced') {
          _customProps.add(_PropEntry(key, value));
        }
      });

      _bodyController.text = NoteUtil.extractBody(content);
      _bodyController.addListener(_triggerAutoSave);

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _bodyController.text = "读取文件失败：$e";
        _isLoading = false;
      });
    }
  }

  void _triggerAutoSave() {
    if (_autoSaveTimer?.isActive ?? false) _autoSaveTimer!.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      _saveFile(silent: true);
    });
  }

  // ================= 修复：使用并发锁保证文件保存安全 =================
  Future<void> _saveFile({bool silent = false}) async {
    if (_saveFuture != null) {
      await _saveFuture;
      return;
    }
    _saveFuture = _doSaveFile(silent: silent);
    await _saveFuture;
    _saveFuture = null;
  }

  Future<void> _doSaveFile({bool silent = false}) async {
    try {
      Map<String, String> allProps = {};
      allProps.addAll(_timeProps);
      allProps['modified'] = DateTime.now().toIso8601String().split('.')[0]; 
      
      for (var prop in _customProps) {
        String key = prop.keyCtrl.text.trim();
        String val = prop.valCtrl.text.trim();
        if (key.isNotEmpty && key != 'created' && key != 'modified' && key != 'synced') {
          allProps[key] = val;
        }
      }

      String newFrontmatter = NoteUtil.buildFrontmatter(allProps);
      String newBody = _bodyController.text;

      await _currentFile.writeAsString('$newFrontmatter$newBody');

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功！'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }
  // ================================================================

  // ================= 修复：使用并发锁保证重命名安全，避免冲突 =================
  Future<void> _commitRename() async {
    if (_renameFuture != null) {
      await _renameFuture;
      return;
    }
    _renameFuture = _doRename();
    await _renameFuture;
    _renameFuture = null;
  }

  Future<void> _doRename() async {
    if (!mounted) return;

    String currentName = _currentFile.path.split('/').last.replaceAll('.md', '');
    String newName = _titleController.text.trim();

    if (newName.isEmpty || newName == currentName) {
      setState(() {
        _titleController.text = currentName;
        _isEditingTitle = false;
      });
      return;
    }

    String parentPath = _currentFile.parent.path;
    String newPath = '$parentPath/$newName.md';
    String oldPath = _currentFile.path;

    if (File(newPath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该名称已存在！')));
      setState(() {
        _titleController.text = currentName;
        _isEditingTitle = false;
      });
      return;
    }

    try {
      await _saveFile(silent: true);
      File renamedFile = await _currentFile.rename(newPath);
      
      final prefs = await SharedPreferences.getInstance();
      String rootPath = prefs.getString('root_path') ?? '';
      if (rootPath.isNotEmpty && oldPath.startsWith(rootPath)) {
        String relPath = oldPath.replaceFirst(rootPath, '');
        List<String> deletes = prefs.getStringList('pending_deletes') ?? [];
        if (!deletes.contains(relPath)) {
          deletes.add(relPath);
          await prefs.setStringList('pending_deletes', deletes);
        }
      }

      if (!mounted) return; 
      setState(() {
        _currentFile = renamedFile;
        _isEditingTitle = false;
      });
    } catch (e) {
      if (!mounted) return; 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败：$e')));
      setState(() {
        _titleController.text = currentName;
        _isEditingTitle = false;
      });
    }
  }
  // =========================================================================

  void _showInfoDialog() {
    int bytes = _currentFile.lengthSync();
    String sizeStr = bytes < 1024 ? '$bytes B' : bytes < 1024 * 1024 ? '${(bytes / 1024).toStringAsFixed(2)} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    String formatDate(String? dtStr) => (dtStr == null || dtStr.isEmpty) ? '未知 / 尚未同步' : dtStr.split('.')[0]; 

    int charCount = _bodyController.text.length;
    int strictCharCount = _bodyController.text.replaceAll(RegExp(r'\s+'), '').length;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('笔记信息', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Icons.text_snippet, color: Colors.purple), title: const Text('字符统计'), trailing: Text('$strictCharCount 字 ($charCount 字符)'), dense: true, contentPadding: EdgeInsets.zero),
              ListTile(leading: const Icon(Icons.data_usage, color: Colors.lightGreen), title: const Text('文件大小'), trailing: Text(sizeStr), dense: true, contentPadding: EdgeInsets.zero),
              ListTile(leading: const Icon(Icons.add_circle_outline, color: Colors.green), title: const Text('创建时间'), subtitle: Text(formatDate(_timeProps['created'])), dense: true, contentPadding: EdgeInsets.zero),
              ListTile(leading: const Icon(Icons.edit_note, color: Colors.amber), title: const Text('修改时间'), subtitle: Text(formatDate(_timeProps['modified'])), dense: true, contentPadding: EdgeInsets.zero),
              ListTile(leading: const Icon(Icons.cloud_sync_outlined, color: Colors.blue), title: const Text('同步时间'), subtitle: Text(formatDate(_timeProps['synced'])), dense: true, contentPadding: EdgeInsets.zero),
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
        );
      },
    );
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    
    int start = selection.start;
    int end = selection.end;
    
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    
    final selectedText = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$prefix$selectedText$suffix');
    
    _bodyController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + prefix.length + selectedText.length),
    );
    
    _triggerAutoSave();
  }

  Widget _buildToolbarBtn(IconData icon, String prefix, String suffix, {String tooltip = ''}) {
    return IconButton(
      icon: Icon(icon, color: Colors.grey.shade700),
      tooltip: tooltip,
      onPressed: () => _insertMarkdown(prefix, suffix),
    );
  }

  void _toggleCheckbox(int targetIndex) {
    final text = _bodyController.text;
    int currentIdx = 0;
    
    final RegExp checkboxPattern = RegExp(r'^([ \t]*[-*+]\s+)\[([ xX])\]', multiLine: true);
    
    final newText = text.replaceAllMapped(checkboxPattern, (match) {
      if (currentIdx == targetIndex) {
        currentIdx++;
        String prefix = match.group(1)!;
        String state = match.group(2)!;
        String newState = (state == ' ') ? 'x' : ' '; 
        return '$prefix[$newState]';
      }
      currentIdx++;
      return match.group(0)!;
    });

    if (text != newText) {
      _bodyController.text = newText;
      _triggerAutoSave();
      setState(() {});
    }
  }

  Future<void> _handleWikilinkTap(String noteName) async {
    String targetPath = '${_currentFile.parent.path}/$noteName.md';
    File targetFile = File(targetPath);

    if (!targetFile.existsSync()) {
      await targetFile.writeAsString(NoteUtil.generateInitialContent());
    }

    if (mounted) {
      await _saveFile(silent: true);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NoteEditorPage(file: targetFile)),
      ).then((_) {
        _loadSettingsAndContent();
      });
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _bodyController.removeListener(_triggerAutoSave);
    
    // 我们将统一的退出保存逻辑移交给了 PopScope
    // 所以这里不需要再发起无主的异步保存了
    _bodyController.dispose();
    _titleFocusNode.dispose();
    _titleController.dispose();
    
    for (var prop in _customProps) { prop.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int checkboxCounter = 0;

    // ================= 核心修复：利用 PopScope 完全接管物理返回键和 AppBar 退出 =================
    return PopScope(
      canPop: false, // 阻止立刻退出
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isExiting) return;
        _isExiting = true;

        // 强行取消键盘焦点
        FocusScope.of(context).unfocus();

        // 强行等待（如果有正在重命名的操作，就等它改完；如果没有，就至少保证保存一下）
        if (_isEditingTitle) {
          await _commitRename();
        } else {
          await _saveFile(silent: true);
        }

        // 文件读写全安全结束后，再执行真正的退出
        if (mounted) {
          Navigator.pop(context, result);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          title: _isEditingTitle
              ? TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  autofocus: true,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true, hintText: '笔记名称'),
                  onSubmitted: (_) => _commitRename(),
                )
              : GestureDetector(
                  onTap: () => setState(() => _isEditingTitle = true),
                  child: Text(_titleController.text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ),
          actions: [
            IconButton(
              icon: Icon(_isPreviewMode ? Icons.edit : Icons.preview),
              onPressed: () => setState(() => _isPreviewMode = !(_isPreviewMode)),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'add_prop') {
                  setState(() {
                    _isPreviewMode = false; 
                    _customProps.add(_PropEntry('', ''));
                  });
                  _triggerAutoSave();
                } else if (value == 'info') {
                  _showInfoDialog();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(value: 'add_prop', child: Row(children: [Icon(Icons.add_box_outlined, size: 20, color: Colors.grey), SizedBox(width: 8), Text('添加属性')])),
                const PopupMenuItem<String>(value: 'info', child: Row(children: [Icon(Icons.info_outline, size: 20, color: Colors.grey), SizedBox(width: 8), Text('详细信息')])),
              ],
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isPreviewMode
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_customProps.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                            decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300, width: 3))),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _customProps.map((prop) {
                                if (prop.keyCtrl.text.trim().isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 80, child: Text(prop.keyCtrl.text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600))),
                                      const Text(':  ', style: TextStyle(color: Colors.grey)),
                                      Expanded(child: Text(prop.valCtrl.text, style: const TextStyle(fontSize: 14))),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                        Builder(
                          builder: (context) {
                            String displayData = _bodyController.text;

                            displayData = displayData.replaceAllMapped(
                              RegExp(r'^([ \t]*[-*+]\s+\[[ xX]\])\s*$', multiLine: true),
                              (match) => '${match.group(1)} \u200B',
                            );

                            displayData = displayData.replaceAllMapped(
                              RegExp(r'\[\[(.*?)\]\]'),
                              (match) {
                                String name = match.group(1) ?? '';
                                return '[$name](wikilink:${Uri.encodeComponent(name)})';
                              },
                            );

                            return MarkdownBody(
                              data: displayData, 
                              selectable: true,
                              softLineBreak: true, 
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(fontSize: 16, height: 1.6),
                                listBullet: const TextStyle(fontSize: 16, height: 1.6),
                                listIndent: 20, 
                                blockSpacing: 10.0,
                                a: TextStyle(color: Colors.green.shade700, decoration: TextDecoration.underline), 
                              ),
                              onTapLink: (text, href, title) {
                                if (href != null && href.startsWith('wikilink:')) {
                                  String noteName = Uri.decodeComponent(href.replaceFirst('wikilink:', ''));
                                  _handleWikilinkTap(noteName);
                                }
                              },
                              checkboxBuilder: (bool checked) {
                                int currentIndex = checkboxCounter++;
                                return InkWell(
                                  onTap: () => _toggleCheckbox(currentIndex),
                                  child: Transform.translate(
                                    offset: const Offset(0, 3.5), 
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 6.0),
                                      child: Icon(
                                        checked ? Icons.check_box : Icons.check_box_outline_blank,
                                        size: 20,
                                        color: checked ? Colors.lightGreen : Colors.grey,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_customProps.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                                  decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300, width: 3))),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ..._customProps.map((prop) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                                          child: Row(
                                            children: [
                                              SizedBox(width: 80, child: TextField(controller: prop.keyCtrl, onChanged: (v) => _triggerAutoSave(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600), decoration: const InputDecoration.collapsed(hintText: '属性名'))),
                                              const Text(':  ', style: TextStyle(color: Colors.grey)),
                                              Expanded(child: TextField(controller: prop.valCtrl, onChanged: (v) => _triggerAutoSave(), style: const TextStyle(fontSize: 14), decoration: const InputDecoration.collapsed(hintText: '空'))),
                                              InkWell(onTap: () { setState(() { _customProps.remove(prop); prop.dispose(); }); _triggerAutoSave(); }, child: const Icon(Icons.close, size: 16, color: Colors.grey)),
                                              const SizedBox(width: 8),
                                            ],
                                          ),
                                        );
                                      }),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () { setState(() => _customProps.add(_PropEntry('', ''))); _triggerAutoSave(); },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                                          child: Row(
                                            children: [
                                              Icon(Icons.add, size: 16, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text('添加属性', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              Expanded(
                                child: TextField(
                                  controller: _bodyController,
                                  maxLines: null,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: const InputDecoration(border: InputBorder.none, hintText: '开始编写正文...'),
                                  style: const TextStyle(fontSize: 16, height: 1.6), 
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      Container(
                        height: 48,
                        width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey.shade100, border: Border(top: BorderSide(color: Colors.grey.shade300))),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildToolbarBtn(Icons.format_bold, '**', '**', tooltip: '加粗'),
                              _buildToolbarBtn(Icons.format_italic, '*', '*', tooltip: '斜体'),
                              _buildToolbarBtn(Icons.format_strikethrough, '~~', '~~', tooltip: '删除线'),
                              _buildToolbarBtn(Icons.format_size, '# ', '', tooltip: '标题'),
                              _buildToolbarBtn(Icons.format_list_bulleted, '- ', '', tooltip: '无序列表'),
                              _buildToolbarBtn(Icons.format_list_numbered, '1. ', '', tooltip: '有序列表'),
                              _buildToolbarBtn(Icons.check_box_outlined, '- [ ] ', '', tooltip: '待办任务'),
                              _buildToolbarBtn(Icons.format_quote, '> ', '', tooltip: '引用'),
                              _buildToolbarBtn(Icons.code, '`', '`', tooltip: '行内代码'),
                              _buildToolbarBtn(Icons.terminal, '```\n', '\n```', tooltip: '代码块'),
                              _buildToolbarBtn(Icons.link, '[', '](url)', tooltip: '链接'),
                              _buildToolbarBtn(Icons.cable, '[[', ']]', tooltip: '双向链接'),
                              _buildToolbarBtn(Icons.image, '![', '](url)', tooltip: '图片'),
                              _buildToolbarBtn(Icons.functions, r'$$', r'$$', tooltip: '数学公式'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}