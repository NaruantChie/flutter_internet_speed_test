import 'dart:io';

import 'package:flutter_internet_speed_test/src/speed_test_utils.dart';
import 'package:flutter_internet_speed_test/src/test_result.dart';

import 'callbacks_enum.dart';
import 'flutter_internet_speed_test_platform_interface.dart';
import 'models/server_selection_response.dart';

typedef DefaultCallback = void Function();
typedef ResultCallback = void Function(TestResult download, TestResult upload);
typedef TestProgressCallback = void Function(double percent, TestResult data);
typedef ResultCompletionCallback = void Function(TestResult data);
typedef DefaultServerSelectionCallback = void Function(Client? client);

class FlutterInternetSpeedTest {
  static const _defaultDownloadTestServer =
      'http://speedtest.ftp.otenet.gr/files/test10Mb.db';
  static const _defaultUploadTestServer = 'http://speedtest.ftp.otenet.gr/';
  static const _defaultFileSize = 20 * 1024 * 1024; // 20 MB

  static final FlutterInternetSpeedTest _instance =
      FlutterInternetSpeedTest._private();

  bool _isTestInProgress = false;
  bool _isCancelled = false;

  factory FlutterInternetSpeedTest() => _instance;

  FlutterInternetSpeedTest._private();

  bool isTestInProgress() => _isTestInProgress;

  /// ฟังก์ชัน startTesting ใช้งานทั่วไป (ใช้สำหรับทั้ง Android และ iOS)
  Future<void> startTesting({
    required ResultCallback onCompleted,
    DefaultCallback? onStarted,
    ResultCompletionCallback? onDownloadComplete,
    ResultCompletionCallback? onUploadComplete,
    TestProgressCallback? onProgress,
    DefaultCallback? onDefaultServerSelectionInProgress,
    DefaultServerSelectionCallback? onDefaultServerSelectionDone,
    ErrorCallback? onError,
    CancelCallback? onCancel,
    String? downloadTestServer,
    String? uploadTestServer,
    int fileSizeInBytes = _defaultFileSize,
    bool useFastApi = true,
  }) async {
    if (_isTestInProgress) {
      return;
    }
    if (await isInternetAvailable() == false) {
      if (onError != null) {
        onError('No internet connection', 'No internet connection');
      }
      return;
    }

    if (fileSizeInBytes < _defaultFileSize) {
      fileSizeInBytes = _defaultFileSize;
    }
    _isTestInProgress = true;

    if (onStarted != null) onStarted();

    if ((downloadTestServer == null || uploadTestServer == null) &&
        useFastApi) {
      if (onDefaultServerSelectionInProgress != null) {
        onDefaultServerSelectionInProgress();
      }
      final serverSelectionResponse =
          await FlutterInternetSpeedTestPlatform.instance.getDefaultServer();

      if (onDefaultServerSelectionDone != null) {
        onDefaultServerSelectionDone(serverSelectionResponse?.client);
      }
      String? url = serverSelectionResponse?.targets?.first.url;
      if (url != null) {
        downloadTestServer = downloadTestServer ?? url;
        uploadTestServer = uploadTestServer ?? url;
      }
    }
    if (downloadTestServer == null || uploadTestServer == null) {
      downloadTestServer = downloadTestServer ?? _defaultDownloadTestServer;
      uploadTestServer = uploadTestServer ?? _defaultUploadTestServer;
    }

    if (_isCancelled) {
      if (onCancel != null) {
        onCancel();
        _isTestInProgress = false;
        _isCancelled = false;
        return;
      }
    }

    final startDownloadTimeStamp = DateTime.now().millisecondsSinceEpoch;
    FlutterInternetSpeedTestPlatform.instance.startDownloadTesting(
      onDone: (double transferRate, SpeedUnit unit) {
        final downloadDuration =
            DateTime.now().millisecondsSinceEpoch - startDownloadTimeStamp;
        final downloadResult = TestResult(
          TestType.download,
          transferRate,
          unit,
          durationInMillis: downloadDuration,
        );

        if (onProgress != null) onProgress(100, downloadResult);
        if (onDownloadComplete != null) onDownloadComplete(downloadResult);

        final startUploadTimeStamp = DateTime.now().millisecondsSinceEpoch;
        FlutterInternetSpeedTestPlatform.instance.startUploadTesting(
          onDone: (double transferRate, SpeedUnit unit) {
            final uploadDuration =
                DateTime.now().millisecondsSinceEpoch - startUploadTimeStamp;
            final uploadResult = TestResult(
              TestType.upload,
              transferRate,
              unit,
              durationInMillis: uploadDuration,
            );

            if (onProgress != null) onProgress(100, uploadResult);
            if (onUploadComplete != null) onUploadComplete(uploadResult);

            onCompleted(downloadResult, uploadResult);
            _isTestInProgress = false;
            _isCancelled = false;
          },
          onProgress: (double percent, double transferRate, SpeedUnit unit) {
            final uploadProgressResult =
                TestResult(TestType.upload, transferRate, unit);
            if (onProgress != null) {
              onProgress(percent, uploadProgressResult);
            }
          },
          onError: (String errorMessage, String speedTestError) {
            if (onError != null) onError(errorMessage, speedTestError);
            _isTestInProgress = false;
            _isCancelled = false;
          },
          onCancel: () {
            if (onCancel != null) onCancel();
            _isTestInProgress = false;
            _isCancelled = false;
          },
          fileSize: fileSizeInBytes,
          testServer: uploadTestServer!,
        );
      },
      onProgress: (double percent, double transferRate, SpeedUnit unit) {
        final downloadProgressResult =
            TestResult(TestType.download, transferRate, unit);
        if (onProgress != null) onProgress(percent, downloadProgressResult);
      },
      onError: (String errorMessage, String speedTestError) {
        if (onError != null) onError(errorMessage, speedTestError);
        _isTestInProgress = false;
        _isCancelled = false;
      },
      onCancel: () {
        if (onCancel != null) onCancel();
        _isTestInProgress = false;
        _isCancelled = false;
      },
      fileSize: fileSizeInBytes,
      testServer: downloadTestServer,
    );
  }

