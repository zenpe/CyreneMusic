import 'package:flutter/cupertino.dart';

/// Local filtering only: opening a directory never requests the backend.
class LxSourceFilters extends StatefulWidget {
  final List<String> directories;
  final String? selectedDirectory;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onDirectoryChanged;

  const LxSourceFilters({
    super.key,
    required this.directories,
    required this.selectedDirectory,
    required this.onQueryChanged,
    required this.onDirectoryChanged,
  });

  @override
  State<LxSourceFilters> createState() => _LxSourceFiltersState();
}

class _LxSourceFiltersState extends State<LxSourceFilters> {
  bool _open = false;
  String _directoryQuery = '';
  final Set<String> _expanded = {};

  void _select(String? directory) {
    widget.onDirectoryChanged(directory);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final query = _directoryQuery.trim().toLowerCase();
    final visible = widget.directories.where((path) {
      if (query.isNotEmpty) return path.toLowerCase().contains(query);
      final parts = path.split('/');
      for (var i = 1; i < parts.length; i++) {
        if (!_expanded.contains(parts.take(i).join('/'))) return false;
      }
      return true;
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoSearchTextField(
          placeholder: '搜索音源名称或目录',
          onChanged: widget.onQueryChanged,
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.centerLeft,
          onPressed: () => setState(() {
            _open = !_open;
            _directoryQuery = '';
            final parts = widget.selectedDirectory?.split('/') ?? [];
            for (var i = 1; i < parts.length; i++) {
              _expanded.add(parts.take(i).join('/'));
            }
          }),
          child: Text(
            '目录：${widget.selectedDirectory == null
                ? '全部音源'
                : widget.selectedDirectory!.isEmpty
                ? '根目录'
                : widget.selectedDirectory} ${_open ? '▴' : '▾'}',
          ),
        ),
        if (_open) ...[
          CupertinoSearchTextField(
            placeholder: '查找目录（包含子目录）',
            onChanged: (value) => setState(() => _directoryQuery = value),
          ),
          SizedBox(
            height: 240,
            child: ListView(
              children: [
                CupertinoButton(
                  onPressed: () => _select(null),
                  child: const Text('全部音源'),
                ),
                CupertinoButton(
                  onPressed: () => _select(''),
                  child: const Text('根目录（仅根目录文件）'),
                ),
                for (final path in visible)
                  Padding(
                    padding: EdgeInsets.only(
                      left: query.isEmpty
                          ? (path.split('/').length - 1).clamp(0, 5) * 12.0
                          : 0,
                    ),
                    child: Row(
                      children: [
                        if (widget.directories.any(
                          (other) => other.startsWith('$path/'),
                        ))
                          CupertinoButton(
                            padding: const EdgeInsets.all(8),
                            onPressed: () => setState(() {
                              if (!_expanded.add(path)) _expanded.remove(path);
                            }),
                            child: Icon(
                              _expanded.contains(path)
                                  ? CupertinoIcons.chevron_down
                                  : CupertinoIcons.chevron_right,
                              size: 16,
                            ),
                          )
                        else
                          const SizedBox(width: 44),
                        Expanded(
                          child: CupertinoButton(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            onPressed: () => _select(path),
                            child: Text(
                              query.isEmpty ? path.split('/').last : path,
                            ),
                          ),
                        ),
                        if (widget.selectedDirectory == path)
                          const Icon(CupertinoIcons.check_mark, size: 16),
                      ],
                    ),
                  ),
                if (query.isNotEmpty && visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('没有匹配的目录'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
