import 'dart:io';

class NoteUtil {
  static String generateInitialContent() {
    String now = DateTime.now().toIso8601String().split('.')[0];
    return '''---
created: $now
modified: $now
synced: 
---

''';
  }

  static Map<String, String> parseFrontmatter(String content) {
    Map<String, String> props = {};
    if (content.startsWith('---\n') || content.startsWith('---\r\n')) {
      int endIndex = content.indexOf('---', 3);
      if (endIndex != -1) {
        String fm = content.substring(3, endIndex);
        List<String> lines = fm.split('\n');
        for (String line in lines) {
          if (line.trim().isEmpty) continue;
          int colonIdx = line.indexOf(':');
          if (colonIdx != -1) {
            String key = line.substring(0, colonIdx).trim();
            String val = line.substring(colonIdx + 1).trim();
            props[key] = val;
          }
        }
      }
    }
    return props;
  }

  static String buildFrontmatter(Map<String, String> props) {
    StringBuffer sb = StringBuffer();
    sb.writeln('---');
    
    List<String> timeKeys = ['created', 'modified', 'synced'];
    for (String tk in timeKeys) {
      if (props.containsKey(tk)) {
        sb.writeln('$tk: ${props[tk]}');
      } else {
        sb.writeln('$tk: ');
      }
    }
    
    props.forEach((k, v) {
      if (!timeKeys.contains(k)) {
        sb.writeln('$k: $v');
      }
    });
    
    sb.writeln('---');
    return sb.toString();
  }

  static String extractBody(String content) {
    if (content.startsWith('---\n') || content.startsWith('---\r\n')) {
      int endIndex = content.indexOf('---', 3);
      if (endIndex != -1) {
        return content.substring(endIndex + 3).trimLeft();
      }
    }
    return content;
  }

  static DateTime? getYamlTime(String content, String key) {
    Map<String, String> props = parseFrontmatter(content);
    String? val = props[key];
    if (val != null && val.isNotEmpty) {
      return DateTime.tryParse(val);
    }
    return null;
  }

  // ==== 新增：为文件更新同步时间 ====
  static Future<void> updateFileSyncedTime(File file) async {
    try {
      String content = await file.readAsString();
      Map<String, String> props = parseFrontmatter(content);
      props['synced'] = DateTime.now().toIso8601String().split('.')[0];
      
      String newFrontmatter = buildFrontmatter(props);
      String body = extractBody(content);
      
      await file.writeAsString('$newFrontmatter$body');
    } catch (e) {
      // 忽略读取或写入错误
    }
  }
}