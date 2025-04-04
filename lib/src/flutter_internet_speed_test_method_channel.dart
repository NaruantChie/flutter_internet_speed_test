import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_internet_speed_test/src/models/server_selection_response.dart';
import 'package:flutter_internet_speed_test/src/speed_test_utils.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:tuple_dart/tuple.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';

/// An implementation of [FlutterInternetSpeedTestPlatform] that uses method channels.
class MethodChannelFlutterInternetSpeedTest
    extends FlutterInternetSpeedTestPlatform {
  /// The method channel used to interact with the native platform.
  final _channel = const MethodChannel('com.shaz.plugin.fist/method');
  final _logger = Logger();

  Future<void> _methodCallHandler(MethodCall call) async {
    // Log arguments and callbacks for debugging
    if (isLogEnabled) {
      _logger.d('Received method call: ${call.method}');
      _logger.d('Arguments: ${call.arguments}');
      _logger.d('Current callbacks: $callbacksById');
      _logger.d('Timestamp: ${DateTime.now()}');
    }
    switch (call.method) {
      case 'callListener':
        if (call.arguments["id"] as int ==
            CallbacksEnum.startDownLoadTesting.index) {
          if (call.arguments['type'] == ListenerEnum.complete.index) {
            downloadSteps++;
            downloadRate +=
                int.parse((call.arguments['transferRate'] ~/ 1000).toString());
            double average = (downloadRate ~/ downloadSteps).toDouble();
            // Convert to Mbps
            average /= 1000;
            SpeedUnit unit = SpeedUnit.mbps;
            if (isLogEnabled) {
              _logger.d(
                  "Download COMPLETE: Raw transferRate: ${call.arguments['transferRate']} | Steps: $downloadSteps | Computed Average: $average $unit");
            }
            callbacksById[call.arguments["id"]]!.item3(average, unit);
            downloadSteps = 0;
            downloadRate = 0;
            callbacksById.remove(call.arguments["id"]);
          } else if (call.arguments['type'] == ListenerEnum.error.index) {
            if (isLogEnabled) {
              _logger.d(
                  "Download ERROR: ${call.arguments['errorMessage']} | ${call.arguments['speedTestError']}");
            }
            callbacksById[call.arguments["id"]]!.item1(
                call.arguments['errorMessage'],
                call.arguments['speedTestError']);
            downloadSteps = 0;
            downloadRate = 0;
            callbacksById.remove(call.arguments["id"]);
          } else if (call.arguments['type'] == ListenerEnum.progress.index) {
            double rawRate =
                (call.arguments['transferRate'] ~/ 1000).toDouble();
            if (rawRate != 0) downloadSteps++;
            downloadRate += rawRate.toInt();
            double convertedRate = rawRate / 1000; // in Mbps
            SpeedUnit unit = SpeedUnit.mbps;
            double percent = call.arguments['percent'].toDouble();
            if (isLogEnabled) {
              _logger.d(
                  "Download PROGRESS: $percent% | Raw Rate: $rawRate, Converted Rate: $convertedRate $unit");
            }
            callbacksById[call.arguments["id"]]!
                .item2(percent, convertedRate, unit);
          } else if (call.arguments['type'] == ListenerEnum.cancel.index) {
            if (isLogEnabled) {
              _logger.d("Download CANCELLED for id: ${call.arguments['id']}");
            }
            callbacksById[call.arguments["id"]]!.item4();
            downloadSteps = 0;
            downloadRate = 0;
            callbacksById.remove(call.arguments["id"]);
          }
        } else if (call.arguments["id"] as int ==
            CallbacksEnum.startUploadTesting.index) {
          if (call.arguments['type'] == ListenerEnum.complete.index) {
            uploadSteps++;
            uploadRate +=
                int.parse((call.arguments['transferRate'] ~/ 1000).toString());
            double average = (uploadRate ~/ uploadSteps).toDouble();
            average /= 1000;
            SpeedUnit unit = SpeedUnit.mbps;
            if (isLogEnabled) {
              _logger.d(
                  "Upload COMPLETE: Raw transferRate: ${call.arguments['transferRate']} | Steps: $uploadSteps | Computed Average: $average $unit");
            }
            callbacksById[call.arguments["id"]]!.item3(average, unit);
            uploadSteps = 0;
            uploadRate = 0;
            callbacksById.remove(call.arguments["id"]);
          } else if (call.arguments['type'] == ListenerEnum.error.index) {
            if (isLogEnabled) {
              _logger.d(
                  "Upload ERROR: ${call.arguments['errorMessage']} | ${call.arguments['speedTestError']}");
            }
            callbacksById[call.arguments["id"]]!.item1(
                call.arguments['errorMessage'],
                call.arguments['speedTestError']);
          } else if (call.arguments['type'] == ListenerEnum.progress.index) {
            double rawRate =
                (call.arguments['transferRate'] ~/ 1000).toDouble();
            if (rawRate != 0) uploadSteps++;
            uploadRate += rawRate.toInt();
            double convertedRate = rawRate / 1000.0; // in Mbps
            SpeedUnit unit = SpeedUnit.mbps;
            double percent = call.arguments['percent'].toDouble();
            if (isLogEnabled) {
              _logger.d(
                  "Upload PROGRESS: $percent% | Raw Rate: $rawRate, Converted Rate: $convertedRate $unit");
            }
            callbacksById[call.arguments["id"]]!
                .item2(percent, convertedRate, unit);
          } else if (call.arguments['type'] == ListenerEnum.cancel.index) {
            if (isLogEnabled) {
              _logger.d("Upload CANCELLED for id: ${call.arguments['id']}");
            }
            callbacksById[call.arguments["id"]]!.item4();
            uploadSteps = 0;
            uploadRate = 0;
            callbacksById.remove(call.arguments["id"]);
          }
        }
        break;
      default:
        if (isLogEnabled) {
          _logger.d(
              'Ignoring unknown method call: ${call.method} with arguments ${call.arguments}');
        }
    }

    // ส่งคำสั่งยกเลิกการฟัง (cancel listening) หลังจากประมวลผลเสร็จ
    _channel.invokeMethod("cancelListening", call.arguments["id"]);
  }

  Future<CancelListening> _startListening(
      Tuple4<ErrorCallback, ProgressCallback, DoneCallback, CancelCallback>
          callback,
      CallbacksEnum callbacksEnum,
      String testServer,
      {Map<String, dynamic>? args,
      int fileSize = 10000000}) async {
    _channel.setMethodCallHandler(_methodCallHandler);
    int currentListenerId = callbacksEnum.index;
    if (isLogEnabled) {
      _logger.d(
          'Starting listening with id: $currentListenerId at ${DateTime.now()}');
    }
    callbacksById[currentListenerId] = callback;
    await _channel.invokeMethod(
      "startListening",
      {
        'id': currentListenerId,
        'args': args,
        'testServer': testServer,
        'fileSize': fileSize,
      },
    );
    return () {
      _channel.invokeMethod("cancelListening", currentListenerId);
      callbacksById.remove(currentListenerId);
      if (isLogEnabled) {
        _logger.d(
            'Cancelled listening for id: $currentListenerId at ${DateTime.now()}');
      }
    };
  }

  Future<void> _toggleLog(bool value) async {
    await _channel.invokeMethod(
      "toggleLog",
      {
        'value': value,
      },
    );
  }

  @override
  Future<CancelListening> startDownloadTesting(
      {required DoneCallback onDone,
      required ProgressCallback onProgress,
      required ErrorCallback onError,
      required CancelCallback onCancel,
      required fileSize,
      required String testServer}) async {
    if (isLogEnabled) {
      _logger.d(
          "Starting download test on server: $testServer with fileSize: $fileSize");
    }
    return await _startListening(Tuple4(onError, onProgress, onDone, onCancel),
        CallbacksEnum.startDownLoadTesting, testServer,
        fileSize: fileSize);
  }

  @override
  Future<CancelListening> startUploadTesting(
      {required DoneCallback onDone,
      required ProgressCallback onProgress,
      required ErrorCallback onError,
      required CancelCallback onCancel,
      required int fileSize,
      required String testServer}) async {
    if (isLogEnabled) {
      _logger.d(
          "Starting upload test on server: $testServer with fileSize: $fileSize");
    }
    return await _startListening(Tuple4(onError, onProgress, onDone, onCancel),
        CallbacksEnum.startUploadTesting, testServer,
        fileSize: fileSize);
  }

  @override
  Future<void> toggleLog({required bool value}) async {
    logEnabled = value;
    await _toggleLog(logEnabled);
  }

  @override
  Future<ServerSelectionResponse?> getDefaultServer() async {
    try {
      if (await isInternetAvailable()) {
        const tag = 'token:"';
        var tokenUrl = Uri.parse('https://fast.com/app-a32983.js');
        var tokenResponse = await http.get(tokenUrl);
        if (tokenResponse.body.contains(tag)) {
          int start = tokenResponse.body.lastIndexOf(tag) + tag.length;
          String token = tokenResponse.body.substring(start, start + 32);
          var serverUrl = Uri.parse(
              'https://api.fast.com/netflix/speedtest/v2?https=true&token=$token&urlCount=5');
          var serverResponse = await http.get(serverUrl);
          var serverSelectionResponse = ServerSelectionResponse.fromJson(
              json.decode(serverResponse.body));
          if (serverSelectionResponse.targets?.isNotEmpty == true) {
            if (isLogEnabled) {
              _logger.d(
                  "Default server found: ${serverSelectionResponse.targets!.first.url}");
            }
            return serverSelectionResponse;
          }
        }
      }
    } catch (e) {
      if (logEnabled) {
        _logger.d("Error in getDefaultServer: $e");
      }
    }
    return null;
  }

  @override
  Future<bool> cancelTest() async {
    var result = false;
    try {
      result = await _channel.invokeMethod("cancelTest", {
        'id1': CallbacksEnum.startDownLoadTesting.index,
        'id2': CallbacksEnum.startUploadTesting.index,
      });
      if (isLogEnabled) {
        _logger.d("Test cancelled, result: $result");
      }
    } on PlatformException {
      result = false;
      if (isLogEnabled) {
        _logger.d("PlatformException while cancelling test");
      }
    }
    return result;
  }
}
