import 'dart:io';
import 'dart:async'; // 引入 Timer 支持自动保存
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
  final TextEditingController _bodyController = TextEditingController();
  
  final Map<String, String> _timeProps = {};
  final List<_PropEntry> _customProps = [];
  
  bool _isPreviewMode = false;
  bool _isLoading = true;

  Timer? _autoSaveTimer; // 自动保存的计时器

  @override
  void initState() {
    super.initState();
    _loadFileContent();
  }

  Future<void> _loadFileContent() async {
    try {
      String content = await widget.file.readAsString();
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

      // 内容加载完成后，添加监听器，每次修改都会触发自动保存
      _bodyController.addListener(_triggerAutoSave);

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _bodyController.text = "读取文件失败：$e";
        _isLoading = false;
      });
    }
  }

  // ==================== 自动保存机制 ====================
  void _triggerAutoSave() {
    if (_autoSaveTimer?.isActive ?? false) _autoSaveTimer!.cancel();
    // 停止输入 1 秒后自动静默保存
    _autoSaveTimer = Timer(const Duration(seconds: 1), () {
      _saveFile(silent: true);
    });
  }

  Future<void> _saveFile({bool silent = false}) async {
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

      await widget.file.writeAsString('$newFrontmatter$newBody');

      // 只有在非静默模式（或者想手动弹出提示时）才显示 SnackBar
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功！'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }
  // ====================================================

  void _showInfoDialog() {
    int bytes = widget.file.lengthSync();
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

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _bodyController.removeListener(_triggerAutoSave);
    
    // 退出页面时，强行做最后一次静默保存
    _saveFile(silent: true);
    
    _bodyController.dispose();
    for (var prop in _customProps) { prop.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String fileName = widget.file.path.split('/').last.replaceAll('.md', '');

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: const TextStyle(fontSize: 16)),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: Icon(_isPreviewMode ? Icons.edit : Icons.preview),
            onPressed: () => setState(() => _isPreviewMode = !(_isPreviewMode)),
          ),
          // 注意：彻底移除了保存按钮 💾
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'add_prop') {
                setState(() => _customProps.add(_PropEntry('', '')));
                _triggerAutoSave(); // 添加属性框也触发自动保存
              } else if (value == 'info') {
                _showInfoDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'add_prop',
                child: Row(children: [Icon(Icons.add_box_outlined, size: 20, color: Colors.grey), SizedBox(width: 8), Text('添加属性')]),
              ),
              const PopupMenuItem<String>(
                value: 'info',
                child: Row(children: [Icon(Icons.info_outline, size: 20, color: Colors.grey), SizedBox(width: 8), Text('详细信息')]),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isPreviewMode
              // ======= 预览模式 =======
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Markdown(
                    data: _bodyController.text, 
                    selectable: true
                  ),
                )
              // ======= 编辑模式 =======
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ==== 这里彻底移除了原来显示文件名的只读大标题 Text(fileName) ====
                      
                      // 自定义属性区域
                      if (_customProps.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: Colors.grey.shade300, width: 3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._customProps.map((prop) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 80,
                                        child: TextField(
                                          controller: prop.keyCtrl,
                                          onChanged: (v) => _triggerAutoSave(), // 修改属性时触发自动保存
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                                          decoration: const InputDecoration.collapsed(hintText: '属性名'),
                                        ),
                                      ),
                                      const Text(':  ', style: TextStyle(color: Colors.grey)),
                                      Expanded(
                                        child: TextField(
                                          controller: prop.valCtrl,
                                          onChanged: (v) => _triggerAutoSave(), // 修改属性时触发自动保存
                                          style: const TextStyle(fontSize: 14),
                                          decoration: const InputDecoration.collapsed(hintText: '空'),
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          setState(() { _customProps.remove(prop); prop.dispose(); });
                                          _triggerAutoSave(); // 删除属性也触发自动保存
                                        },
                                        child: const Icon(Icons.close, size: 16, color: Colors.grey),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: () {
                                  setState(() => _customProps.add(_PropEntry('', '')));
                                  _triggerAutoSave();
                                },
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

                      // 正文区域
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
    );
  }
}