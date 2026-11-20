import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

// ⚠️ We are using 127.0.0.1 because both Flask and the Flutter app are on the same phone.
// If you ever move Flask to a PC, change this to your PC's IP (e.g., 'http://192.168.1.100:5000').
const String backendBaseUrl = 'http://127.0.0.1:5000';

void main() {
  runApp(const VideoFeedApp());
}

class VideoFeedApp extends StatelessWidget {
  const VideoFeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Feed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const VideoFeedScreen(),
    );
  }
}

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final List<Map<String, String>> _videos = []; // [{name, url}]
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchVideos();
  }

  // ---------------- API: list ----------------
  Future<void> _fetchVideos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse('$backendBaseUrl/videos'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as List<dynamic>;
        setState(() {
          _videos
            ..clear()
            ..addAll(data.map((e) => {
                  'name': e['name'] as String,
                  'url': e['url'] as String,
                }));
        });
      } else {
        setState(() => _error = 'Failed to load videos (${res.statusCode})');
      }
    } catch (e) {
      setState(() => _error = 'Cannot reach backend: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- API: upload ----------------
  Future<void> _uploadVideo() async {
    final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    _showLoadingDialog('Uploading...');
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$backendBaseUrl/upload'),
      );
      req.files.add(await http.MultipartFile.fromPath('video', picked.path));

      final streamed = await req.send().timeout(const Duration(minutes: 5));
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 201) {
        await _fetchVideos();
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      } else {
        _showSnack('Upload failed: ${res.body}');
      }
    } catch (e) {
      _showSnack('Upload error: $e');
    } finally {
      _dismissDialog();
    }
  }

  // ---------------- API: delete ----------------
  Future<void> _deleteVideo(int index) async {
    if (index < 0 || index >= _videos.length) return;
    final name = _videos[index]['name']!;

    _showLoadingDialog('Deleting...');
    try {
      final res = await http
          .delete(Uri.parse('$backendBaseUrl/delete/$name'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        await _fetchVideos();
        if (_videos.isNotEmpty && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      } else {
        _showSnack('Delete failed: ${res.statusCode}');
      }
    } catch (e) {
      _showSnack('Delete error: $e');
    } finally {
      _dismissDialog();
    }
  }

  // ---------------- UI helpers ----------------
  void _showLoadingDialog(String text) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 12),
            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _dismissDialog() {
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showOptions(int currentIndex) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload Video'),
              onTap: () {
                Navigator.pop(ctx);
                _uploadVideo();
              },
            ),
            ListTile(
              enabled: _videos.isNotEmpty,
              leading:
                  const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text(
                'Delete Current Video',
                style: TextStyle(color: Colors.redAccent),
              ),
              onTap: _videos.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _deleteVideo(currentIndex);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh Feed'),
              onTap: () {
                Navigator.pop(ctx);
                _fetchVideos();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final idx = _pageController.hasClients
              ? (_pageController.page ?? 0).round()
              : 0;
          _showOptions(idx);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchVideos,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_videos.isEmpty) {
      return const Center(
        child: Text(
          'No videos yet.\nTap + to upload one.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: _videos.length,
      itemBuilder: (context, index) {
        return VideoPlayerItem(
          key: ValueKey(_videos[index]['url']),
          videoUrl: _videos[index]['url']!,
          onDelete: () => _deleteVideo(index),
        );
      },
    );
  }
}

// ================================================================
// Individual video player (full-screen, tap to pause, loop)
// ================================================================
class VideoPlayerItem extends StatefulWidget {
  final String videoUrl;
  final VoidCallback onDelete;

  const VideoPlayerItem({
    super.key,
    required this.videoUrl,
    required this.onDelete,
  });

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
    _controller.initialize().then((_) {
      if (!mounted) return;
      _controller
        ..setLooping(true)
        ..setVolume(1.0)
        ..play();
      setState(() => _initialized = true);
    }).catchError((e) {
      if (mounted) setState(() => _hasError = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return const Center(
        child: Text('Failed to load video',
            style: TextStyle(color: Colors.white)),
      );
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final size = _controller.value.size;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen video (cover)
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(_controller),
          ),
        ),

        // Tap to pause/play
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          }),
          child: Container(color: Colors.transparent),
        ),

        // Play icon overlay when paused
        if (!_controller.value.isPlaying)
          const Center(
            child: Icon(Icons.play_arrow, size: 96, color: Colors.white70),
          ),

        // Delete button (bottom-right of the video)
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.small(
            heroTag: null,
            backgroundColor: Colors.black54,
            onPressed: widget.onDelete,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
