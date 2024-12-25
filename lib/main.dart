// main.dart
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:external_path/external_path.dart';
import 'dart:io';

void main() {
  runApp(const MusicPlayerApp());
}

class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Player',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const MusicPlayerScreen(),
    );
  }
}

class Song {
  final String title;
  final String path;
  final String? artist;
  final Duration? duration;

  Song({required this.title, required this.path, this.artist, this.duration});
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({Key? key}) : super(key: key);

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _player = AudioPlayer();
  List<Song> _songs = [];
  bool _isScanning = false;
  Song? _currentSong;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _setupAudioSession();
    _setupAudioPlayer();
    _initializeMusic();
  }

  Future<void> _initializeMusic() async {
    await _requestPermissions();
    await _scanMusic();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.audio.request();
    await Permission.manageExternalStorage.request();
  }

  Future<void> _scanMusic() async {
    setState(() => _isScanning = true);
    try {
      final paths = await _getMusicPaths();
      final songs = await _findMusicFiles(paths);
      setState(() => _songs = songs);
    } catch (e) {
      debugPrint('Error scanning music: $e');
    } finally {
      setState(() => _isScanning = false);
    }
  }

  // Add this function to _MusicPlayerScreenState class
  Future<List<String>> _getMusicPaths() async {
    final paths = <String>[];

    try {
      // Get root storage path
      final root = await ExternalPath.getExternalStorageDirectories();
      paths.add(root[0]); // Add root directory to scan entire device
    } catch (e) {
      debugPrint('Error getting paths: $e');
    }

    return paths;
  }

// Update _findMusicFiles function
  Future<List<Song>> _findMusicFiles(List<String> paths) async {
    final songs = <Song>[];
    final audioExtensions = ['.mp3'];

    for (final path in paths) {
      try {
        final dir = Directory(path);
        if (!await dir.exists()) continue;

        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            if (entity.path.contains("AUD-") ||
                entity.path.contains("Slack") ||
                entity.path.toLowerCase().contains("ringtone")) {
              continue;
            }
            final lowercase = entity.path.toLowerCase();
            if (audioExtensions.any((ext) => lowercase.endsWith(ext))) {
              try {
                // Get file metadata
                final file = File(entity.path);
                final stats = await file.stat();

                if (stats.size > 0) {
                  // Skip empty files
                  songs.add(Song(
                    title: _getFileName(entity.path),
                    path: entity.path,
                    artist: 'Unknown Artist',
                  ));
                }
              } catch (e) {
                debugPrint('Error reading file: ${entity.path} - $e');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning directory: $path - $e');
        continue; // Continue with next directory if one fails
      }
    }

    return songs;
  }

  String _getFileName(String path) {
    final name = path.split('/').last;
    return name.substring(0, name.lastIndexOf('.'));
  }

  void _setupAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
      ));
    } catch (e) {
      debugPrint('Error setting up audio session: $e');
    }
  }

  void _setupAudioPlayer() {
    _player.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });

    _player.durationStream.listen((duration) {
      setState(() => _duration = duration ?? Duration.zero);
    });

    _player.positionStream.listen((position) {
      setState(() => _position = position);
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  Future<void> _playSong(Song song, int index) async {
    try {
      await _player.setFilePath(song.path);
      await _player.play();
      setState(() {
        _currentSong = song;
        _currentIndex = index;
      });
    } catch (e) {
      debugPrint('Error playing song: $e');
    }
  }

  void _playNext() {
    if (_currentIndex < _songs.length - 1) {
      _playSong(_songs[_currentIndex + 1], _currentIndex + 1);
    }
  }

  void _playPrevious() {
    if (_currentIndex > 0) {
      _playSong(_songs[_currentIndex - 1], _currentIndex - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanMusic,
          ),
        ],
      ),
      body: _isScanning
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning for music files...'),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _songs.isEmpty
                      ? const Center(
                          child: Text('No music files found'),
                        )
                      : ListView.builder(
                          itemCount: _songs.length,
                          itemBuilder: (context, index) {
                            final song = _songs[index];
                            return ListTile(
                              leading: const Icon(Icons.music_note),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                song.artist ?? 'Unknown Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _playSong(song, index),
                              trailing: _currentSong?.path == song.path
                                  ? const Icon(Icons.play_arrow)
                                  : null,
                            );
                          },
                        ),
                ),
                if (_currentSong != null) _buildPlayerControls(),
              ],
            ),
    );
  }

  Widget _buildPlayerControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _currentSong?.title ?? '',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _currentSong?.artist ?? 'Unknown Artist',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Slider(
            value: _position.inSeconds.toDouble(),
            min: 0,
            max: _duration.inSeconds.toDouble(),
            onChanged: (value) {
              final position = Duration(seconds: value.toInt());
              _player.seek(position);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(_position)),
                Text(_formatDuration(_duration)),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: _playPrevious,
              ),
              IconButton(
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () {
                  if (_isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: _playNext,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
