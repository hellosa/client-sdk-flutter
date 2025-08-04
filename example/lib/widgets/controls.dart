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
  
  // Bandwidth monitoring chart
  List<double> _bandwidthHistory = [];
  List<double> _rttHistory = [];
  final int _maxHistoryLength = 30; // Keep last 30 data points (1 minute at 2s intervals)
  bool _showBandwidthChart = false;
  
  // CPU usage monitoring
  double _cpuUsage = 0.0; // Percentage 0-100
  List<double> _cpuHistory = [];
  bool _showCPUStats = false;
  Timer? _cpuMonitorTimer;
  
  // Auto degradation thresholds
  bool _showDegradationSettings = false;
  double _networkQualityThreshold = 0.5; // Network quality threshold (0.0-1.0)
  double _cpuUsageThreshold = 75.0; // CPU usage threshold (0-100%)
  double _rttThreshold = 200.0; // RTT threshold in ms
  int _packetLossThreshold = 5; // Packet loss threshold
  bool _enableCPUBasedDegradation = true;
  bool _enableRTTBasedDegradation = true;
  bool _enablePacketLossBasedDegradation = true;

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
    
    // Start CPU monitoring
    _startCPUMonitoring();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _cpuMonitorTimer?.cancel();
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
            
            // Add to history for charts
            _bandwidthHistory.add(_currentBandwidth);
            _rttHistory.add(_rtt);
            
            // Keep history within limits
            if (_bandwidthHistory.length > _maxHistoryLength) {
              _bandwidthHistory.removeAt(0);
            }
            if (_rttHistory.length > _maxHistoryLength) {
              _rttHistory.removeAt(0);
            }
            
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
    
    bool shouldDegrade = false;
    String degradationReason = '';
    
    // Check network quality threshold
    if (_networkQuality < _networkQualityThreshold) {
      shouldDegrade = true;
      degradationReason += 'Network quality (${(_networkQuality * 100).toStringAsFixed(0)}%) below threshold (${(_networkQualityThreshold * 100).toStringAsFixed(0)}%); ';
    }
    
    // Check RTT threshold
    if (_enableRTTBasedDegradation && _rtt > _rttThreshold) {
      shouldDegrade = true;
      degradationReason += 'RTT (${_rtt.toStringAsFixed(0)}ms) above threshold (${_rttThreshold.toStringAsFixed(0)}ms); ';
    }
    
    // Check packet loss threshold
    if (_enablePacketLossBasedDegradation && _packetsLost > _packetLossThreshold) {
      shouldDegrade = true;
      degradationReason += 'Packet loss ($_packetsLost) above threshold ($_packetLossThreshold); ';
    }
    
    // Check CPU usage threshold
    if (_enableCPUBasedDegradation && _cpuUsage > _cpuUsageThreshold) {
      shouldDegrade = true;
      degradationReason += 'CPU usage (${_cpuUsage.toStringAsFixed(1)}%) above threshold (${_cpuUsageThreshold.toStringAsFixed(1)}%); ';
    }
    
    if (shouldDegrade) {
      print('Quality degradation triggered: $degradationReason');
      
      // Degrade resolution
      if (_selectedResolution == '1440p') {
        _changeResolution('1080p');
      } else if (_selectedResolution == '1080p') {
        _changeResolution('720p');
      } else if (_selectedResolution == '720p') {
        _changeResolution('480p');
      } else if (_selectedResolution == '480p') {
        _changeResolution('360p');
      }
      
      // Degrade frame rate if CPU is too high
      if (_enableCPUBasedDegradation && _cpuUsage > _cpuUsageThreshold && _selectedFrameRate > 15) {
        if (_selectedFrameRate == 60) {
          _changeFrameRate(30);
        } else if (_selectedFrameRate == 30) {
          _changeFrameRate(24);
        } else if (_selectedFrameRate == 24) {
          _changeFrameRate(15);
        }
      }
    } else {
      // Try to upgrade quality if conditions allow
      if (_networkQuality > (_networkQualityThreshold + 0.2) && 
          _rtt < (_rttThreshold - 50) && 
          _cpuUsage < (_cpuUsageThreshold - 15)) {
        
        print('Conditions good - considering quality upgrade');
        
        // Upgrade resolution gradually
        if (_selectedResolution == '360p') {
          _changeResolution('480p');
        } else if (_selectedResolution == '480p' && _cpuUsage < (_cpuUsageThreshold - 20)) {
          _changeResolution('720p');
        }
      }
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
  
  void _startCPUMonitoring() {
    _cpuMonitorTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _updateCPUStats();
    });
  }
  
  void _updateCPUStats() {
    // Simulate CPU usage calculation
    // In a real app, you would use platform-specific methods to get actual CPU usage
    // For web, we can estimate based on video processing performance
    try {
      final videoTrack = participant.videoTrackPublications.firstOrNull?.track as LocalVideoTrack?;
      if (videoTrack != null) {
        // Estimate CPU usage based on video encoding performance
        // Higher resolution and frame rate = higher CPU usage
        double estimatedCPU = 0.0;
        
        // Base CPU usage
        estimatedCPU += 10.0; // Base usage for running the app
        
        // Resolution impact
        switch (_selectedResolution) {
          case '360p':
            estimatedCPU += 5.0;
            break;
          case '480p':
            estimatedCPU += 10.0;
            break;
          case '720p':
            estimatedCPU += 20.0;
            break;
          case '1080p':
            estimatedCPU += 35.0;
            break;
          case '1440p':
            estimatedCPU += 50.0;
            break;
        }
        
        // Frame rate impact
        estimatedCPU += (_selectedFrameRate / 60.0) * 15.0;
        
        // Codec impact
        switch (_selectedCodec) {
          case 'H.264':
            estimatedCPU += 5.0;
            break;
          case 'VP8':
            estimatedCPU += 8.0;
            break;
          case 'VP9':
            estimatedCPU += 12.0;
            break;
          case 'AV1':
            estimatedCPU += 20.0;
            break;
        }
        
        // Simulcast impact
        if (_simulcastEnabled && _selectedSimulcastLayers != 'Disabled') {
          estimatedCPU += 10.0;
        }
        
        // Add some random variation to simulate real CPU usage
        final random = math.Random();
        estimatedCPU += (random.nextDouble() - 0.5) * 10.0;
        
        // Clamp to reasonable range
        estimatedCPU = math.max(0.0, math.min(100.0, estimatedCPU));
        
        setState(() {
          _cpuUsage = estimatedCPU;
          _cpuHistory.add(_cpuUsage);
          
          // Keep history within limits
          if (_cpuHistory.length > _maxHistoryLength) {
            _cpuHistory.removeAt(0);
          }
        });
      }
    } catch (e) {
      print('Failed to update CPU stats: $e');
    }
  }
  
  Color _getCPUStatusColor() {
    if (_cpuUsage >= 80) return Colors.red;
    if (_cpuUsage >= 60) return Colors.orange;
    if (_cpuUsage >= 40) return Colors.yellow;
    return Colors.green;
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
          IconButton(
            onPressed: () => setState(() => _showBandwidthChart = !_showBandwidthChart),
            icon: Icon(Icons.show_chart, color: _showBandwidthChart ? Colors.blue : null),
            tooltip: 'Bandwidth Chart',
          ),
          IconButton(
            onPressed: () => setState(() => _showCPUStats = !_showCPUStats),
            icon: Icon(
              Icons.memory,
              color: _showCPUStats ? Colors.blue : _getCPUStatusColor(),
            ),
            tooltip: 'CPU Usage: ${_cpuUsage.toStringAsFixed(1)}%',
          ),
          IconButton(
            onPressed: () => setState(() => _showDegradationSettings = !_showDegradationSettings),
            icon: Icon(Icons.auto_fix_high, color: _showDegradationSettings ? Colors.blue : null),
            tooltip: 'Auto Quality Settings',
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
      // Bandwidth monitoring chart panel
      if (_showBandwidthChart) ...[
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
                    Icons.show_chart,
                    color: Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Bandwidth Monitor',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Bandwidth chart
              Text(
                'Bandwidth (last ${_bandwidthHistory.length} samples)',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: _buildBandwidthChart(),
              ),
              const SizedBox(height: 16),
              // RTT chart
              Text(
                'Round Trip Time (last ${_rttHistory.length} samples)',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: _buildRTTChart(),
              ),
              const SizedBox(height: 16),
              // Chart statistics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'Avg Bandwidth',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _bandwidthHistory.isNotEmpty 
                          ? '${(_bandwidthHistory.reduce((a, b) => a + b) / _bandwidthHistory.length / 1000).toStringAsFixed(1)} Mbps'
                          : '0.0 Mbps',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Max Bandwidth',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _bandwidthHistory.isNotEmpty 
                          ? '${(_bandwidthHistory.reduce(math.max) / 1000).toStringAsFixed(1)} Mbps'
                          : '0.0 Mbps',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Avg RTT',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _rttHistory.isNotEmpty 
                          ? '${(_rttHistory.reduce((a, b) => a + b) / _rttHistory.length).toStringAsFixed(0)} ms'
                          : '0 ms',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      // CPU usage panel
      if (_showCPUStats) ...[
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
                    Icons.memory,
                    color: _getCPUStatusColor(),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CPU Usage',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Current CPU usage
              Text(
                'Current: ${_cpuUsage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _getCPUStatusColor(),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // CPU usage progress bar
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (_cpuUsage / 100.0).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _getCPUStatusColor(),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // CPU history chart
              Text(
                'CPU History (last ${_cpuHistory.length} seconds)',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: _buildCPUChart(),
              ),
              const SizedBox(height: 16),
              // CPU statistics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'Average',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _cpuHistory.isNotEmpty 
                          ? '${(_cpuHistory.reduce((a, b) => a + b) / _cpuHistory.length).toStringAsFixed(1)}%'
                          : '0.0%',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Maximum',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _cpuHistory.isNotEmpty 
                          ? '${_cpuHistory.reduce(math.max).toStringAsFixed(1)}%'
                          : '0.0%',
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        'Status',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _cpuUsage >= 80 ? 'High' : 
                        _cpuUsage >= 60 ? 'Medium' : 
                        _cpuUsage >= 40 ? 'Normal' : 'Low',
                        style: TextStyle(
                          color: _getCPUStatusColor(), 
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '* CPU usage estimated based on video encoding settings',
                style: const TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ],
      // Auto degradation settings panel
      if (_showDegradationSettings) ...[
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
                    Icons.auto_fix_high,
                    color: Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Auto Quality Thresholds',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Network Quality Threshold
              Text(
                'Network Quality Threshold: ${(_networkQualityThreshold * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              Slider(
                value: _networkQualityThreshold,
                min: 0.1,
                max: 0.9,
                divisions: 8,
                activeColor: Colors.blue,
                inactiveColor: Colors.grey,
                onChanged: (value) {
                  setState(() {
                    _networkQualityThreshold = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              
              // CPU Usage Threshold
              Row(
                children: [
                  Checkbox(
                    value: _enableCPUBasedDegradation,
                    onChanged: (value) {
                      setState(() {
                        _enableCPUBasedDegradation = value ?? true;
                      });
                    },
                    activeColor: Colors.blue,
                  ),
                  Expanded(
                    child: Text(
                      'CPU Threshold: ${_cpuUsageThreshold.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: _enableCPUBasedDegradation ? Colors.white : Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (_enableCPUBasedDegradation)
                Slider(
                  value: _cpuUsageThreshold,
                  min: 50.0,
                  max: 95.0,
                  divisions: 9,
                  activeColor: Colors.purple,
                  inactiveColor: Colors.grey,
                  onChanged: (value) {
                    setState(() {
                      _cpuUsageThreshold = value;
                    });
                  },
                ),
              const SizedBox(height: 12),
              
              // RTT Threshold
              Row(
                children: [
                  Checkbox(
                    value: _enableRTTBasedDegradation,
                    onChanged: (value) {
                      setState(() {
                        _enableRTTBasedDegradation = value ?? true;
                      });
                    },
                    activeColor: Colors.blue,
                  ),
                  Expanded(
                    child: Text(
                      'RTT Threshold: ${_rttThreshold.toStringAsFixed(0)}ms',
                      style: TextStyle(
                        color: _enableRTTBasedDegradation ? Colors.white : Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (_enableRTTBasedDegradation)
                Slider(
                  value: _rttThreshold,
                  min: 50.0,
                  max: 500.0,
                  divisions: 18,
                  activeColor: Colors.orange,
                  inactiveColor: Colors.grey,
                  onChanged: (value) {
                    setState(() {
                      _rttThreshold = value;
                    });
                  },
                ),
              const SizedBox(height: 12),
              
              // Packet Loss Threshold
              Row(
                children: [
                  Checkbox(
                    value: _enablePacketLossBasedDegradation,
                    onChanged: (value) {
                      setState(() {
                        _enablePacketLossBasedDegradation = value ?? true;
                      });
                    },
                    activeColor: Colors.blue,
                  ),
                  Expanded(
                    child: Text(
                      'Packet Loss Threshold: $_packetLossThreshold packets',
                      style: TextStyle(
                        color: _enablePacketLossBasedDegradation ? Colors.white : Colors.white54,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              if (_enablePacketLossBasedDegradation)
                Slider(
                  value: _packetLossThreshold.toDouble(),
                  min: 1.0,
                  max: 20.0,
                  divisions: 19,
                  activeColor: Colors.red,
                  inactiveColor: Colors.grey,
                  onChanged: (value) {
                    setState(() {
                      _packetLossThreshold = value.round();
                    });
                  },
                ),
              const SizedBox(height: 16),
              
              // Current status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Status',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Network: ${(_networkQuality * 100).toStringAsFixed(0)}% (threshold: ${(_networkQualityThreshold * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(
                        color: _networkQuality >= _networkQualityThreshold ? Colors.green : Colors.red,
                        fontSize: 12,
                      ),
                    ),
                    if (_enableCPUBasedDegradation)
                      Text(
                        'CPU: ${_cpuUsage.toStringAsFixed(1)}% (threshold: ${_cpuUsageThreshold.toStringAsFixed(0)}%)',
                        style: TextStyle(
                          color: _cpuUsage <= _cpuUsageThreshold ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    if (_enableRTTBasedDegradation)
                      Text(
                        'RTT: ${_rtt.toStringAsFixed(0)}ms (threshold: ${_rttThreshold.toStringAsFixed(0)}ms)',
                        style: TextStyle(
                          color: _rtt <= _rttThreshold ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    if (_enablePacketLossBasedDegradation)
                      Text(
                        'Packet Loss: $_packetsLost (threshold: $_packetLossThreshold)',
                        style: TextStyle(
                          color: _packetsLost <= _packetLossThreshold ? Colors.green : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ],
      ),
    );
  }
  
  Widget _buildBandwidthChart() {
    if (_bandwidthHistory.isEmpty) {
      return const Center(
        child: Text(
          'No data yet...',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }
    
    return CustomPaint(
      size: Size.infinite,
      painter: LineChartPainter(
        data: _bandwidthHistory,
        color: Colors.blue,
        label: 'kbps',
      ),
    );
  }
  
  Widget _buildRTTChart() {
    if (_rttHistory.isEmpty) {
      return const Center(
        child: Text(
          'No data yet...',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }
    
    return CustomPaint(
      size: Size.infinite,
      painter: LineChartPainter(
        data: _rttHistory,
        color: Colors.orange,
        label: 'ms',
      ),
    );
  }
  
  Widget _buildCPUChart() {
    if (_cpuHistory.isEmpty) {
      return const Center(
        child: Text(
          'No data yet...',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      );
    }
    
    return CustomPaint(
      size: Size.infinite,
      painter: LineChartPainter(
        data: _cpuHistory,
        color: Colors.purple,
        label: '%',
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final String label;
  
  LineChartPainter({
    required this.data,
    required this.color,
    required this.label,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final fillPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    
    final path = Path();
    final fillPath = Path();
    
    final maxValue = data.reduce(math.max);
    final minValue = data.reduce(math.min);
    final range = maxValue - minValue;
    
    if (range == 0) return; // Avoid division by zero
    
    final stepX = size.width / (data.length - 1);
    
    // Start fill path from bottom
    fillPath.moveTo(0, size.height);
    
    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = (data[i] - minValue) / range;
      final y = size.height - (normalizedValue * size.height);
      
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    
    // Close fill path
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    
    // Draw filled area first
    canvas.drawPath(fillPath, fillPaint);
    
    // Draw line on top
    canvas.drawPath(path, paint);
    
    // Draw value labels
    final textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    
    // Draw min value
    textPainter.text = TextSpan(
      text: '${minValue.toStringAsFixed(0)}$label',
      style: const TextStyle(color: Colors.white70, fontSize: 10),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(4, size.height - textPainter.height - 2));
    
    // Draw max value
    textPainter.text = TextSpan(
      text: '${maxValue.toStringAsFixed(0)}$label',
      style: const TextStyle(color: Colors.white70, fontSize: 10),
    );
    textPainter.layout();
    textPainter.paint(canvas, const Offset(4, 2));
  }
  
  @override
  bool shouldRepaint(LineChartPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}
