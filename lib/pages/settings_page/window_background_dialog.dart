import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:file_picker/file_picker.dart';
import '../../services/window_background_service.dart';

/// 窗口背景设置对话框
class WindowBackgroundDialog extends StatefulWidget {
  final VoidCallback onChanged;

  const WindowBackgroundDialog({super.key, required this.onChanged});

  @override
  State<WindowBackgroundDialog> createState() => _WindowBackgroundDialogState();
}

class _WindowBackgroundDialogState extends State<WindowBackgroundDialog> {
  @override
  Widget build(BuildContext context) {
    final service = WindowBackgroundService();

    return fluent_ui.ContentDialog(
      title: Row(
        children: [
          const Icon(fluent_ui.FluentIcons.picture_library),
          const SizedBox(width: 8),
          const Text('窗口背景设置'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 启用开关
            Row(
              children: [
                const Expanded(child: Text('启用窗口背景')),
                fluent_ui.ToggleSwitch(
                  checked: service.enabled,
                  onChanged: (value) async {
                    await service.setEnabled(value);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Text(
              '为整个窗口设置背景图片或视频（独立于播放器背景）',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),

            if (service.enabled) ...[
              const SizedBox(height: 16),
              const fluent_ui.Divider(),
              const SizedBox(height: 16),

              // 媒体文件选择
              Row(
                children: [
                  Expanded(
                    child: fluent_ui.FilledButton(
                      onPressed: _selectBackgroundImage,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            service.isVideo
                                ? fluent_ui.FluentIcons.video
                                : fluent_ui.FluentIcons.photo_collection,
                            size: 16
                          ),
                          const SizedBox(width: 8),
                          Text(service.mediaPath != null
                              ? (service.isVideo ? '更换视频' : '更换图片')
                              : '选择图片/视频'),
                        ],
                      ),
                    ),
                  ),
                  if (service.mediaPath != null) ...[
                    const SizedBox(width: 8),
                    fluent_ui.IconButton(
                      icon: const Icon(fluent_ui.FluentIcons.clear),
                      onPressed: () async {
                        await service.clearMedia();
                        setState(() {});
                        widget.onChanged();
                      },
                    ),
                  ],
                ],
              ),

              if (service.mediaPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  '当前${service.isVideo ? '视频' : '图片'}: ${service.mediaPath!.split(Platform.pathSeparator).last}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 16),

              // 模糊程度
              Text('模糊程度: ${service.blurAmount.toStringAsFixed(0)}'),
              const SizedBox(height: 8),
              fluent_ui.Slider(
                value: service.blurAmount,
                min: 0,
                max: 50,
                divisions: 50,
                label: service.blurAmount.toStringAsFixed(0),
                onChanged: (value) async {
                  await service.setBlurAmount(value);
                  setState(() {});
                  widget.onChanged();
                },
              ),
              const Text(
                '0 = 清晰，50 = 最模糊',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),

              const SizedBox(height: 16),

              // 不透明度
              Text('不透明度: ${(service.opacity * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 8),
              fluent_ui.Slider(
                value: service.opacity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                label: '${(service.opacity * 100).toStringAsFixed(0)}%',
                onChanged: (value) async {
                  await service.setOpacity(value);
                  setState(() {});
                  widget.onChanged();
                },
              ),
              const Text(
                '0% = 完全透明，100% = 完全不透明',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),

              const SizedBox(height: 16),

              // 预览
              if (service.hasValidMedia) ...[
                const Text('预览', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: service.isVideo
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  fluent_ui.FluentIcons.video,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '视频背景\n${service.mediaPath!.split(Platform.pathSeparator).last}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                service.getMediaFile()!,
                                fit: BoxFit.cover,
                              ),
                              BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: service.blurAmount,
                                  sigmaY: service.blurAmount,
                                ),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 1 - service.opacity),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        fluent_ui.Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  /// 选择背景媒体文件（图片或视频）
  Future<void> _selectBackgroundImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'],
      dialogTitle: '选择窗口背景（图片或视频）',
    );

    if (result != null && result.files.single.path != null) {
      final mediaPath = result.files.single.path!;
      final service = WindowBackgroundService();

      await service.setMediaPath(mediaPath);
      setState(() {});
      widget.onChanged();

      if (mounted) {
        final isVideo = service.isVideoFile(mediaPath);
        fluent_ui.displayInfoBar(
          context,
          builder: (context, close) => fluent_ui.InfoBar(
            title: Text(isVideo ? '背景视频已设置' : '背景图片已设置'),
            severity: fluent_ui.InfoBarSeverity.success,
          ),
        );
      }
    }
  }
}