  /// ฟังก์ชัน startIOSTesting สำหรับ iOS โดยจะเพิ่มดีเลย์และปรับขนาดไฟล์ให้มากขึ้น
  Future<void> startIOSTesting({
    required ResultCallback onCompleted,
    DefaultCallback? onStarted,
    ResultCompletionCallback? onDownloadComplete,
    ResultCompletionCallback? onUploadComplete,
    TestProgressCallback? onProgress,
    DefaultCallback? onDefaultServerSelectionInProgress,
    DefaultServerSelectionCallback? onDefaultServerSelectionDone,
    ErrorCallback? onError,
    CancelCallback? onCancel,
    String? downloadTestServer,
    String? uploadTestServer,
    int fileSizeInBytes = _defaultFileSize,
    bool useFastApi = true,
  }) async {
    // ตรวจสอบว่าปัจจุบันเป็น iOS หรือไม่
    if (!Platform.isIOS) {
      // ถ้าไม่ใช่ iOS ให้เรียกใช้ฟังก์ชันปกติ
      return startTesting(
        onCompleted: onCompleted,
        onStarted: onStarted,
        onDownloadComplete: onDownloadComplete,
        onUploadComplete: onUploadComplete,
        onProgress: onProgress,
        onDefaultServerSelectionInProgress: onDefaultServerSelectionInProgress,
        onDefaultServerSelectionDone: onDefaultServerSelectionDone,
        onError: onError,
        onCancel: onCancel,
        downloadTestServer: downloadTestServer,
        uploadTestServer: uploadTestServer,
        fileSizeInBytes: fileSizeInBytes,
        useFastApi: useFastApi,
      );
    }

    // สำหรับ iOS เพิ่มดีเลย์ 5 วินาที (ก่อนเริ่มการทดสอบ)
    await Future.delayed(Duration(seconds: 5));

    // เพิ่มขนาดไฟล์สำหรับ iOS เพื่อให้การประมวลผลนานขึ้น (ในตัวอย่างเพิ่มเป็น 8 เท่า)
    int iosFileSize = fileSizeInBytes * 8;

    return startTesting(
      onCompleted: onCompleted,
      onStarted: onStarted,
      onDownloadComplete: onDownloadComplete,
      onUploadComplete: onUploadComplete,
      onProgress: onProgress,
      onDefaultServerSelectionInProgress: onDefaultServerSelectionInProgress,
      onDefaultServerSelectionDone: onDefaultServerSelectionDone,
      onError: onError,
      onCancel: onCancel,
      downloadTestServer: downloadTestServer,
      uploadTestServer: uploadTestServer,
      fileSizeInBytes: iosFileSize,
      useFastApi: useFastApi,
    );
  }

