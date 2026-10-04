import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Takes one or more photos (or imports them from the gallery) and returns
/// their file paths.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  final _shots = <String>[];
  bool _taking = false;
  FlashMode _flash = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      setState(() => _controller = null);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.max,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      await controller.setFlashMode(_flash);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Camera permission denied. You can still import images from the gallery.'
          : 'Camera error: ${e.description}');
    } on StateError {
      setState(() => _error = 'No camera found.');
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (controller == null || _taking) return;
    setState(() => _taking = true);
    try {
      final file = await controller.takePicture();
      setState(() => _shots.add(file.path));
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Capture failed: ${e.description}')));
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  Future<void> _importFromGallery() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty || !mounted) return;
    Navigator.pop(context, [..._shots, ...files.map((f) => f.path)]);
  }

  Future<void> _toggleFlash() async {
    final next = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _controller?.setFlashMode(next);
    setState(() => _flash = next);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan'),
        actions: [
          if (controller != null)
            IconButton(
              tooltip: 'Flash',
              icon: Icon(_flash == FlashMode.off ? Icons.flash_off : Icons.flash_on),
              onPressed: _toggleFlash,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70)),
                    )
                  : controller == null
                      ? const CircularProgressIndicator()
                      : CameraPreview(controller),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Import from gallery',
                    iconSize: 32,
                    color: Colors.white,
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: _importFromGallery,
                  ),
                  _ShutterButton(
                    busy: _taking,
                    onPressed: controller == null ? null : _takePicture,
                  ),
                  _DoneButton(
                    shots: _shots,
                    onPressed: _shots.isEmpty ? null : () => Navigator.pop(context, _shots),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        padding: const EdgeInsets.all(4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null || busy ? Colors.white38 : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Thumbnail of the last shot with a page counter; tapping finishes capture.
class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.shots, required this.onPressed});
  final List<String> shots;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (shots.isEmpty) return const SizedBox(width: 56, height: 56);
    return GestureDetector(
      onTap: onPressed,
      child: Badge(
        label: Text('${shots.length}'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(File(shots.last),
              width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 160),
        ),
      ),
    );
  }
}
