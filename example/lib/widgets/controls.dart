import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../exts.dart';

class ControlsWidget extends StatefulWidget {
  //
  final Room room;
  final LocalParticipant participant;

  const ControlsWidget(
    this.room,
    this.participant, {
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _ControlsWidgetState();
}

class _ControlsWidgetState extends State<ControlsWidget> {
  //
  CameraPosition position = CameraPosition.front;

  List<MediaDevice>? _audioInputs;
  List<MediaDevice>? _audioOutputs;
  List<MediaDevice>? _videoInputs;

  StreamSubscription? _subscription;

  bool _speakerphoneOn = Hardware.instance.speakerOn ?? false;
  
  // Video bitrate control (in kbps)
  double _videoBitrate = 1700; // Default 1.7 Mbps
  double _audioBitrate = 48; // Default 48 kbps
  bool _showBitrateControls = false;
  
  // Audio quality presets
  String _selectedAudioPreset = 'Music';
  final Map<String, int> _audioPresets = {
    'Telephone': 12, // AudioPreset.telephone
    'Speech': 24,    // AudioPreset.speech
    'Music': 48,     // AudioPreset.music
    'Music Stereo': 64,  // AudioPreset.musicStereo
    'High Quality': 96,  // AudioPreset.musicHighQuality
    'HQ Stereo': 128,    // AudioPreset.musicHighQualityStereo
  };
  
  // Resolution control
  String _selectedResolution = '720p';
  final Map<String, VideoDimensions> _resolutionOptions = {
    '360p': VideoDimensionsPresets.h360_169,
    '480p': VideoDimensionsPresets.h480_43,
    '720p': VideoDimensionsPresets.h720_169,
    '1080p': VideoDimensionsPresets.h1080_169,
    '1440p': VideoDimensionsPresets.h1440_169,
  };
  
  // Frame rate control
  int _selectedFrameRate = 30;
  final List<int> _frameRateOptions = [15, 24, 30, 60];
  
  // Simulcast control
  bool _simulcastEnabled = true;
  String _selectedSimulcastLayers = 'Auto';
  final Map<String, List<VideoParameters>?> _simulcastOptions = {
    'Disabled': null,
    'Auto': [], // Use default layers
    'Low+Medium': [
      VideoParametersPresets.h360_169,
      VideoParametersPresets.h540_169,
    ],
    'Medium+High': [
      VideoParametersPresets.h540_169,
      VideoParametersPresets.h720_169,
    ],
    'All Layers': [
      VideoParametersPresets.h360_169,
      VideoParametersPresets.h540_169,
      VideoParametersPresets.h720_169,
    ],
  };
  
  // Codec control
  String _selectedCodec = 'H.264';
  final List<String> _codecOptions = ['H.264', 'VP8', 'VP9', 'AV1'];
  
  // Network status control
  String _networkStatus = 'Unknown';
  double _networkQuality = 0.0; // 0.0 to 1.0
  bool _adaptiveStream = true;
  double _currentBandwidth = 0.0; // in kbps
  int _packetsLost = 0;
  double _rtt = 0.0; // Round trip time in ms
  bool _showNetworkStats = false;

  @override
  void initState() {
    super.initState();
    participant.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream
        .listen((List<MediaDevice> devices) {
      _loadDevices(devices);
    });
    Hardware.instance.enumerateDevices().then(_loadDevices);
    
    // Start network monitoring
    _startNetworkMonitoring();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    participant.removeListener(_onChange);
    super.dispose();
  }

  LocalParticipant get participant => widget.participant;

  void _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();
    setState(() {});
  }

  void _onChange() {
    // trigger refresh
    setState(() {});
  }

  void _unpublishAll() async {
    final result = await context.showUnPublishDialog();
    if (result == true) await participant.unpublishAllTracks();
  }

  bool get isMuted => participant.isMuted;

  void _disableAudio() async {
    await participant.setMicrophoneEnabled(false);
  }

  Future<void> _enableAudio() async {
    await participant.setMicrophoneEnabled(true);
  }

  void _disableVideo() async {
    await participant.setCameraEnabled(false);
  }

  void _enableVideo() async {
    await participant.setCameraEnabled(true);
  }

  void _selectAudioOutput(MediaDevice device) async {
    await widget.room.setAudioOutputDevice(device);
    setState(() {});
  }

  void _selectAudioInput(MediaDevice device) async {
    await widget.room.setAudioInputDevice(device);
    setState(() {});
  }

  void _selectVideoInput(MediaDevice device) async {
    await widget.room.setVideoInputDevice(device);
    setState(() {});
  }

  void _setSpeakerphoneOn() async {
    _speakerphoneOn = !_speakerphoneOn;
    await widget.room.setSpeakerOn(_speakerphoneOn, forceSpeakerOutput: false);
    setState(() {});
  }

  void _toggleCamera() async {
    final track = participant.videoTrackPublications.firstOrNull?.track;
    if (track == null) return;

    try {
      final newPosition = position.switched();
      await track.setCameraPosition(newPosition);
      setState(() {
        position = newPosition;
      });
    } catch (error) {
      print('could not restart track: $error');
      return;
    }
  }

  void _enableScreenShare() async {
    if (lkPlatformIsDesktop()) {
      try {
        final source = await showDialog<DesktopCapturerSource>(
          context: context,
          builder: (context) => ScreenSelectDialog(),
        );
        if (source == null) {
          print('cancelled screenshare');
          return;
        }
        print('DesktopCapturerSource: ${source.id}');
        var track = await LocalVideoTrack.createScreenShareTrack(
          ScreenShareCaptureOptions(
            sourceId: source.id,
            maxFrameRate: 15.0,
          ),
        );
        await participant.publishVideoTrack(track);
      } catch (e) {
        print('could not publish video: $e');
      }
      return;
    }
    if (lkPlatformIs(PlatformType.android)) {
      // Android specific
      bool hasCapturePermission = await Helper.requestCapturePermission();
      if (!hasCapturePermission) {
        return;
      }

      requestBackgroundPermission([bool isRetry = false]) async {
        // Required for android screenshare.
        try {
          bool hasPermissions = await FlutterBackground.hasPermissions;
          if (!isRetry) {
            const androidConfig = FlutterBackgroundAndroidConfig(
              notificationTitle: 'Screen Sharing',
              notificationText: 'LiveKit Example is sharing the screen.',
              notificationImportance: AndroidNotificationImportance.normal,
              notificationIcon: AndroidResource(
                  name: 'livekit_ic_launcher', defType: 'mipmap'),
            );
            hasPermissions = await FlutterBackground.initialize(
                androidConfig: androidConfig);
          }
          if (hasPermissions &&
              !FlutterBackground.isBackgroundExecutionEnabled) {
            await FlutterBackground.enableBackgroundExecution();
          }
        } catch (e) {
          if (!isRetry) {
            return await Future<void>.delayed(const Duration(seconds: 1),
                () => requestBackgroundPermission(true));
          }
          print('could not publish video: $e');
        }
      }

      await requestBackgroundPermission();
    }

    if (lkPlatformIsWebMobile()) {
      await context
          .showErrorDialog('Screen share is not supported on mobile web');
      return;
    }
    await participant.setScreenShareEnabled(true, captureScreenAudio: true);
  }

  void _disableScreenShare() async {
    await participant.setScreenShareEnabled(false);
    if (lkPlatformIs(PlatformType.android)) {
      // Android specific
      try {
        //   await FlutterBackground.disableBackgroundExecution();
      } catch (error) {
        print('error disabling screen share: $error');
      }
    }
  }

  void _onTapDisconnect() async {
    final result = await context.showDisconnectDialog();
    if (result == true) await widget.room.disconnect();
  }

  void _onTapUpdateSubscribePermission() async {
    final result = await context.showSubscribePermissionDialog();
    if (result != null) {
      try {
        widget.room.localParticipant?.setTrackSubscriptionPermissions(
          allParticipantsAllowed: result,
        );
      } catch (error) {
        await context.showErrorDialog(error);
      }
    }
  }

  void _onTapSimulateScenario() async {
    final result = await context.showSimulateScenarioDialog();
    if (result != null) {
      print('${result}');

      if (SimulateScenarioResult.e2eeKeyRatchet == result) {
        await widget.room.e2eeManager?.ratchetKey();
      }

      if (SimulateScenarioResult.participantMetadata == result) {
        widget.room.localParticipant?.setMetadata(
            'new metadata ${widget.room.localParticipant?.identity}');
      }

      if (SimulateScenarioResult.participantName == result) {
        widget.room.localParticipant
            ?.setName('new name for ${widget.room.localParticipant?.identity}');
      }

      await widget.room.sendSimulateScenario(
        speakerUpdate:
            result == SimulateScenarioResult.speakerUpdate ? 3 : null,
        signalReconnect:
            result == SimulateScenarioResult.signalReconnect ? true : null,
        fullReconnect:
            result == SimulateScenarioResult.fullReconnect ? true : null,
        nodeFailure: result == SimulateScenarioResult.nodeFailure ? true : null,
        migration: result == SimulateScenarioResult.migration ? true : null,
        serverLeave: result == SimulateScenarioResult.serverLeave ? true : null,
        switchCandidate:
            result == SimulateScenarioResult.switchCandidate ? true : null,
      );
    }
  }

  void _onTapSendData() async {
    final result = await context.showSendDataDialog();
    if (result == true) {
      await widget.participant.publishData(
        utf8.encode('This is a sample data message'),
      );
    }
  }

  void _updateVideoBitrate(double bitrate) async {
    setState(() {
      _videoBitrate = bitrate;
    });
    
    // TODO: Implement runtime bitrate adjustment
    // Currently LiveKit Flutter SDK doesn't support runtime bitrate changes
    // This UI will be ready for when the API is available
    print('Video bitrate set to: ${bitrate.round()} kbps');
  }

  void _updateAudioBitrate(double bitrate) async {
    setState(() {
      _audioBitrate = bitrate;
    });
    
    // TODO: Implement runtime bitrate adjustment
    // Currently LiveKit Flutter SDK doesn't support runtime bitrate changes
    // This UI will be ready for when the API is available
    print('Audio bitrate set to: ${bitrate.round()} kbps');
  }

  void _changeAudioPreset(String preset) async {
    if (_selectedAudioPreset == preset) return;
    
    final bitrate = _audioPresets[preset]!;
    setState(() {
      _selectedAudioPreset = preset;
      _audioBitrate = bitrate.toDouble();
    });
    
    final audioTrack = participant.audioTrackPublications.firstOrNull?.track as LocalAudioTrack?;
    if (audioTrack != null) {
      try {
        // Stop current track
        await audioTrack.stop();
        
        // Create new track with new audio settings
        final newTrack = await LocalAudioTrack.create(
          AudioCaptureOptions(),
        );
        
        // Replace the track
        await participant.publishAudioTrack(newTrack);
        print('Audio preset changed to: $preset (${bitrate} kbps)');
      } catch (e) {
        print('Failed to change audio preset: $e');
      }
    }
  }

  void _changeSimulcastLayers(String layerOption) async {
    if (_selectedSimulcastLayers == layerOption) return;
    
    setState(() {
      _selectedSimulcastLayers = layerOption;
      _simulcastEnabled = layerOption != 'Disabled';
    });
    
    final videoTrack = participant.videoTrackPublications.firstOrNull?.track as LocalVideoTrack?;
    if (videoTrack != null) {
      try {
        // Stop current track
        await videoTrack.stop();
        
        // Create new track with new simulcast settings
        final dimensions = _resolutionOptions[_selectedResolution]!;
        final simulcastLayers = _simulcastOptions[layerOption];
        
        final newTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            params: VideoParameters(
              dimensions: dimensions,
              encoding: VideoEncoding(
                maxBitrate: (_videoBitrate * 1000).round(),
                maxFramerate: _selectedFrameRate,
              ),
            ),
          ),
        );
        
        // Replace the track with simulcast options
        await participant.publishVideoTrack(
          newTrack,
          publishOptions: VideoPublishOptions(
            simulcast: _simulcastEnabled,
            videoSimulcastLayers: simulcastLayers ?? [],
            videoCodec: _codecToApiString(_selectedCodec),
          ),
        );
        
        print('Simulcast layers changed to: $layerOption (enabled: $_simulcastEnabled)');
      } catch (e) {
        print('Failed to change simulcast layers: $e');
      }
    }
  }

  void _changeResolution(String resolution) async {
    if (_selectedResolution == resolution) return;
    
    setState(() {
      _selectedResolution = resolution;
    });
    
    final videoTrack = participant.videoTrackPublications.firstOrNull?.track as LocalVideoTrack?;
    if (videoTrack != null) {
      try {
        // Stop current track
        await videoTrack.stop();
        
        // Create new track with new resolution
        final dimensions = _resolutionOptions[resolution]!;
        final newTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            params: VideoParameters(
              dimensions: dimensions,
              encoding: VideoEncoding(
                maxBitrate: (_videoBitrate * 1000).round(),
                maxFramerate: _selectedFrameRate,
              ),
            ),
          ),
        );
        
        // Replace the track with current simulcast settings
        final simulcastLayers = _simulcastOptions[_selectedSimulcastLayers];
        await participant.publishVideoTrack(
          newTrack,
          publishOptions: VideoPublishOptions(
            simulcast: _simulcastEnabled,
            videoSimulcastLayers: simulcastLayers ?? [],
            videoCodec: _codecToApiString(_selectedCodec),
          ),
        );
        print('Resolution changed to: $resolution (${dimensions.width}x${dimensions.height})');
      } catch (e) {
        print('Failed to change resolution: $e');
      }
    }
  }

  void _changeFrameRate(int frameRate) async {
    if (_selectedFrameRate == frameRate) return;
    
    setState(() {
      _selectedFrameRate = frameRate;
    });
    
    final videoTrack = participant.videoTrackPublications.firstOrNull?.track as LocalVideoTrack?;
    if (videoTrack != null) {
      try {
        // Stop current track
        await videoTrack.stop();
        
        // Create new track with new frame rate
        final dimensions = _resolutionOptions[_selectedResolution]!;
        final newTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            params: VideoParameters(
              dimensions: dimensions,
              encoding: VideoEncoding(
                maxBitrate: (_videoBitrate * 1000).round(),
                maxFramerate: frameRate,
              ),
            ),
          ),
        );
        
        // Replace the track with current simulcast settings
        final simulcastLayers = _simulcastOptions[_selectedSimulcastLayers];
        await participant.publishVideoTrack(
          newTrack,
          publishOptions: VideoPublishOptions(
            simulcast: _simulcastEnabled,
            videoSimulcastLayers: simulcastLayers ?? [],
            videoCodec: _codecToApiString(_selectedCodec),
          ),
        );
        print('Frame rate changed to: ${frameRate} fps');
      } catch (e) {
        print('Failed to change frame rate: $e');
      }
    }
  }

  void _changeCodec(String codec) async {
    if (_selectedCodec == codec) return;
    
    setState(() {
      _selectedCodec = codec;
    });
    
    final videoTrack = participant.videoTrackPublications.firstOrNull?.track as LocalVideoTrack?;
    if (videoTrack != null) {
      try {
        // Stop current track
        await videoTrack.stop();
        
        // Create new track with new codec
        final dimensions = _resolutionOptions[_selectedResolution]!;
        final newTrack = await LocalVideoTrack.createCameraTrack(
          CameraCaptureOptions(
            params: VideoParameters(
              dimensions: dimensions,
              encoding: VideoEncoding(
                maxBitrate: (_videoBitrate * 1000).round(),
                maxFramerate: _selectedFrameRate,
              ),
            ),
          ),
        );
        
        // Replace the track with new codec and current settings
        final simulcastLayers = _simulcastOptions[_selectedSimulcastLayers];
        await participant.publishVideoTrack(
          newTrack,
          publishOptions: VideoPublishOptions(
            simulcast: _simulcastEnabled,
            videoSimulcastLayers: simulcastLayers ?? [],
            videoCodec: _codecToApiString(codec),
          ),
        );
        print('Codec changed to: $codec');
      } catch (e) {
        print('Failed to change codec: $e');
      }
    }
  }
  
  String _codecToApiString(String displayCodec) {
    switch (displayCodec) {
      case 'H.264':
        return 'h264';
      case 'VP8':
        return 'vp8';
      case 'VP9':
        return 'vp9';
      case 'AV1':
        return 'av01';
      default:
        return 'h264';
    }
  }
  
  void _startNetworkMonitoring() {
    // Start periodic network monitoring
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateNetworkStats();
    });
  }
  
  void _updateNetworkStats() async {
    try {
      final videoTrack = participant.videoTrackPublications.firstOrNull?.track as LocalVideoTrack?;
      if (videoTrack != null) {
        final stats = await videoTrack.getSenderStats();
        if (stats.isNotEmpty) {
          final latestStat = stats.first;
          
          setState(() {
            _packetsLost = latestStat.packetsLost?.toInt() ?? 0;
            _rtt = (latestStat.roundTripTime ?? 0.0) * 1000; // Convert to ms
            _currentBandwidth = videoTrack.currentBitrate?.toDouble() ?? 0.0;
            
            // Calculate network quality based on RTT and packet loss
            _networkQuality = _calculateNetworkQuality(_rtt, _packetsLost);
            _networkStatus = _getNetworkStatusString(_networkQuality);
          });
          
          // Auto-adjust quality if adaptive streaming is enabled
          if (_adaptiveStream) {
            _adjustQualityBasedOnNetwork();
          }
        }
      }
    } catch (e) {
      print('Failed to update network stats: $e');
    }
  }
  
  double _calculateNetworkQuality(double rtt, int packetsLost) {
    // Simple network quality calculation
    // Good network: RTT < 50ms, no packet loss = 1.0
    // Poor network: RTT > 300ms, high packet loss = 0.0
    
    double rttScore = 1.0;
    if (rtt > 50) {
      rttScore = math.max(0.0, 1.0 - (rtt - 50) / 250); // Linear decay from 50ms to 300ms
    }
    
    double lossScore = math.max(0.0, 1.0 - (packetsLost / 100.0)); // Penalty for packet loss
    
    return (rttScore + lossScore) / 2.0;
  }
  
  String _getNetworkStatusString(double quality) {
    if (quality >= 0.8) return 'Excellent';
    if (quality >= 0.6) return 'Good';
    if (quality >= 0.4) return 'Fair';
    if (quality >= 0.2) return 'Poor';
    return 'Very Poor';
  }
  
  void _adjustQualityBasedOnNetwork() {
    if (!_adaptiveStream) return;
    
    // Auto-adjust resolution and bitrate based on network quality
    if (_networkQuality < 0.3 && _selectedResolution != '360p') {
      // Very poor network - drop to 360p
      _changeResolution('360p');
    } else if (_networkQuality < 0.5 && _selectedResolution == '1080p') {
      // Poor network - drop from 1080p to 720p
      _changeResolution('720p');
    } else if (_networkQuality > 0.8 && _selectedResolution == '360p') {
      // Excellent network - upgrade from 360p to 720p
      _changeResolution('720p');
    }
    
    // Adjust frame rate based on network quality
    if (_networkQuality < 0.4 && _selectedFrameRate > 15) {
      _changeFrameRate(15);
    } else if (_networkQuality > 0.7 && _selectedFrameRate < 30) {
      _changeFrameRate(30);
    }
  }
  
  void _toggleAdaptiveStream() {
    setState(() {
      _adaptiveStream = !_adaptiveStream;
    });
    print('Adaptive streaming ${_adaptiveStream ? 'enabled' : 'disabled'}');
  }
  
  Color _getNetworkStatusColor() {
    if (_networkQuality >= 0.8) return Colors.green;
    if (_networkQuality >= 0.6) return Colors.yellow;
    if (_networkQuality >= 0.4) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 15,
        horizontal: 15,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Control buttons
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: [
          IconButton(
            onPressed: _unpublishAll,
            icon: const Icon(Icons.cancel),
            tooltip: 'Unpublish all',
          ),
          if (participant.isMicrophoneEnabled())
            if (lkPlatformIs(PlatformType.android))
              IconButton(
                onPressed: _disableAudio,
                icon: const Icon(Icons.mic),
                tooltip: 'mute audio',
              )
            else
              PopupMenuButton<MediaDevice>(
                icon: const Icon(Icons.settings_voice),
                offset: const Offset(0, -90),
                itemBuilder: (BuildContext context) {
                  return [
                    PopupMenuItem<MediaDevice>(
                      value: null,
                      onTap: isMuted ? _enableAudio : _disableAudio,
                      child: const ListTile(
                        leading: Icon(
                          Icons.mic_off,
                          color: Colors.white,
                        ),
                        title: Text('Mute Microphone'),
                      ),
                    ),
                    if (_audioInputs != null)
                      ..._audioInputs!.map((device) {
                        return PopupMenuItem<MediaDevice>(
                          value: device,
                          child: ListTile(
                            leading: (device.deviceId ==
                                    widget.room.selectedAudioInputDeviceId)
                                ? const Icon(
                                    Icons.check_box_outlined,
                                    color: Colors.white,
                                  )
                                : const Icon(
                                    Icons.check_box_outline_blank,
                                    color: Colors.white,
                                  ),
                            title: Text(device.label),
                          ),
                          onTap: () => _selectAudioInput(device),
                        );
                      })
                  ];
                },
              )
          else
            IconButton(
              onPressed: _enableAudio,
              icon: const Icon(Icons.mic_off),
              tooltip: 'un-mute audio',
            ),
          if (!lkPlatformIsMobile())
            PopupMenuButton<MediaDevice>(
              icon: const Icon(Icons.volume_up),
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem<MediaDevice>(
                    value: null,
                    child: ListTile(
                      leading: Icon(
                        Icons.speaker,
                        color: Colors.white,
                      ),
                      title: Text('Select Audio Output'),
                    ),
                  ),
                  if (_audioOutputs != null)
                    ..._audioOutputs!.map((device) {
                      return PopupMenuItem<MediaDevice>(
                        value: device,
                        child: ListTile(
                          leading: (device.deviceId ==
                                  widget.room.selectedAudioOutputDeviceId)
                              ? const Icon(
                                  Icons.check_box_outlined,
                                  color: Colors.white,
                                )
                              : const Icon(
                                  Icons.check_box_outline_blank,
                                  color: Colors.white,
                                ),
                          title: Text(device.label),
                        ),
                        onTap: () => _selectAudioOutput(device),
                      );
                    })
                ];
              },
            ),
          if (!kIsWeb && lkPlatformIsMobile())
            IconButton(
              disabledColor: Colors.grey,
              onPressed: _setSpeakerphoneOn,
              icon: Icon(
                  _speakerphoneOn ? Icons.speaker_phone : Icons.phone_android),
              tooltip: 'Switch SpeakerPhone',
            ),
          if (participant.isCameraEnabled())
            PopupMenuButton<MediaDevice>(
              icon: const Icon(Icons.videocam_sharp),
              itemBuilder: (BuildContext context) {
                return [
                  PopupMenuItem<MediaDevice>(
                    value: null,
                    onTap: _disableVideo,
                    child: const ListTile(
                      leading: Icon(
                        Icons.videocam_off,
                        color: Colors.white,
                      ),
                      title: Text('Disable Camera'),
                    ),
                  ),
                  if (_videoInputs != null)
                    ..._videoInputs!.map((device) {
                      return PopupMenuItem<MediaDevice>(
                        value: device,
                        child: ListTile(
                          leading: (device.deviceId ==
                                  widget.room.selectedVideoInputDeviceId)
                              ? const Icon(
                                  Icons.check_box_outlined,
                                  color: Colors.white,
                                )
                              : const Icon(
                                  Icons.check_box_outline_blank,
                                  color: Colors.white,
                                ),
                          title: Text(device.label),
                        ),
                        onTap: () => _selectVideoInput(device),
                      );
                    })
                ];
              },
            )
          else
            IconButton(
              onPressed: _enableVideo,
              icon: const Icon(Icons.videocam_off),
              tooltip: 'un-mute video',
            ),
          IconButton(
            icon: Icon(position == CameraPosition.back
                ? Icons.video_camera_back
                : Icons.video_camera_front),
            onPressed: () => _toggleCamera(),
            tooltip: 'toggle camera',
          ),
          if (participant.isScreenShareEnabled())
            IconButton(
              icon: const Icon(Icons.monitor_outlined),
              onPressed: () => _disableScreenShare(),
              tooltip: 'unshare screen (experimental)',
            )
          else
            IconButton(
              icon: const Icon(Icons.monitor),
              onPressed: () => _enableScreenShare(),
              tooltip: 'share screen (experimental)',
            ),
          IconButton(
            onPressed: _onTapDisconnect,
            icon: const Icon(Icons.close_sharp),
            tooltip: 'disconnect',
          ),
          IconButton(
            onPressed: _onTapSendData,
            icon: const Icon(Icons.message),
            tooltip: 'send demo data',
          ),
          IconButton(
            onPressed: _onTapUpdateSubscribePermission,
            icon: const Icon(Icons.settings),
            tooltip: 'Subscribe permission',
          ),
          IconButton(
            onPressed: _onTapSimulateScenario,
            icon: const Icon(Icons.bug_report),
            tooltip: 'Simulate scenario',
          ),
          IconButton(
            onPressed: () => setState(() => _showBitrateControls = !_showBitrateControls),
            icon: Icon(Icons.tune, color: _showBitrateControls ? Colors.blue : null),
            tooltip: 'Bitrate Controls',
          ),
          IconButton(
            onPressed: () => setState(() => _showNetworkStats = !_showNetworkStats),
            icon: Icon(
              Icons.network_check,
              color: _showNetworkStats ? Colors.blue : _getNetworkStatusColor(),
            ),
            tooltip: 'Network Status: $_networkStatus',
          ),
        ],
      ),
      // Bitrate control panel
      if (_showBitrateControls) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bitrate Controls',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Video bitrate slider
              Text(
                'Video Bitrate: ${_videoBitrate.round()} kbps',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Slider(
                value: _videoBitrate,
                min: 100,
                max: 5000,
                divisions: 49,
                activeColor: Colors.blue,
                inactiveColor: Colors.grey,
                onChanged: _updateVideoBitrate,
              ),
              const SizedBox(height: 16),
              // Audio quality presets
              Text(
                'Audio Quality: ${_selectedAudioPreset} (${_audioBitrate.round()} kbps)',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedAudioPreset,
                    dropdownColor: Colors.black87,
                    style: const TextStyle(color: Colors.white),
                    items: _audioPresets.keys.map((String preset) {
                      final bitrate = _audioPresets[preset]!;
                      return DropdownMenuItem<String>(
                        value: preset,
                        child: Text(
                          '$preset (${bitrate} kbps)',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        _changeAudioPreset(newValue);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Resolution selector
              Text(
                'Video Resolution',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedResolution,
                    dropdownColor: Colors.black87,
                    style: const TextStyle(color: Colors.white),
                    items: _resolutionOptions.keys.map((String resolution) {
                      final dimensions = _resolutionOptions[resolution]!;
                      return DropdownMenuItem<String>(
                        value: resolution,
                        child: Text(
                          '$resolution (${dimensions.width}x${dimensions.height})',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        _changeResolution(newValue);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Frame rate selector
              Text(
                'Frame Rate',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedFrameRate,
                    dropdownColor: Colors.black87,
                    style: const TextStyle(color: Colors.white),
                    items: _frameRateOptions.map((int frameRate) {
                      return DropdownMenuItem<int>(
                        value: frameRate,
                        child: Text(
                          '${frameRate} fps',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        _changeFrameRate(newValue);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Simulcast layers selector
              Text(
                'Simulcast Layers',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedSimulcastLayers,
                    dropdownColor: Colors.black87,
                    style: const TextStyle(color: Colors.white),
                    items: _simulcastOptions.keys.map((String option) {
                      String description = '';
                      switch (option) {
                        case 'Disabled':
                          description = 'Single stream only';
                          break;
                        case 'Auto':
                          description = 'Default layers';
                          break;
                        case 'Low+Medium':
                          description = '360p + 540p';
                          break;
                        case 'Medium+High':
                          description = '540p + 720p';
                          break;
                        case 'All Layers':
                          description = '360p + 540p + 720p';
                          break;
                      }
                      return DropdownMenuItem<String>(
                        value: option,
                        child: Text(
                          '$option ($description)',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        _changeSimulcastLayers(newValue);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Video codec selector
              Text(
                'Video Codec',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCodec,
                    dropdownColor: Colors.black87,
                    style: const TextStyle(color: Colors.white),
                    items: _codecOptions.map((String codec) {
                      String description = '';
                      switch (codec) {
                        case 'H.264':
                          description = 'AVC - Best compatibility';
                          break;
                        case 'VP8':
                          description = 'Open source';
                          break;
                        case 'VP9':
                          description = 'Better compression';
                          break;
                        case 'AV1':
                          description = 'Latest, best quality';
                          break;
                      }
                      return DropdownMenuItem<String>(
                        value: codec,
                        child: Text(
                          '$codec ($description)',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        _changeCodec(newValue);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      // Network status panel
      if (_showNetworkStats) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.network_check,
                    color: _getNetworkStatusColor(),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Network Status',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Network quality indicator
              Text(
                'Quality: $_networkStatus',
                style: TextStyle(
                  color: _getNetworkStatusColor(),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // Quality bar
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _networkQuality.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _getNetworkStatusColor(),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Network statistics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bandwidth',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '${(_currentBandwidth / 1000).toStringAsFixed(1)} Mbps',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RTT',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '${_rtt.toStringAsFixed(0)} ms',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Packet Loss',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        '$_packetsLost',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Adaptive streaming toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Adaptive Streaming',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  Switch(
                    value: _adaptiveStream,
                    onChanged: (value) => _toggleAdaptiveStream(),
                    activeColor: Colors.blue,
                  ),
                ],
              ),
              if (_adaptiveStream) ...[
                const SizedBox(height: 8),
                Text(
                  'Quality automatically adjusts based on network conditions',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    ],
      ),
    );
  }
}