  /// ฟังก์ชัน startAndroidTesting สำหรับ Android โดยจะเพิ่มดีเลย์และปรับขนาดไฟล์ให้มากขึ้น
  Future<void> startAndroidTesting({
    required ResultCallback onCompleted,
    DefaultCallback? onStarted,
    ResultCompletionCallback? onDownloadComplete,
    ResultCompletionCallback? onUploadComplete,
    TestProgressCallback? onProgress,
    DefaultCallback? onDefaultServerSelectionInProgress,
    DefaultServerSelectionCallback? onDefaultServerSelectionDone,
    ErrorCallback? onError,
    CancelCallback? onCancel,
    String? downloadTestServer,
    String? uploadTestServer,
    int fileSizeInBytes = _defaultFileSize,
    bool useFastApi = true,
  }) async {
    // ตรวจสอบว่าปัจจุบันเป็น Android หรือไม่
    if (!Platform.isAndroid) {
      // ถ้าไม่ใช่ Android ให้เรียกใช้ฟังก์ชันปกติ
      return startTesting(
        onCompleted: onCompleted,
        onStarted: onStarted,
        onDownloadComplete: onDownloadComplete,
        onUploadComplete: onUploadComplete,
        onProgress: onProgress,
        onDefaultServerSelectionInProgress: onDefaultServerSelectionInProgress,
        onDefaultServerSelectionDone: onDefaultServerSelectionDone,
        onError: onError,
        onCancel: onCancel,
        downloadTestServer: downloadTestServer,
        uploadTestServer: uploadTestServer,
        fileSizeInBytes: fileSizeInBytes,
        useFastApi: useFastApi,
      );
    }

    // สำหรับ Android เพิ่มดีเลย์ 3 วินาที (ก่อนเริ่มการทดสอบ)
    await Future.delayed(Duration(seconds: 3));

    // ปรับขนาดไฟล์สำหรับ Android ให้มากขึ้น (ในตัวอย่างเพิ่มเป็น 3 เท่า)
    int androidFileSize = fileSizeInBytes * 3;

    return startTesting(
      onCompleted: onCompleted,
      onStarted: onStarted,
      onDownloadComplete: onDownloadComplete,
      onUploadComplete: onUploadComplete,
      onProgress: onProgress,
      onDefaultServerSelectionInProgress: onDefaultServerSelectionInProgress,
      onDefaultServerSelectionDone: onDefaultServerSelectionDone,
      onError: onError,
      onCancel: onCancel,
      downloadTestServer: downloadTestServer,
      uploadTestServer: uploadTestServer,
      fileSizeInBytes: androidFileSize,
      useFastApi: useFastApi,
    );
  }

  void enableLog() {
    FlutterInternetSpeedTestPlatform.instance.toggleLog(value: true);
  }

  void disableLog() {
    FlutterInternetSpeedTestPlatform.instance.toggleLog(value: false);
  }

  Future<bool> cancelTest() async {
    _isCancelled = true;
    return await FlutterInternetSpeedTestPlatform.instance.cancelTest();
  }

  bool get isLogEnabled => FlutterInternetSpeedTestPlatform.instance.logEnabled;
}
