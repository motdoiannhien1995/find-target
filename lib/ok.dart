import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart' hide ServiceStatus;
import 'package:geolocator/geolocator.dart';
import 'dart:async'; 
import 'dart:math';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart'; 
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:android_id/android_id.dart';

import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';

import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: InvincibleOverlay(),
  ));
}

class InvincibleOverlay extends StatefulWidget {
  const InvincibleOverlay({super.key});

  @override
  State<InvincibleOverlay> createState() => _InvincibleOverlayState();
}

class _InvincibleOverlayState extends State<InvincibleOverlay> {
  final String _myPackage = "com.khoa.findtarget"; 
  String? _targetPackage;
  String? _secondTargetPackage; 
  
  bool _isReturning = false; 
  Color _bgColor = Colors.blue.shade800;
  
  double _opacity = 0.4; 

  @override
  void initState() {
    super.initState();
    _loadTargetFromDisk();
    
    FlutterOverlayWindow.overlayListener.listen((event) async {
      if (!mounted) return;
      
      try {
        await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
      } catch (e) {}

      if (event == 'update_packages') {
        await _loadTargetFromDisk();
      } else if (event == 'to_target') {
        setState(() {
          _isReturning = true;
          _bgColor = Colors.green.shade800;
          _opacity = 0.4; 
        });
      } else if (event == 'to_main') {
        setState(() {
          _isReturning = false;
          _bgColor = Colors.blue.shade800;
          _opacity = 0.4;
        });
      } else if (event == 'show') {
        await _loadTargetFromDisk(); 
        setState(() => _opacity = 0.4);
      }
    });
  }

  Future<void> _loadTargetFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); 
      setState(() {
        _targetPackage = prefs.getString('target_app_package');
        _secondTargetPackage = prefs.getString('second_target_app_package');
        _isReturning = prefs.getBool('overlay_is_returning') ?? false;
        if (_isReturning) {
          _bgColor = Colors.green.shade800;
        } else {
          _bgColor = Colors.blue.shade800;
        }
      });
    } catch (e) {
      print("Overlay lỗi đọc disk");
    }
  }

  Future<void> _launchApp(String pkg) async {
    try {
      final Uri uri1 = Uri.parse("intent:#Intent;action=android.intent.action.MAIN;package=$pkg;launchFlags=0x10020000;end");
      if (await launchUrl(uri1, mode: LaunchMode.externalApplication)) return;
    } catch (e) {}

    try {
      final Uri uri2 = Uri.parse("intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;package=$pkg;launchFlags=0x10100000;end");
      if (await launchUrl(uri2, mode: LaunchMode.externalApplication)) return;
    } catch (e) {}

    try {
      bool? success = await InstalledApps.startApp(pkg);
      if (success == true) return; 
    } catch (e) {
      if (mounted) setState(() => _bgColor = Colors.red.shade800);
    }
  }

  Widget _buildButton(IconData icon, String? pkg, bool isMain) {
    bool isDisabled = !isMain && (pkg == null || pkg.isEmpty);
    return InkWell(
      onTap: isDisabled ? null : () async {
        setState(() {
          _opacity = 0.4; 
          _bgColor = isMain ? Colors.blue.shade800 : (pkg == _targetPackage ? Colors.green.shade800 : Colors.deepOrange);
        });

        if (isMain) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('overlay_is_returning', false);
          await _launchApp(_myPackage);
        } else {
          if (pkg == _targetPackage) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('overlay_is_returning', true);
          }
          await _launchApp(pkg!);
        }
      },
      onDoubleTap: () async {
        setState(() {
          _opacity = 0.0;
        });
        try {
          await FlutterOverlayWindow.updateFlag(OverlayFlag.clickThrough);
        } catch (e) {}

        await Future.delayed(const Duration(seconds: 3));

        if (mounted) {
          setState(() {
            _opacity = 0.4;
          });
          try {
            await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
          } catch (e) {}
        }
      },
      onLongPress: () async {
        setState(() {
          _opacity = 0.0;
        });
        try {
          await FlutterOverlayWindow.updateFlag(OverlayFlag.clickThrough);
        } catch (e) {}
      },
      borderRadius: BorderRadius.circular(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 18.0),
        child: Icon(
          icon, 
          color: isDisabled ? Colors.white30 : Colors.white.withOpacity(_opacity == 0.0 ? 0.0 : 1.0), 
          size: 26
        ),
      ),
    );
  }

 @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            width: 60, 
            decoration: BoxDecoration(
              color: _bgColor.withOpacity(_opacity), 
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(_opacity == 0.0 ? 0.0 : 0.5), width: 2.0), 
              boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black45.withOpacity(_opacity == 0.0 ? 0.0 : 0.4))], 
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildButton(Icons.my_location, _myPackage, true),
                
                if (_targetPackage != null && _targetPackage!.isNotEmpty) ...[
                  Container(width: 30, height: 1, color: Colors.white.withOpacity(_opacity == 0.0 ? 0.0 : 0.3)),
                  _buildButton(Icons.layers, _targetPackage, false),
                ],
                
                if (_secondTargetPackage != null && _secondTargetPackage!.isNotEmpty) ...[
                  Container(width: 30, height: 1, color: Colors.white.withOpacity(_opacity == 0.0 ? 0.0 : 0.3)),
                  _buildButton(Icons.rocket_launch, _secondTargetPackage, false),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

late final CacheStore _mapCacheStore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  try {
    final dir = await getTemporaryDirectory();
    _mapCacheStore = FileCacheStore('${dir.path}/map_tiles');
  } catch (e) {
    _mapCacheStore = MemCacheStore(); 
  }
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MockApp()));
}

class Beacon {
  LatLng? location;
  final TextEditingController controller;
  final FocusNode focusNode;
  Color color;
  int resetStep = 0; 
  String unit; 
   
  Beacon({this.location, String dist = "", Color? color, this.unit = 'km'}) 
      : controller = TextEditingController(text: dist),
        focusNode = FocusNode(),
        color = color ?? Colors.blue; 

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class SavedTarget {
  LatLng location;
  String name;
  final DateTime timestamp;
  final String id;
  String address; 

  SavedTarget({required this.location, required this.name, required this.timestamp, String? id, this.address = ""}) 
    : id = id ?? DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(100).toString();

  Map<String, dynamic> toJson() => {
    'lat': location.latitude,
    'lng': location.longitude,
    'name': name,
    'time': timestamp.toIso8601String(),
    'id': id,
    'address': address,
  };

  factory SavedTarget.fromJson(Map<String, dynamic> json) => SavedTarget(
    location: LatLng(json['lat'], json['lng']),
    name: json['name'],
    timestamp: DateTime.parse(json['time']),
    id: json['id'],
    address: json['address'] ?? "", 
  );
}

class MockApp extends StatefulWidget {
  const MockApp({super.key});
  @override
  State<MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<MockApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.mock/gps');
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  final ScreenshotController _screenshotController = ScreenshotController(); 

  final GlobalKey _linkAppKey = GlobalKey(); 
  final GlobalKey _helpKey = GlobalKey(); 
  
  late TutorialCoachMark tutorialCoachMark;
  List<TargetFocus> targets = [];
  bool _isTutorialShowing = false;
  bool _isMockDialogShowing = false; 

  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  
  bool _isGpsDialogShowing = false;
  bool _isOverlayActive = false; 
  bool _autoShowOverlay = true; 

  bool isPro = false;
  int trialCount = 0;
  final int maxTrial = 150;
  bool allowTrialFromServer = true; 
  String? deviceId;

  List<Beacon> beacons = [Beacon(unit: 'km')]; 
  List<SavedTarget> savedTargets = [];
  List<SavedTarget> historyTargets = []; 
  
  String defaultUnit = 'km'; 
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0, 'mi': 1609.34};
  final List<String> availableUnits = ['km', 'm', 'mi', 'ft'];

  int? selectedIndex; 
  List<LatLng> targetPoints = [];
  LatLng? myRealLocation = const LatLng(21.028511, 105.804817);
  LatLng? searchMarker;
  
  String coordDisplay = "0.000000, 0.000000";
  String addressDisplay = "Chưa có vị trí";
  Color addressColor = Colors.grey; 

  bool isMockingTarget = false;
  bool isSearchVisible = false;
  
  String? targetAppPackage; 
  String? secondTargetAppPackage; 
  
  bool _isLoadingLocation = false;
  Timer? _resetSwitchTimer; 

  static const double earthRadius = 6371000.0;
  
  final List<Color> colorPalette = [Colors.orange, Colors.teal, Colors.pink, Colors.brown, Colors.indigo, Colors.blue];

  int? _lastFocusedIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _checkStatus(); 
    _loadData(); 
    _requestOverlayPermission();
    
    FlutterOverlayWindow.isActive().then((val) {
      if (mounted) setState(() => _isOverlayActive = val);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initLocation();
      
      _serviceStatusStreamSubscription = Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
        if (status == ServiceStatus.disabled) {
          if (!_isGpsDialogShowing) _showGpsBlockingDialog();
        } else if (status == ServiceStatus.enabled) {
          if (_isGpsDialogShowing) {
            Navigator.of(context, rootNavigator: true).pop();
            _isGpsDialogShowing = false;
          }
        }
      });

      bool isGranted = await platform.invokeMethod('checkMockPermission');
      if (!isGranted) {
        _showMockPermissionDialog();
      } else {
        _checkAndShowTutorial();
      }
    });
  }

  void _showGpsBlockingDialog() {
    if (!mounted) return;
    _isGpsDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Mất Kết Nối GPS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          content: const Text("Bạn vừa tắt Dịch vụ vị trí (GPS).\n\nỨng dụng bắt buộc phải bật GPS để lấy mốc tính toán tọa độ chính xác. Vui lòng bật lại GPS để tiếp tục.", textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                await Geolocator.openLocationSettings();
              },
              child: const Text("Mở Cài đặt GPS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () async {
                bool enabled = await Geolocator.isLocationServiceEnabled();
                if (enabled) {
                  Navigator.pop(ctx);
                  _isGpsDialogShowing = false;
                } else {
                  _showMsg("Bạn chưa bật GPS!");
                }
              },
              child: const Text("Đã bật lại"),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _checkGpsOnResume() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled && !_isGpsDialogShowing) {
       _showGpsBlockingDialog();
    } else if (serviceEnabled && _isGpsDialogShowing) {
       Navigator.of(context, rootNavigator: true).pop();
       _isGpsDialogShowing = false;
    }
  }

  String _getBeaconName(int index) {
    if (index < 3) return "Mốc ${index + 1}";
    return "Mục tiêu ${index - 2}";
  }

  String _getBeaconShortName(int index) {
    if (index < 3) return "M${index + 1}";
    return "T${index - 2}";
  }

  Color _getBeaconColor(int index, Color originalColor) {
    if (index < 3) return Colors.blueGrey.shade800; 
    return originalColor;
  }

  Future<void> _checkAndShowTutorial() async {
    bool isGranted = await platform.invokeMethod('checkMockPermission');
    if (!isGranted || _isTutorialShowing) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isFirstTime = prefs.getBool('is_first_time_flow_v10') ?? true;

    if (isFirstTime) {
      _isTutorialShowing = true;
      _initTargets();
      _showTutorial();
      await prefs.setBool('is_first_time_flow_v10', false); 
    }
  }

  void _initTargets() {
    targets = [
      TargetFocus(
        identify: "link_app_btn",
        keyTarget: _linkAppKey,
        alignSkip: Alignment.topRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("BƯỚC 1: Liên kết ứng dụng", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 22)),
                SizedBox(height: 10),
                Text("Nhấn giữ vào biểu tượng này để chọn app dùng để đo khoảng cách.", style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "help_btn",
        keyTarget: _helpKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Bảng hướng dẫn chi tiết", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 22)),
                SizedBox(height: 10),
                Text("Bấm vào đây để đọc bảng hướng dẫn chi tiết nhé!", style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  void _showTutorial() {
    tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.85,
      textSkip: "ĐÃ HIỂU",
      paddingFocus: 10,
      onFinish: () {
        _isTutorialShowing = false;
      },
      onSkip: () {
        _isTutorialShowing = false;
        return true;
      },
    )..show(context: context);
  }

  Future<void> _showMockPermissionDialog() async {
    if (_isMockDialogShowing) return;
    
    bool devEnabled = false;
    try {
      devEnabled = await platform.invokeMethod('checkDevOptionsStatus') ?? false;
    } catch (e) {}

    _isMockDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) => PopScope(
        canPop: false, 
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("Bắt Buộc Cấp Quyền", textAlign: TextAlign.center, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Bạn PHẢI chọn ứng dụng này trong mục 'Ứng dụng vị trí mô phỏng' (Mock Location) ở Tùy chọn nhà phát triển thì mới có thể sử dụng được app.",
                  style: TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                
                if (!devEnabled) ...[
                  const Text(
                    "Máy của bạn CHƯA BẬT Tùy chọn nhà phát triển:",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Vào Cài đặt máy -> Giới thiệu điện thoại -> Nhấn liên tục 7 lần vào 'Số hiệu bản tạo' (hoặc 'Phiên bản MIUI/OS', 'Số bản dựng').",
                    style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                   const Text(
                    "Máy của bạn ĐÃ BẬT Tùy chọn nhà phát triển.\nHãy bấm nút bên dưới và tìm mục ứng dụng vị trí mô phỏng nhé.",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
                
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent, 
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      try {
                        await platform.invokeMethod('openDeveloperOptions');
                      } catch (e) {
                        _showMsg("Lỗi: Không thể tự động mở. Vui lòng mở thủ công trong Cài đặt.");
                      }
                    },
                    child: Text(
                      devEnabled ? "Tới Tùy Chọn Nhà Phát Triển" : "Tới Giới Thiệu Điện Thoại", 
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkMockOnResume() async {
    try {
      bool isGranted = await platform.invokeMethod('checkMockPermission');
      if (isGranted) {
        if (_isMockDialogShowing) {
          Navigator.of(context, rootNavigator: true).pop(); 
          _isMockDialogShowing = false;
          _showMsg("Đã cấp quyền thành công!");
        }
        _checkAndShowTutorial();
      } else {
        _stopMock();
        if (_isMockDialogShowing) {
           Navigator.of(context, rootNavigator: true).pop(); 
           _isMockDialogShowing = false;
        }
        _showMockPermissionDialog();
      }
    } catch (e) {}
  }

  Future<void> _checkStatus() async {
    final androidIdPlugin = const AndroidId();
    deviceId = await androidIdPlugin.getId();
    if (deviceId == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('trace_target').doc('config').get();
      if (adminDoc.exists) {
        if (mounted) {
          setState(() {
            allowTrialFromServer = adminDoc.data()?['allow_trial'] ?? true;
          });
        }
      }
    } catch (e) {
      print("Lỗi đọc công tắc trace_target: $e");
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('devices').doc(deviceId!).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            isPro = doc.data()?['isPro'] ?? false;
            trialCount = doc.data()?['trialCount'] ?? 0;
          });
        }
      } else {
        await FirebaseFirestore.instance.collection('devices').doc(deviceId!).set({
          'trialCount': 0,
          'isPro': false,
          'lastUsed': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Lỗi kết nối Firebase Thiết bị: $e");
    }
  }

  void _showPaymentDialog() {
    String bankId = "TPB"; 
    String accountNo = "05805024701"; 
    String amount = "339000"; 
    String description = "PRO $deviceId"; 
    
    String encodedDesc = Uri.encodeComponent(description);
    String qrUrl = "https://img.vietqr.io/image/$bankId-$accountNo-compact.png?amount=$amount&addInfo=$encodedDesc";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Nâng cấp FIND TARGET PRO", textAlign: TextAlign.center),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView( 
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Bạn đã hết 150 lượt dùng thử.\nQuét mã QR dưới đây để thanh toán nâng cấp PRO:", textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
                const SizedBox(height: 15),
                Screenshot(
                  controller: _screenshotController,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: Image.network(qrUrl, height: 180, width: 180), 
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade800,
                    elevation: 0,
                  ),
                  onPressed: () async {
                    try {
                      final image = await _screenshotController.capture();
                      if (image != null) {
                        final tempDir = await getTemporaryDirectory();
                        final file = await File('${tempDir.path}/thanh_toan_qr.png').create();
                        await file.writeAsBytes(image);
                        await Gal.putImage(file.path); 
                        _showMsg("Đã lưu mã QR vào thư viện ảnh!");
                      }
                    } catch (e) {
                      _showMsg("Lỗi tải ảnh. Vui lòng cấp quyền bộ nhớ.");
                    }
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text("Tải mã QR về máy", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                const Divider(),
                const Text("Ngân hàng: TPBank", style: TextStyle(fontSize: 12)),
                const Text("Chủ TK: DO NGOC KHOA", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text("Giá: 339.000 VNĐ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                const SizedBox(height: 10),
                SelectableText("Mã máy: $deviceId", style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                const Text("(Vui lòng giữ nguyên nội dung chuyển khoản)", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Để sau")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _checkStatus(); 
              _showMsg("Đang cập nhật trạng thái PRO...");
            }, 
            child: const Text("Đã thanh toán")
          ),
        ],
      ),
    );
  }

  bool _isActionBlocked() {
    if (isPro) return false; 
    if (!allowTrialFromServer) return true; 
    if (trialCount >= maxTrial) return true; 
    return false;
  }

  Future<void> _requestOverlayPermission() async {
    bool status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) await FlutterOverlayWindow.requestPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceStatusStreamSubscription?.cancel();
    _resetSwitchTimer?.cancel(); 
    _mapController.dispose();
    _searchCtrl.dispose();
    for (var b in beacons) b.dispose();
    super.dispose();
  }

  Future<void> _switchToTargetApp() async {
    if (targetAppPackage == null || targetAppPackage!.isEmpty) return;
    
    if (_isOverlayActive) {
      FlutterOverlayWindow.shareData('to_target');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('overlay_is_returning', true);

    await Future.delayed(const Duration(milliseconds: 500)); 
    
    try {
      final Uri uri1 = Uri.parse("intent:#Intent;action=android.intent.action.MAIN;package=$targetAppPackage;launchFlags=0x10020000;end");
      if (await launchUrl(uri1, mode: LaunchMode.externalApplication)) return;
    } catch (e) {}

    try {
      final Uri uri2 = Uri.parse("intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;package=$targetAppPackage;launchFlags=0x10100000;end");
      if (await launchUrl(uri2, mode: LaunchMode.externalApplication)) return;
    } catch (e) {}
    
    try {
       await InstalledApps.startApp(targetAppPackage!);
    } catch (e) {
       print("Lỗi chuyển app: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      int currentFocus = beacons.indexWhere((b) => b.focusNode.hasFocus);
      if (currentFocus != -1) {
        _lastFocusedIndex = currentFocus;
        FocusManager.instance.primaryFocus?.unfocus();
      } else if (selectedIndex != null) {
        _lastFocusedIndex = selectedIndex; 
      } else if (beacons.isNotEmpty) {
        _lastFocusedIndex = beacons.length - 1;
      }
    } else if (state == AppLifecycleState.resumed) {
      _checkMockOnResume();
      _checkGpsOnResume();
      
      FlutterOverlayWindow.isActive().then((val) {
        if (mounted) setState(() => _isOverlayActive = val);
      });
      
      if (_isOverlayActive) {
        FlutterOverlayWindow.shareData('to_main');
      }

      if (_lastFocusedIndex != null && _lastFocusedIndex! < beacons.length) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            beacons[_lastFocusedIndex!].focusNode.requestFocus();
            SystemChannels.textInput.invokeMethod('TextInput.show');
            _lastFocusedIndex = null; 
          }
        });
      }
    }
  }

  double _getRadiusInMeters(Beacon b) {
    double inputVal = double.tryParse(b.controller.text.replaceAll(',', '.')) ?? 0;
    if (inputVal == 0) return 0;
    return inputVal * unitToMeter[b.unit]!;
  }

  void _zoomToFitAll() {
    if (beacons.isEmpty) return;

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;
    bool hasValid = false;

    for (var b in beacons) {
      if (b.location == null) continue;
      hasValid = true;

      double r = _getRadiusInMeters(b);
      if (r <= 0) r = 100; 

      double latBuffer = r / 111000.0;
      double lngBuffer = r / (111000.0 * cos(_toRadians(b.location!.latitude)));

      double top = b.location!.latitude + latBuffer;
      double bottom = b.location!.latitude - latBuffer;
      double right = b.location!.longitude + lngBuffer;
      double left = b.location!.longitude - lngBuffer;

      if (bottom < minLat) minLat = bottom;
      if (top > maxLat) maxLat = top;
      if (left < minLng) minLng = left;
      if (right > maxLng) maxLng = right;
    }

    if (!hasValid) {
      if (myRealLocation != null) {
         _mapController.move(myRealLocation!, 15);
      }
      return;
    }

    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
          padding: const EdgeInsets.all(50), 
        ),
      );
    } catch(e) {
      print("Lỗi fit camera");
    }
  }

  Future<void> _updateCurrentInfo(LatLng pos) async {
    setState(() {
      coordDisplay = "${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
      addressDisplay = "Đang lấy địa chỉ...";
      addressColor = Colors.blue;
    });

    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=18&addressdetails=1');
      final response = await http.get(url, headers: {'User-Agent': 'TrilaterationApp_Mock_v1'});
      
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        String addr = data['display_name'] ?? "Không tìm thấy tên đường";
        if (mounted) {
          setState(() {
            addressDisplay = addr;
            addressColor = Colors.black87;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          addressDisplay = "Lỗi mạng hoặc server";
          addressColor = Colors.red;
        });
      }
    }
  }

  void _showAppLinkOptions() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Tùy chọn App liên kết", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.blue),
              title: const Text("Đổi App liên kết"),
              onTap: () {
                Navigator.pop(ctx);
                _pickTargetApp();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_off, color: Colors.red),
              title: const Text("Hủy liên kết App", style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                setState(() {
                  targetAppPackage = null;
                });
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('target_app_package');
                FlutterOverlayWindow.shareData('update_packages'); 
                if (await FlutterOverlayWindow.isActive()) {
                  await FlutterOverlayWindow.closeOverlay();
                  setState(() => _isOverlayActive = false);
                }
                _showMsg("Đã xóa liên kết App và tắt nút nổi!");
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTargetApp() async {
    _showMsg("Đang quét danh sách ứng dụng...");
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps();
      
      apps.sort((a, b) {
        String nameA = (a.name ?? "").toLowerCase();
        String nameB = (b.name ?? "").toLowerCase();
        
        bool isHeeSayA = nameA.contains("heesay");
        bool isHeeSayB = nameB.contains("heesay");
        
        if (isHeeSayA && !isHeeSayB) return -1;
        if (!isHeeSayA && isHeeSayB) return 1;
        
        return nameA.compareTo(nameB);
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Chọn App để liên kết"),
          content: SizedBox(
            width: double.maxFinite, height: 400,
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                AppInfo app = apps[index];
                return ListTile(
                  leading: SizedBox(
                    width: 40, 
                    height: 40,
                    child: app.icon != null && app.icon!.isNotEmpty
                        ? Image.memory(
                            app.icon!,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const Icon(Icons.android, size: 30, color: Colors.grey),
                          )
                        : const Icon(Icons.android, size: 30, color: Colors.grey),
                  ),
                  title: Text(app.name ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(app.packageName ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                  onTap: () async {
                    setState(() => targetAppPackage = app.packageName);
                    await _saveTargetApp(app.packageName!);
                    FlutterOverlayWindow.shareData('update_packages'); 
                    Navigator.pop(ctx);
                    _showMsg("Đã liên kết: ${app.name}");
                    if (_autoShowOverlay) {
                      _showInvincibleOverlay(); 
                    }
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) { _showMsg("Lỗi lấy danh sách app"); }
  }

  void _showSecondAppLinkOptions() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Tùy chọn App phụ", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.blue),
              title: const Text("Đổi App phụ"),
              onTap: () {
                Navigator.pop(ctx);
                _pickSecondTargetApp();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_off, color: Colors.red),
              title: const Text("Hủy liên kết App phụ", style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                setState(() => secondTargetAppPackage = null);
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('second_target_app_package');
                FlutterOverlayWindow.shareData('update_packages'); 
                _showMsg("Đã xóa liên kết App phụ!");
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSecondTargetApp() async {
    _showMsg("Đang quét danh sách ứng dụng...");
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps();
      apps.sort((a, b) {
        if (a.packageName == 'com.khoa.photo_note_map') return -1;
        if (b.packageName == 'com.khoa.photo_note_map') return 1;
        return (a.name ?? "").toLowerCase().compareTo((b.name ?? "").toLowerCase());
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Chọn App phụ để mở nhanh"),
          content: SizedBox(
            width: double.maxFinite, height: 400,
            child: ListView.builder(
              itemCount: apps.length,
              itemBuilder: (context, index) {
                AppInfo app = apps[index];
                return ListTile(
                  leading: SizedBox(
                    width: 40, height: 40,
                    child: app.icon != null && app.icon!.isNotEmpty
                        ? Image.memory(app.icon!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.android, size: 30, color: Colors.grey))
                        : const Icon(Icons.android, size: 30, color: Colors.grey),
                  ),
                  title: Text(app.name ?? "Unknown", maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(app.packageName ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
                  onTap: () async {
                    setState(() => secondTargetAppPackage = app.packageName);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('second_target_app_package', app.packageName!);
                    FlutterOverlayWindow.shareData('update_packages'); 
                    Navigator.pop(ctx);
                    _showMsg("Đã liên kết App phụ: ${app.name}");
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) { _showMsg("Lỗi lấy danh sách app"); }
  }

  Future<void> _triggerOverlay() async {
    if (targetAppPackage == null) {
      _showMsg("Chưa chọn App! Vui lòng chọn App trước.");
      _pickTargetApp();
      return;
    }

    setState(() {
      _autoShowOverlay = !_autoShowOverlay;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_show_overlay', _autoShowOverlay);

    if (_autoShowOverlay) {
      await _showInvincibleOverlay();
      FlutterOverlayWindow.shareData('show'); 
      setState(() => _isOverlayActive = true);
      _showMsg("Đã BẬT tự động hiện nút nổi");
    } else {
      bool isActive = await FlutterOverlayWindow.isActive();
      if (isActive) {
        await FlutterOverlayWindow.closeOverlay();
        setState(() => _isOverlayActive = false);
      }
      _showMsg("Đã TẮT tự động hiện nút nổi");
    }
  }

  Future<void> _showInvincibleOverlay() async {
    if (await FlutterOverlayWindow.isActive()) {
      setState(() => _isOverlayActive = true);
      FlutterOverlayWindow.shareData('show'); 
      return;
    }
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      flag: OverlayFlag.defaultFlag, 
      visibility: NotificationVisibility.visibilitySecret,
      alignment: OverlayAlignment.centerLeft, 
      positionGravity: PositionGravity.none,
      height: 300, 
      width: 100,  
      startPosition: const OverlayPosition(0, -100),
    );
    setState(() => _isOverlayActive = true);
  }

  Future<void> _setMock(double lat, double lng, {bool fromTarget = false}) async {
    if (_isActionBlocked()) {
      _showPaymentDialog(); 
      return; 
    }

    if (!isPro) {
      trialCount++;
      if (deviceId != null) {
         await FirebaseFirestore.instance.collection('devices').doc(deviceId!).set({
           'trialCount': trialCount,
           'lastUsed': FieldValue.serverTimestamp(),
         }, SetOptions(merge: true)).catchError((e) {
           print("Lỗi lưu lên Firebase: $e");
         });
      }
      setState(() {}); 
    }

    try { 
      await platform.invokeMethod('setMockLocation', {"lat": lat, "lng": lng}); 
    } catch (e) { 
      print("Lỗi Mock: $e"); 
      bool isGranted = await platform.invokeMethod('checkMockPermission');
      if (!isGranted) {
         _stopMock();
         _showMockPermissionDialog();
         return; 
      }
    }
    
    if (targetAppPackage != null && targetAppPackage!.isNotEmpty) {
      if (_autoShowOverlay) {
        if (!_isOverlayActive) {
           await _showInvincibleOverlay();
        } else {
           FlutterOverlayWindow.shareData('show');
        }
      }
    }
    
    _updateCurrentInfo(LatLng(lat, lng));

    if (mounted) {
      setState(() {
        isMockingTarget = fromTarget;
        if (fromTarget && targetPoints.isNotEmpty) {
           _mapController.move(targetPoints[0], 17);
        }
      });
    }
  }

  Future<void> _stopMock() async {
    try { 
      await platform.invokeMethod('stopMockLocation'); 
      if (mounted) { setState(() { isMockingTarget = false; selectedIndex = null; }); }
      _showMsg("Đã dừng Mock");
    } catch (e) { print(e); }
  }

  double _toRadians(double degree) => degree * pi / 180.0;
  double _toDegrees(double radian) => radian * 180.0 / pi;

  // Tính khoảng cách phẳng Local Tangent Plane (Độ chính xác tuyệt đối ở cự ly hẹp)
  double _calculateExactDistance(LatLng p1, LatLng p2) {
    double latMid = _toRadians((p1.latitude + p2.latitude) / 2.0);
    double mPerDegLat = 111132.92 - 559.82 * cos(2 * latMid) + 1.175 * cos(4 * latMid);
    double mPerDegLng = 111412.84 * cos(latMid) - 93.5 * cos(3 * latMid);
    double dx = (p2.longitude - p1.longitude) * mPerDegLng;
    double dy = (p2.latitude - p1.latitude) * mPerDegLat;
    return sqrt(dx * dx + dy * dy);
  }

  double _calculateBearing(LatLng start, LatLng end) {
    double startLat = _toRadians(start.latitude);
    double startLng = _toRadians(start.longitude);
    double endLat = _toRadians(end.latitude);
    double endLng = _toRadians(end.longitude);
    double dLng = endLng - startLng;
    double y = sin(dLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);
    double bearing = atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360; 
  }

  LatLng _calculatePointFromBearing(LatLng start, double distanceMeters, double bearingDegrees) {
    if (distanceMeters < 50000) { 
      double latMid = _toRadians(start.latitude);
      double mPerDegLat = 111132.92 - 559.82 * cos(2 * latMid) + 1.175 * cos(4 * latMid);
      double mPerDegLng = 111412.84 * cos(latMid) - 93.5 * cos(3 * latMid);
      
      double dx = distanceMeters * sin(_toRadians(bearingDegrees));
      double dy = distanceMeters * cos(_toRadians(bearingDegrees));
      
      return LatLng(start.latitude + dy / mPerDegLat, start.longitude + dx / mPerDegLng);
    } else { 
      double bearingRad = _toRadians(bearingDegrees); 
      double startLat = _toRadians(start.latitude);
      double startLng = _toRadians(start.longitude);
      double distRatio = distanceMeters / earthRadius;
      
      double endLat = asin(sin(startLat) * cos(distRatio) + cos(startLat) * sin(distRatio) * cos(bearingRad));
      double endLng = startLng + atan2(sin(bearingRad) * sin(distRatio) * cos(startLat), cos(distRatio) - sin(startLat) * sin(endLat));
      return LatLng(_toDegrees(endLat), _toDegrees(endLng));
    }
  }

  List<LatLng> _calculateTwoCircleIntersectionPrecise(LatLng p1, double r1, LatLng p2, double r2) {
    double latMid = _toRadians((p1.latitude + p2.latitude) / 2.0);
    double mPerDegLat = 111132.92 - 559.82 * cos(2 * latMid) + 1.175 * cos(4 * latMid);
    double mPerDegLng = 111412.84 * cos(latMid) - 93.5 * cos(3 * latMid);

    double dx = (p2.longitude - p1.longitude) * mPerDegLng;
    double dy = (p2.latitude - p1.latitude) * mPerDegLat;
    double d = sqrt(dx * dx + dy * dy);

    double tolerance = 2.0;
    if (d == 0 || d > r1 + r2 + tolerance || d < (r1 - r2).abs() - tolerance) {
      return []; 
    }

    double a = (r1 * r1 - r2 * r2 + d * d) / (2 * d);
    double hSquare = r1 * r1 - a * a;
    double h = hSquare > 0 ? sqrt(hSquare) : 0.0;

    double cx = dx * a / d;
    double cy = dy * a / d;

    double px1 = cx - dy * h / d;
    double py1 = cy + dx * h / d;
    
    double px2 = cx + dy * h / d;
    double py2 = cy - dx * h / d;

    LatLng k1 = LatLng(p1.latitude + py1 / mPerDegLat, p1.longitude + px1 / mPerDegLng);
    LatLng k2 = LatLng(p1.latitude + py2 / mPerDegLat, p1.longitude + px2 / mPerDegLng);

    return [k1, k2];
  }

  LatLng? _internalCalculateBestFit() {
      var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
      if (validBeacons.length < 2) return null;
      return _calculateBestFit(validBeacons);
  }

  LatLng _optimizePoint(LatLng startPoint, List<Beacon> beacons) {
    LatLng currentPos = startPoint;
    double stepSize = 0.00005; 
    double minStep = 0.000000001; 
    int maxIterations = 2000; 
    int iter = 0;

    while (stepSize > minStep && iter < maxIterations) {
      iter++;
      LatLng bestNeighbor = currentPos;
      double minError = _calculateTotalError(currentPos, beacons);
      bool improved = false;

      List<LatLng> neighbors = [
        LatLng(currentPos.latitude + stepSize, currentPos.longitude),
        LatLng(currentPos.latitude - stepSize, currentPos.longitude),
        LatLng(currentPos.latitude, currentPos.longitude + stepSize),
        LatLng(currentPos.latitude, currentPos.longitude - stepSize),
        LatLng(currentPos.latitude + stepSize, currentPos.longitude + stepSize),
        LatLng(currentPos.latitude - stepSize, currentPos.longitude - stepSize),
        LatLng(currentPos.latitude + stepSize, currentPos.longitude - stepSize),
        LatLng(currentPos.latitude - stepSize, currentPos.longitude + stepSize),
      ];

      for (var p in neighbors) {
        double err = _calculateTotalError(p, beacons);
        if (err < minError) {
          minError = err;
          bestNeighbor = p;
          improved = true;
        }
      }

      if (improved) {
        currentPos = bestNeighbor;
      } else {
        stepSize /= 2.0; 
      }
    }
    return currentPos;
  }

  double _calculateTotalError(LatLng p, List<Beacon> beacons) {
    double totalError = 0;
    for (var b in beacons) {
      if (b.location == null) continue;
      
      double d = _calculateExactDistance(p, b.location!);
      double r = _getRadiusInMeters(b);
      if (r <= 0) continue; 
      
      double err = (d - r).abs();
      
      // Trọng số thông minh: Mốc càng gần thì trọng số càng cao (ép mục tiêu bám chặt mốc gần)
      double weight = 1.0 / ((r / 200.0) + 1.0); 
      
      totalError += err * err * weight; 
    }
    return totalError;
  }

  LatLng? _calculateBestFit(List<Beacon> validBeacons) {
    if (validBeacons.length < 2) return null;

    List<LatLng> allRoots = [];
    
    for (int i = 0; i < validBeacons.length - 1; i++) {
        for (int j = i + 1; j < validBeacons.length; j++) {
            double r1 = _getRadiusInMeters(validBeacons[i]);
            double r2 = _getRadiusInMeters(validBeacons[j]);
            var roots = _calculateTwoCircleIntersectionPrecise(validBeacons[i].location!, r1, validBeacons[j].location!, r2);
            allRoots.addAll(roots);
        }
    }

    LatLng bestStartNode;
    
    if (allRoots.isEmpty) {
      var p1 = validBeacons[0];
      double r1 = _getRadiusInMeters(p1);
      if (r1 <= 0) r1 = 10; 

      List<LatLng> candidates = [
        _calculatePointFromBearing(p1.location!, r1, 0),   
        _calculatePointFromBearing(p1.location!, r1, 90),  
        _calculatePointFromBearing(p1.location!, r1, 180), 
        _calculatePointFromBearing(p1.location!, r1, 270), 
      ];

      double minE = double.infinity;
      bestStartNode = candidates[0];
      for (var c in candidates) {
        double e = _calculateTotalError(c, validBeacons);
        if (e < minE) {
          minE = e;
          bestStartNode = c;
        }
      }
    } else {
      double minE = double.infinity;
      bestStartNode = allRoots[0];
      for (var root in allRoots) {
          double e = _calculateTotalError(root, validBeacons);
          if (e < minE) {
              minE = e;
              bestStartNode = root;
          }
      }
    }
    
    return _optimizePoint(bestStartNode, validBeacons);
  }

  void _requestFocus(int index) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (index >= 0 && index < beacons.length) {
        beacons[index].focusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show'); 
      }
    });
  }

  Future<void> _assignSavedTargetToP(LatLng location) async {
    int targetIndex = -1;
    String unitToUse = 'km'; 
    if (beacons.isNotEmpty) unitToUse = beacons.last.unit;

    for (int i = 0; i < beacons.length; i++) {
      if (beacons[i].location == null) { targetIndex = i; break; }
    }
    setState(() {
      if (targetIndex != -1) {
        beacons[targetIndex].location = location;
      } else {
        beacons.add(Beacon(location: location, color: colorPalette[beacons.length % colorPalette.length], unit: unitToUse));
        targetIndex = beacons.length - 1;
      }
      targetPoints.clear();
      selectedIndex = targetIndex;
      isMockingTarget = false;
      searchMarker = null;
      _mapController.move(location, 17);
    });
    _requestFocus(targetIndex); 
    await _setMock(location.latitude, location.longitude);
    _showMsg("Đang chạy ${_getBeaconName(targetIndex)}");
  }

  double _calculateOptimalBearing(LatLng center, int currentIndex) {
    List<double> existingBearings = [];
    for (int i = 0; i < beacons.length; i++) {
      if (i == currentIndex) continue;
      if (beacons[i].location != null && beacons[i].location != center) {
        double b = _calculateBearing(center, beacons[i].location!);
        existingBearings.add(b);
      }
    }
    if (existingBearings.isEmpty) return Random().nextDouble() * 360.0;
    existingBearings.sort();
    double maxGap = 0;
    double bestStartAngle = 0;
    for (int i = 0; i < existingBearings.length; i++) {
      double current = existingBearings[i];
      double next = existingBearings[(i + 1) % existingBearings.length];
      double gap = (next - current + 360) % 360;
      if (gap > maxGap) { maxGap = gap; bestStartAngle = current; }
    }
    return (bestStartAngle + maxGap / 2) % 360;
  }

  Future<void> _smartSetLocation(int index) async {
    if (selectedIndex == index) { _stopMock(); return; }
    
    if (index < beacons.length - 1) {
      for (int i = index + 1; i < beacons.length; i++) {
        beacons[i].dispose();
      }
      setState(() {
        beacons.removeRange(index + 1, beacons.length);
      });
    }

    _requestFocus(index); 
    try {
      LatLng finalPos;
      if (beacons[index].location != null) {
          finalPos = beacons[index].location!;
      } 
      else {
        int bestReferenceIndex = -1;
        double minDistance = double.infinity;
        for (int i = 0; i < beacons.length; i++) {
          if (i == index) continue;
          if (beacons[i].location != null && beacons[i].controller.text.isNotEmpty) {
             double? dist = double.tryParse(beacons[i].controller.text.replaceAll(',', '.'));
             if (dist != null && dist > 0 && dist < minDistance) {
                 minDistance = dist;
                 bestReferenceIndex = i;
             }
          }
        }

        if (bestReferenceIndex == -1) {
          Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          finalPos = LatLng(p.latitude, p.longitude);
        } else {
          LatLng baseLoc = beacons[bestReferenceIndex].location!;
          double distMeters = _getRadiusInMeters(beacons[bestReferenceIndex]);
          double optimalBearing = _calculateOptimalBearing(baseLoc, index);
          finalPos = _calculatePointFromBearing(baseLoc, distMeters, optimalBearing);
        }
      }

      setState(() {
        beacons[index].location = finalPos;
        selectedIndex = index;
        targetPoints.clear(); 
        isMockingTarget = false;
        if (myRealLocation == null && index == 0) { myRealLocation = finalPos; }
      });
      _mapController.move(finalPos, 16);
      await _setMock(finalPos.latitude, finalPos.longitude);
    } catch (e) { _showMsg("Lỗi"); }
  }

  Future<void> _resetCurrentBeacon() async {
    if (selectedIndex == null) {
      _showMsg("Chưa chọn điểm nào để tính lại!");
      return;
    }
    
    int originalIndex = selectedIndex!;
    int targetIndex = originalIndex;
    bool isFixingNext = false;
    
    if (originalIndex < beacons.length - 1) {
      targetIndex = originalIndex + 1;
      isFixingNext = true;
    }

    List<Beacon> otherBeacons = [];
    for (int i = 0; i < beacons.length; i++) {
      if (i != targetIndex && beacons[i].location != null && beacons[i].controller.text.isNotEmpty) {
        double? d = double.tryParse(beacons[i].controller.text.replaceAll(',', '.'));
        if (d != null && d > 0) {
          otherBeacons.add(beacons[i]);
        }
      }
    }

    LatLng? newPos;

    if (otherBeacons.length >= 3) {
      newPos = _calculateBestFit(otherBeacons);
    } else if (otherBeacons.length == 2) {
      var b1 = otherBeacons[0];
      var b2 = otherBeacons[1];
      double r1 = _getRadiusInMeters(b1);
      double r2 = _getRadiusInMeters(b2);

      List<LatLng> intersections = _calculateTwoCircleIntersectionPrecise(b1.location!, r1, b2.location!, r2);

      if (intersections.isNotEmpty) {
        if (intersections.length == 2 && beacons[targetIndex].location != null) {
          LatLng currentPos = beacons[targetIndex].location!;
          double d1 = _calculateExactDistance(currentPos, intersections[0]);
          double d2 = _calculateExactDistance(currentPos, intersections[1]);
          
          if (!isFixingNext) {
             newPos = (d1 > d2) ? intersections[0] : intersections[1]; 
          } else {
             newPos = (d1 < d2) ? intersections[0] : intersections[1]; 
          }
        } else {
          newPos = intersections[0];
        }
      }
    } else if (otherBeacons.length == 1) {
      var ref = otherBeacons[0];
      double r = _getRadiusInMeters(ref);
      if (beacons[targetIndex].location != null) {
        double currentBearing = _calculateBearing(ref.location!, beacons[targetIndex].location!);
        double newBearing = (currentBearing + 80.0) % 360.0;
        newPos = _calculatePointFromBearing(ref.location!, r, newBearing);
      } else {
        newPos = _calculatePointFromBearing(ref.location!, r, 0);
      }
    }

    if (newPos != null) {
      setState(() {
        beacons[targetIndex].location = newPos!;
        selectedIndex = targetIndex; 
        targetPoints.clear();
      });
      
      FocusManager.instance.primaryFocus?.unfocus(); 
      
      _mapController.move(newPos, _mapController.camera.zoom);
      await _setMock(newPos.latitude, newPos.longitude);
      _zoomToFitAll();
      
      if (!isFixingNext) {
         if (otherBeacons.length >= 3) {
            _showMsg("Đã tính lại vị trí chính xác!");
         } else if (otherBeacons.length == 2) {
            _showMsg("Đã đảo vị trí K1/K2 thành công!");
         } else {
            _showMsg("Đã xoay điểm thêm 80 độ!");
         }
      } else {
         _showMsg("Đã cập nhật lại vị trí ${_getBeaconName(targetIndex)}!");
      }
      
      if (!isFixingNext && otherBeacons.length == 1) {
        _resetSwitchTimer?.cancel();
        _resetSwitchTimer = Timer(const Duration(milliseconds: 1500), () async {
          _requestFocus(targetIndex); 
          await _switchToTargetApp();
        });
      } else {
        _requestFocus(targetIndex); 
        await _switchToTargetApp(); 
      }
    } else {
      _showMsg("Không đủ dữ liệu để tính lại! Cần ít nhất 1-2 điểm khác.");
    }
  }

  void _autoSaveLastTargetBeforeClearing() {
    LatLng? lastTarget;
    
    if (selectedIndex != null && selectedIndex! >= 3 && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) {
      lastTarget = beacons[selectedIndex!].location;
    } else {
      for (int i = beacons.length - 1; i >= 3; i--) {
        if (beacons[i].location != null) {
          lastTarget = beacons[i].location;
          break;
        }
      }
    }

    if (lastTarget != null) {
      String timeStr = "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
      String dateStr = "${DateTime.now().day}/${DateTime.now().month}";
      String name = "Mục tiêu ($timeStr - $dateStr)";
      
      bool isDuplicate = historyTargets.any((t) => 
         t.location.latitude == lastTarget!.latitude && 
         t.location.longitude == lastTarget!.longitude);

      if (!isDuplicate) {
        setState(() {
          historyTargets.insert(0, SavedTarget(location: lastTarget!, name: name, timestamp: DateTime.now(), address: addressDisplay));
          if (historyTargets.length > 20) {
            historyTargets = historyTargets.sublist(0, 20);
          }
        });
        _saveData();
      }
    }
  }

  Future<void> _restartWithResultAsP1(int fromIndex) async {
    _autoSaveLastTargetBeforeClearing(); 

    LatLng? newStart;
    String distToKeep = "";
    String unitToKeep = 'km';

    if (fromIndex >= 0 && fromIndex < beacons.length && beacons[fromIndex].location != null) {
        newStart = beacons[fromIndex].location;
        distToKeep = beacons[fromIndex].controller.text;
        unitToKeep = beacons[fromIndex].unit;
    } else if (isMockingTarget && targetPoints.isNotEmpty) { 
        newStart = targetPoints[0]; 
    } else if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) { 
        newStart = beacons[selectedIndex!].location; 
        distToKeep = beacons[selectedIndex!].controller.text;
        unitToKeep = beacons[selectedIndex!].unit;
    } else {
        newStart = myRealLocation ?? _mapController.camera.center;
    }

    if (newStart == null) { _showMsg("Chưa có tọa độ nào để gán!"); return; }

    setState(() {
      defaultUnit = unitToKeep; 
      beacons = [Beacon(location: newStart, dist: distToKeep, color: Colors.blue, unit: unitToKeep)];
      targetPoints.clear();
      coordDisplay = "0.000000, 0.000000";
      addressDisplay = "Chưa có vị trí";
      searchMarker = null;
      selectedIndex = 0; 
      isMockingTarget = false;
    });
    
    _mapController.move(newStart, 16);
    await _setMock(newStart.latitude, newStart.longitude);
    _showMsg("Đã gán và chạy Mốc 1 mới!");

    if (distToKeep.isNotEmpty) {
        await _addNewBeacon();
    } else {
        _requestFocus(0); 
    }
  }

  Future<void> _searchLocation() async {
    String query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    
    final coordRegExp = RegExp(r'^([-+]?\d+(?:[\.,]\d+)?)\s*[,;\s]+\s*([-+]?\d+(?:[\.,]\d+)?)$');
    final match = coordRegExp.firstMatch(query);
    
    if (match != null) {
      double lat = double.parse(match.group(1)!.replaceAll(',', '.'));
      double lng = double.parse(match.group(2)!.replaceAll(',', '.'));
      LatLng pos = LatLng(lat, lng);
      
      _mapController.move(pos, 15);
      setState(() { isSearchVisible = false; });
      await _assignSavedTargetToP(pos); 
      FocusScope.of(context).unfocus();
      return;
    }
    
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1');
      final response = await http.get(url, headers: {'User-Agent': 'TrilaterationApp_Mock_v1'});
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          double lat = double.parse(data[0]['lat']);
          double lon = double.parse(data[0]['lon']);
          LatLng pos = LatLng(lat, lon);
          
          _mapController.move(pos, 15);
          setState(() { isSearchVisible = false; });
          await _assignSavedTargetToP(pos); 
          FocusScope.of(context).unfocus();
        } else { _showMsg("Không tìm thấy địa điểm"); }
      }
    } catch (e) { _showMsg("Lỗi kết nối"); }
  }

  void _saveCurrentTarget() {
    LatLng? pointToSave;
    String defaultName = "";
    if (isMockingTarget && targetPoints.isNotEmpty) { pointToSave = targetPoints[0]; defaultName = "Mục tiêu đã lưu ${savedTargets.length + 1}"; } 
    else if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) { pointToSave = beacons[selectedIndex!].location; defaultName = _getBeaconName(selectedIndex!); }
    else if (targetPoints.isNotEmpty) { pointToSave = targetPoints[0]; defaultName = "Mục tiêu đã lưu ${savedTargets.length + 1}"; }

    if (pointToSave == null) { _showMsg("Không có tọa độ đang chạy để lưu!"); return; }
    TextEditingController nameCtrl = TextEditingController(text: defaultName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Lưu vị trí hiện tại"),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Tên điểm")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
          ElevatedButton(onPressed: () {
            setState(() => savedTargets.add(SavedTarget(location: pointToSave!, name: nameCtrl.text, timestamp: DateTime.now(), address: addressDisplay)));
            _saveData(); Navigator.pop(ctx); _showMsg("Đã lưu!");
          }, child: const Text("LƯU")),
        ],
      ),
    );
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    
    String encodedSaved = jsonEncode(savedTargets.map((e) => e.toJson()).toList());
    await prefs.setString('saved_targets', encodedSaved);
    
    String encodedHistory = jsonEncode(historyTargets.map((e) => e.toJson()).toList());
    await prefs.setString('history_targets', encodedHistory);
  }
   
  Future<void> _saveTargetApp(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('target_app_package', packageName);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    String? encodedSaved = prefs.getString('saved_targets');
    if (encodedSaved != null) {
      Iterable l = jsonDecode(encodedSaved);
      setState(() { savedTargets = List<SavedTarget>.from(l.map((model) => SavedTarget.fromJson(model))); });
    }

    String? encodedHistory = prefs.getString('history_targets');
    if (encodedHistory != null) {
      Iterable l = jsonDecode(encodedHistory);
      setState(() { historyTargets = List<SavedTarget>.from(l.map((model) => SavedTarget.fromJson(model))); });
    }

    String? pkg = prefs.getString('target_app_package');
    if (pkg != null) setState(() => targetAppPackage = pkg);
    
    String? secondPkg = prefs.getString('second_target_app_package');
    if (secondPkg != null) setState(() => secondTargetAppPackage = secondPkg);

    bool? autoOverlay = prefs.getBool('auto_show_overlay');
    if (autoOverlay != null) setState(() => _autoShowOverlay = autoOverlay);
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    while (true) {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        _isGpsDialogShowing = true;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false, 
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Text("Bắt Buộc Bật GPS", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              content: const Text("Ứng dụng cần bạn bật Dịch vụ vị trí (GPS) để có thể định vị bản đồ và tính toán tọa độ.\n\nVui lòng bật GPS để có thể tiếp tục sử dụng app.", textAlign: TextAlign.center),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () async {
                    await Geolocator.openLocationSettings();
                  },
                  child: const Text("Mở Cài đặt GPS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Đã bật, thử lại"),
                )
              ],
            ),
          )
        );
        _isGpsDialogShowing = false;
        continue; 
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => PopScope(
              canPop: false, 
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                title: const Text("Bắt Buộc Cấp Quyền", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                content: const Text("Bạn cần cấp quyền truy cập vị trí thì ứng dụng mới lấy được tọa độ hiện tại của bạn để làm Mốc tính toán.", textAlign: TextAlign.center),
                actionsAlignment: MainAxisAlignment.center,
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    onPressed: () => Navigator.pop(ctx), 
                    child: const Text("Cấp quyền ngay", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            )
          );
          continue; 
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Text("Quyền Vị Trí Bị Chặn", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              content: const Text("Bạn đã từ từ chối quyền vị trí vĩnh viễn.\n\nVui lòng nhấn vào nút bên dưới để mở Cài đặt ứng dụng -> Chọn 'Quyền' -> Cấp quyền 'Vị trí' để có thể dùng app.", textAlign: TextAlign.center),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () async {
                    await Geolocator.openAppSettings();
                  },
                  child: const Text("Mở Cài đặt App", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Đã cấp quyền, thử lại"),
                )
              ],
            ),
          )
        );
        continue;
      }

      break; 
    }

    Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    LatLng current = LatLng(p.latitude, p.longitude);

    if (mounted) {
      setState(() {
        myRealLocation = current;
        _isLoadingLocation = false; 
      });
      if (selectedIndex == null && targetPoints.isEmpty) {
        _mapController.move(current, 15);
      }
    }

    Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5))
        .listen((p) { 
          if (mounted) setState(() => myRealLocation = LatLng(p.latitude, p.longitude)); 
        });
  }

  Future<void> _openNavigation(LatLng destination) async {
    Uri uri = Platform.isAndroid 
      ? Uri.parse('google.navigation:q=${destination.latitude},${destination.longitude}')
      : Uri.parse('maps://?q=${destination.latitude},${destination.longitude}');
    if (await canLaunchUrl(uri)) { await launchUrl(uri); } else { _showMsg("Lỗi mở bản đồ"); }
  }

  Future<void> _viewOnMap(LatLng destination) async {
    Uri uri = Platform.isAndroid 
      ? Uri.parse('geo:${destination.latitude},${destination.longitude}?q=${destination.latitude},${destination.longitude}')
      : Uri.parse('https://maps.apple.com/?ll=${destination.latitude},${destination.longitude}&q=Vị+trí+Mock');
      
    try {
      if (await canLaunchUrl(uri)) { 
        await launchUrl(uri); 
      } else { 
        Uri webUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${destination.latitude},${destination.longitude}');
        if (await canLaunchUrl(webUri)) {
           await launchUrl(webUri);
        } else {
           _showMsg("Lỗi mở bản đồ");
        }
      }
    } catch(e) {
        _showMsg("Lỗi mở bản đồ");
    }
  }

  void _editTargetName(int index, {bool isHistory = false, VoidCallback? onEdited}) {
    var targetList = isHistory ? historyTargets : savedTargets;
    TextEditingController editCtrl = TextEditingController(text: targetList[index].name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Đổi tên"),
        content: TextField(controller: editCtrl, decoration: const InputDecoration(labelText: "Tên mới")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
          ElevatedButton(onPressed: () { 
            setState(() => targetList[index].name = editCtrl.text); 
            _saveData(); 
            Navigator.pop(ctx); 
            if (onEdited != null) onEdited();
          }, child: const Text("OK")),
        ],
      ),
    );
  }

  void _confirmDeleteTarget(int index, {VoidCallback? onDeleted, bool isHistory = false}) {
    var targetList = isHistory ? historyTargets : savedTargets;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: Text("Xóa '${targetList[index].name}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("KHÔNG")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { 
            setState(() => targetList.removeAt(index)); 
            _saveData(); 
            Navigator.pop(ctx); 
            if (onDeleted != null) onDeleted();
          }, child: const Text("XÓA", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  void _showMsg(String m) {
    ScaffoldMessenger.of(context).clearSnackBars(); 
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          m, 
          textAlign: TextAlign.center, 
          style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.1) 
        ),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black.withOpacity(0.8), 
        elevation: 0, 
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
        margin: const EdgeInsets.only(
          bottom: 20, 
          left: 20,
          right: 80, 
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      )
    );
  }

  void _showSearchOptions() {
    if (searchMarker == null) return;
    String coords = "${searchMarker!.latitude.toStringAsFixed(6)}, ${searchMarker!.longitude.toStringAsFixed(6)}";
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vị trí tìm kiếm"),
        content: Text(coords, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        actions: [
          IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 35), onPressed: () async { Navigator.pop(ctx); await _assignSavedTargetToP(searchMarker!); }),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setState(() => searchMarker = null); Navigator.pop(ctx); }),
        ],
      ),
    );
  }

  void _confirmDeleteBeacon(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Xóa ${_getBeaconName(index)}?"),
        content: const Text("Dữ liệu của điểm này sẽ bị mất."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { Navigator.pop(ctx); _deleteBeacon(index); },
            child: const Text("XÓA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteBeacon(int index) {
    setState(() {
      if (selectedIndex == index) { _stopMock(); } 
      else if (selectedIndex != null && selectedIndex! > index) { selectedIndex = selectedIndex! - 1; }
      beacons[index].dispose();
      beacons.removeAt(index);
      targetPoints.clear(); 
    });
    _showMsg("Đã xóa ${_getBeaconName(index)} cũ");
    _zoomToFitAll(); 
  }

  void _showTargetOptions(int index, {bool isHistory = false}) {
    var list = isHistory ? historyTargets : savedTargets;
    String coords = "${list[index].location.latitude.toStringAsFixed(6)}, ${list[index].location.longitude.toStringAsFixed(6)}";
    String address = list[index].address.isNotEmpty ? list[index].address : "Đang lấy địa chỉ...";
    bool fetched = list[index].address.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (!fetched) {
            fetched = true;
            final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${list[index].location.latitude}&lon=${list[index].location.longitude}&zoom=18&addressdetails=1');
            http.get(url, headers: {'User-Agent': 'TrilaterationApp_Mock_v1'}).then((response) {
              if (response.statusCode == 200) {
                var data = jsonDecode(response.body);
                setStateDialog(() { address = data['display_name'] ?? "Không tìm thấy địa chỉ"; });
              } else {
                setStateDialog(() { address = "Lỗi mạng"; });
              }
            }).catchError((e) {
               setStateDialog(() { address = "Lỗi kết nối"; });
            });
          }

          return AlertDialog(
            title: Text(list[index].name, textAlign: TextAlign.center),
            content: GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: "$coords\n$address"));
                _showMsg("Đã copy tọa độ và địa chỉ!");
                Navigator.pop(ctx);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(coords, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)),
                  const SizedBox(height: 10),
                  Text(address, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 10),
                  const Text("(Nhấn giữ để copy)", style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 32), onPressed: () async { Navigator.pop(ctx); await _assignSavedTargetToP(list[index].location); }),
              IconButton(icon: const Icon(Icons.directions, color: Colors.orange, size: 32), onPressed: () { Navigator.pop(ctx); _openNavigation(list[index].location); }),
              if (!isHistory) 
                IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 32), onPressed: () { Navigator.pop(ctx); _editTargetName(index, isHistory: isHistory); }),
              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 32), onPressed: () { Navigator.pop(ctx); _confirmDeleteTarget(index, isHistory: isHistory); }),
            ],
          );
        }
      ),
    );
  }

  void _showSavedTargetsSheet() {
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      backgroundColor: Colors.transparent, 
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20))
            ),
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                  ),
                  const TabBar(
                    labelColor: Colors.blue,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.blue,
                    labelStyle: TextStyle(fontWeight: FontWeight.bold),
                    tabs: [
                      Tab(icon: Icon(Icons.bookmark), text: "Đã lưu"),
                      Tab(icon: Icon(Icons.history), text: "Lịch sử"),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildTargetList(savedTargets, false, setModalState, ctx),
                        _buildTargetList(historyTargets, true, setModalState, ctx),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _buildTargetList(List<SavedTarget> list, bool isHistory, StateSetter setModalState, BuildContext ctx) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          isHistory ? "Chưa có lịch sử tính toán nào." : "Chưa có vị trí nào được lưu.", 
          style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)
        )
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.5),
      itemBuilder: (c, i) {
        final target = list[i];
        String coordsStr = "${target.location.latitude.toStringAsFixed(5)}, ${target.location.longitude.toStringAsFixed(5)}";
        
        String displaySub = (target.address.isNotEmpty && target.address != "Chưa có vị trí")
            ? "${target.address}\n$coordsStr"
            : coordsStr;
            
        return ListTile(
          contentPadding: const EdgeInsets.only(left: 12, right: 4), 
          visualDensity: VisualDensity.compact,
          leading: Icon(isHistory ? Icons.history : Icons.location_on, color: isHistory ? Colors.blueGrey : Colors.blue, size: 20),
          title: Text(target.name, style: TextStyle(fontWeight: isHistory ? FontWeight.normal : FontWeight.bold, fontSize: 13)),
          subtitle: Text(displaySub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.grey, height: 1.2)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isHistory)
                InkWell(
                  onTap: () { _editTargetName(i, isHistory: isHistory, onEdited: () { setModalState(() {}); }); },
                  child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.edit, color: Colors.blue, size: 18)),
                ),
              InkWell(
                onTap: () async { await _assignSavedTargetToP(target.location); Navigator.pop(ctx); },
                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.play_circle_fill, color: Colors.green, size: 18)),
              ),
              InkWell(
                onTap: () { _confirmDeleteTarget(i, isHistory: isHistory, onDeleted: () { setModalState(() {}); }); },
                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete, color: Colors.red, size: 18)),
              ),
            ],
          ),
          onTap: () { 
            _mapController.move(target.location, 15); 
            Navigator.pop(ctx); 
          },
        );
      },
    );
  }

  void _setUnitForSelectedBeacon(String unit) {
    setState(() {
      int focusedIndex = beacons.indexWhere((b) => b.focusNode.hasFocus);
      
      if (focusedIndex != -1) {
          if (focusedIndex < beacons.length - 1) {
            for (int i = focusedIndex + 1; i < beacons.length; i++) {
              beacons[i].dispose();
            }
            beacons.removeRange(focusedIndex + 1, beacons.length);
          }
          beacons[focusedIndex].unit = unit;
      } 
      else if (selectedIndex != null && selectedIndex! < beacons.length) { 
        if (selectedIndex! < beacons.length - 1) {
          for (int i = selectedIndex! + 1; i < beacons.length; i++) {
            beacons[i].dispose();
          }
          beacons.removeRange(selectedIndex! + 1, beacons.length);
        }
        beacons[selectedIndex!].unit = unit; 
      } 
      else {
        defaultUnit = unit; 
      }
    });
  }

  Future<void> _addNewBeacon() async {
    if (_isActionBlocked()) {
      _showPaymentDialog(); 
      return; 
    }

    if (beacons.isNotEmpty) {
      Beacon last = beacons.last;
      if (last.location == null || last.controller.text.trim().isEmpty) {
        _showMsg("${_getBeaconName(beacons.length - 1)} chưa hoàn thành!");
        return;
      }
      
      String distStr = last.controller.text.trim();
      if (double.tryParse(distStr) == null) {
        _showMsg("Sai định dạng số (vd: dư dấu chấm)! Vui lòng sửa lại.");
        return;
      }
    }

    String defaultNewUnit = beacons.isNotEmpty ? beacons.last.unit : defaultUnit;
    LatLng? bestK;
    LatLng? finalPoint;

    if (beacons.length >= 3) {
      bestK = _internalCalculateBestFit();

      int updatedCountM = beacons.where((b) => b.unit == 'm').length;
      int countKm = beacons.where((b) => b.unit == 'km').length;
      int countMi = beacons.where((b) => b.unit == 'mi').length;
      int countFt = beacons.where((b) => b.unit == 'ft').length;

      bool isRefereeMode = (updatedCountM == 2 && countKm == 1) || (countMi == 2 && countFt == 1);

      if (isRefereeMode) {
          String pairUnit = (updatedCountM == 2) ? 'm' : 'mi';
          var pair = beacons.where((b) => b.unit == pairUnit).toList();
          var referee = beacons.firstWhere((b) => b.unit != pairUnit);
          
          if (pair.length == 2 && pair[0].location != null && pair[1].location != null && referee.location != null) {
               var roots = _calculateTwoCircleIntersectionPrecise(
                  pair[0].location!, _getRadiusInMeters(pair[0]), 
                  pair[1].location!, _getRadiusInMeters(pair[1])
               );
               
               if (roots.length == 2) {
                   double rRef = _getRadiusInMeters(referee);
                   
                   double distRefToK1 = _calculateExactDistance(referee.location!, roots[0]);
                   double errorRadius1 = (distRefToK1 - rRef).abs();
                   double errorFit1 = bestK != null ? _calculateExactDistance(bestK, roots[0]) : 0;
                   double totalScore1 = errorRadius1 + errorFit1;

                   double distRefToK2 = _calculateExactDistance(referee.location!, roots[1]);
                   double errorRadius2 = (distRefToK2 - rRef).abs();
                   double errorFit2 = bestK != null ? _calculateExactDistance(bestK, roots[1]) : 0;
                   double totalScore2 = errorRadius2 + errorFit2;

                   finalPoint = (totalScore1 < totalScore2) ? roots[0] : roots[1];
               }
          }
      }

      if (finalPoint == null && bestK != null) {
         finalPoint = bestK;
      }

      if (finalPoint != null) {
          setState(() {
            beacons.add(Beacon(location: finalPoint, color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
            selectedIndex = beacons.length - 1;
            targetPoints.clear();
            isMockingTarget = false;
          });
          
          await _setMock(finalPoint!.latitude, finalPoint!.longitude);
          _zoomToFitAll();
          _requestFocus(beacons.length - 1); 
          await _switchToTargetApp();
          return; 
      }
    }
    
    LatLng? finalPos; 
    bool autoPlaced = false;

    if (beacons.isEmpty) {
      finalPos = myRealLocation ?? _mapController.camera.center;
      autoPlaced = true;
    }

    if (beacons.length >= 2) {
      var b1 = beacons[0];
      var b2 = beacons[1];
      if (b1.location != null && b1.controller.text.isNotEmpty &&
          b2.location != null && b2.controller.text.isNotEmpty) {
          try {
            double r1 = _getRadiusInMeters(b1);
            double r2 = _getRadiusInMeters(b2);
            List<LatLng> intersections = _calculateTwoCircleIntersectionPrecise(b1.location!, r1, b2.location!, r2);
            if (intersections.isNotEmpty) {
              finalPos = intersections[0]; 
              autoPlaced = true;
            }
          } catch (e) {}
      }
    }
    
    if (!autoPlaced) {
      int newIndex = beacons.length; 
      if (newIndex > 0) {
         Beacon prevBeacon = beacons[newIndex - 1];
         if (prevBeacon.location != null && prevBeacon.controller.text.isNotEmpty) {
                 double? r = double.tryParse(prevBeacon.controller.text.replaceAll(',', '.'));
                 if (r != null && r > 0) {
                      double distMeters = _getRadiusInMeters(prevBeacon);
                      LatLng center = prevBeacon.location!;
                      double bearing = _calculateOptimalBearing(center, newIndex);
                      finalPos = _calculatePointFromBearing(center, distMeters, bearing);
                 }
         }
      }
    }

    if (finalPos != null) {
      setState(() {
        beacons.add(Beacon(location: finalPos, color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
        selectedIndex = beacons.length - 1;
        targetPoints.clear();
        isMockingTarget = false;
      });
      await _setMock(finalPos!.latitude, finalPos!.longitude);
      _zoomToFitAll();
      await _switchToTargetApp(); 
    } else {
      setState(() {
        beacons.add(Beacon(color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
      });
    }
    _requestFocus(beacons.length - 1); 
  }

  @override
  Widget build(BuildContext context) {
    String activeUnitForChip = defaultUnit;
    int focusedIndex = beacons.indexWhere((b) => b.focusNode.hasFocus);
    
    if (focusedIndex != -1) {
      activeUnitForChip = beacons[focusedIndex].unit;
    } else if (selectedIndex != null && selectedIndex! < beacons.length) { 
      activeUnitForChip = beacons[selectedIndex!].unit;
    }

    bool isAnyMocking = isMockingTarget || selectedIndex != null;

    return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8), color: Colors.white,
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 90, 
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: beacons.length,
                            itemBuilder: (ctx, i) {
                              return Container(
                                width: 80, 
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _smartSetLocation(i),
                                      onLongPress: () => _confirmDeleteBeacon(i), 
                                      child: Container(
                                        width: double.infinity,
                                        alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 4),
                                        decoration: BoxDecoration(
                                          color: selectedIndex == i ? Colors.red : (beacons[i].location != null ? _getBeaconColor(i, beacons[i].color) : Colors.grey.shade400),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(_getBeaconName(i), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                    ),
                                    TextField(
                                      controller: beacons[i].controller, 
                                      focusNode: beacons[i].focusNode, 
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                      textInputAction: TextInputAction.done,
                                      textAlign: TextAlign.center, 
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      onTap: () {
                                        setState(() {});
                                      },
                                      onSubmitted: (val) async {
                                        String text = val.toLowerCase().trim();
                                        bool isRestartP1 = text.contains(',');
                                        
                                        String numStr = text.replaceAll(',', '').trim();
                                        
                                        if (numStr.isNotEmpty && double.tryParse(numStr) == null) {
                                            _showMsg("Sai định dạng số (vd: dư dấu chấm)!");
                                            return;
                                        }
                                        
                                        if (isRestartP1) {
                                            beacons[i].controller.text = numStr;
                                            setState(() { selectedIndex = i; });
                                            await _restartWithResultAsP1(i);
                                        } else {
                                            await _addNewBeacon();
                                        }
                                      },
                                      onChanged: (val) async {
                                        String text = val.toLowerCase();
                                        
                                        bool hasMinus = text.contains('-');
                                        bool hasSpace = text.contains(' ');
                                        bool hasK = text.contains('k');
                                        bool hasM = text.contains('m');
                                        bool hasComma = text.contains(',');

                                        if (hasMinus || hasSpace || hasK || hasM) {
                                           bool isRestartP1 = hasComma;
                                           
                                           String numStr = text.replaceAll(RegExp(r'[- km,]'), '').trim();
                                           
                                           if (numStr.isNotEmpty && double.tryParse(numStr) == null) {
                                              _showMsg("Sai định dạng số (vd: dư dấu chấm)!");
                                              beacons[i].controller.text = val;
                                              beacons[i].controller.selection = TextSelection.fromPosition(TextPosition(offset: val.length));
                                              return; 
                                           }

                                           if (i < beacons.length - 1 && !isRestartP1) {
                                             for (int j = i + 1; j < beacons.length; j++) {
                                               beacons[j].dispose();
                                             }
                                             setState(() {
                                               beacons.removeRange(i + 1, beacons.length);
                                             });
                                           }

                                           beacons[i].controller.text = numStr;
                                           beacons[i].controller.selection = TextSelection.fromPosition(TextPosition(offset: numStr.length));
                                           
                                           if (hasMinus || hasK) beacons[i].unit = 'km';
                                           if (hasSpace || hasM) beacons[i].unit = 'm';

                                           if (isRestartP1) {
                                               setState(() { selectedIndex = i; });
                                               await _restartWithResultAsP1(i);
                                           } else {
                                               if (numStr.isNotEmpty) {
                                                 await _addNewBeacon();
                                               }
                                           }
                                        }
                                      },
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                        suffixIcon: Padding(
                                          padding: const EdgeInsets.all(4.0),
                                          child: Text(beacons[i].unit, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                      )
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onLongPress: () { Clipboard.setData(ClipboardData(text: "$coordDisplay\n$addressDisplay")); _showMsg("Đã copy!"); },
                    child: Column(
                      children: [
                        Text(coordDisplay, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(addressDisplay, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: addressColor, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 10),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: availableUnits.map((unit) => Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: InkWell(
                                  onTap: () async {
                                    _setUnitForSelectedBeacon(unit);
                                    int focusedIdx = beacons.indexWhere((b) => b.focusNode.hasFocus);
                                    if (focusedIdx != -1 && focusedIdx == beacons.length - 1) {
                                      if (beacons[focusedIdx].controller.text.isNotEmpty) {
                                        await _addNewBeacon();
                                      }
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: activeUnitForChip == unit ? Colors.blue : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(unit, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: activeUnitForChip == unit ? Colors.white : Colors.black87)),
                                  ),
                                ),
                              )).toList(),
                            ),
                          ),
                        ),
                        
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              key: const ValueKey("secondApp"),
                              onLongPress: secondTargetAppPackage == null ? _pickSecondTargetApp : _showSecondAppLinkOptions, 
                              onTap: () async {
                                if (secondTargetAppPackage == null) {
                                  _pickSecondTargetApp();
                                } else {
                                  try {
                                    final Uri uri1 = Uri.parse("intent:#Intent;action=android.intent.action.MAIN;package=$secondTargetAppPackage;launchFlags=0x10020000;end");
                                    if (await launchUrl(uri1, mode: LaunchMode.externalApplication)) return;
                                  } catch (e) {}
                                  try {
                                    final Uri uri2 = Uri.parse("intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;package=$secondTargetAppPackage;launchFlags=0x10100000;end");
                                    if (await launchUrl(uri2, mode: LaunchMode.externalApplication)) return;
                                  } catch (e) {}
                                  try {
                                    await InstalledApps.startApp(secondTargetAppPackage!);
                                  } catch (err) {
                                    _showMsg("Lỗi mở App phụ");
                                  }
                                }
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                child: Icon(
                                  Icons.rocket_launch, 
                                  color: secondTargetAppPackage == null ? Colors.grey : Colors.blueAccent, 
                                  size: 26
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            IconButton(
                              icon: const Icon(Icons.content_paste_go, color: Colors.blue, size: 26),
                              onPressed: () async {
                                ClipboardData? cData = await Clipboard.getData(Clipboard.kTextPlain);
                                if (cData != null && cData.text != null && cData.text!.isNotEmpty) {
                                  String query = cData.text!.trim();
                                  final match = RegExp(r'^([-+]?\d+(?:[\.,]\d+)?)\s*[,;\s]+\s*([-+]?\d+(?:[\.,]\d+)?)$').firstMatch(query);
                                  
                                  if (match != null) {
                                    double lat = double.parse(match.group(1)!.replaceAll(',', '.'));
                                    double lng = double.parse(match.group(2)!.replaceAll(',', '.'));
                                    LatLng pos = LatLng(lat, lng);
                                    
                                    _mapController.move(pos, 15);
                                    await _assignSavedTargetToP(pos);
                                    _showMsg("Đã dán và chạy tọa độ!");
                                  } else {
                                    _showMsg("Nội dung copy không phải là tọa độ hợp lệ!");
                                  }
                                } else {
                                  _showMsg("Bộ nhớ tạm đang trống!");
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),

                            InkWell(
                              key: _linkAppKey, 
                              onLongPress: targetAppPackage == null ? _pickTargetApp : _showAppLinkOptions, 
                              onTap: _triggerOverlay,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                child: Icon(
                                  Icons.layers, 
                                  color: targetAppPackage == null 
                                      ? Colors.grey 
                                      : (_autoShowOverlay ? Colors.green : Colors.blueAccent),
                                  size: 26
                                ),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Visibility(
                              visible: targetPoints.isNotEmpty || selectedIndex != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                icon: const Icon(Icons.looks_one, color: Colors.teal, size: 32), 
                                onPressed: () => _restartWithResultAsP1(selectedIndex ?? 0)
                              ),
                            ),
                            const SizedBox(width: 18),

                            Visibility(
                              visible: selectedIndex != null, 
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                icon: const Icon(Icons.refresh, color: Colors.orange, size: 32), 
                                onPressed: _resetCurrentBeacon
                              ),
                            ),
                            const SizedBox(width: 18),

                            Visibility(
                              visible: targetPoints.isNotEmpty || selectedIndex != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                onPressed: isAnyMocking ? _stopMock : () async { 
                                   if (selectedIndex != null && beacons[selectedIndex!].location != null) {
                                     await _setMock(beacons[selectedIndex!].location!.latitude, beacons[selectedIndex!].location!.longitude);
                                   } else if (targetPoints.isNotEmpty) {
                                     await _setMock(targetPoints[0].latitude, targetPoints[0].longitude, fromTarget: true);
                                   }
                                },
                                icon: Icon(isAnyMocking ? Icons.stop_circle : Icons.play_circle, color: isAnyMocking ? Colors.red : Colors.green, size: 32),
                              ),
                            ),
                            const SizedBox(width: 18),
                            
                            Visibility(
                              visible: (beacons.length > 1 || (beacons.isNotEmpty && (beacons[0].location != null || beacons[0].controller.text.isNotEmpty))) || targetPoints.isNotEmpty || searchMarker != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 32), 
                                onPressed: () async {
                                  _autoSaveLastTargetBeforeClearing(); 

                                  setState(() { 
                                    beacons = [Beacon(unit: defaultUnit)]; 
                                    targetPoints.clear(); 
                                    searchMarker = null; 
                                    coordDisplay = "0.000000, 0.000000"; 
                                    addressDisplay = "Chưa có vị trí"; 
                                    addressColor = Colors.grey; 
                                    selectedIndex = null; 
                                  });
                                  await _stopMock();
                                  _zoomToFitAll();
                                  
                                  if (await FlutterOverlayWindow.isActive()) {
                                    await FlutterOverlayWindow.closeOverlay();
                                    setState(() => _isOverlayActive = false);
                                  }
                                }
                              ),
                            ),
                            const SizedBox(width: 18),

                            Visibility(
                              visible: targetPoints.isNotEmpty || selectedIndex != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                icon: const Icon(Icons.map, color: Colors.indigo, size: 32), 
                                onPressed: () {
                                  LatLng? locToOpen;
                                  if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) {
                                    locToOpen = beacons[selectedIndex!].location;
                                  } else if (targetPoints.isNotEmpty) {
                                    locToOpen = targetPoints[0];
                                  }
                                  if (locToOpen != null) {
                                    _viewOnMap(locToOpen); 
                                  } else {
                                    _showMsg("Không có vị trí để mở bản đồ!");
                                  }
                                }
                              ),
                            ),
                            const SizedBox(width: 18),

                            Visibility(
                              visible: targetPoints.isNotEmpty || selectedIndex != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                icon: const Icon(Icons.save, color: Colors.blue, size: 32), 
                                onPressed: _saveCurrentTarget
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (_isLoadingLocation)
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.blue),
                          SizedBox(height: 16),
                          Text("Đang định vị trí của bạn...", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))
                        ],
                      ),
                    )
                  else
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: myRealLocation!,
                        initialZoom: 15,
                        minZoom: 3.0, 
                        maxZoom: 18.0,
                        cameraConstraint: CameraConstraint.contain(
                          bounds: LatLngBounds(
                            const LatLng(-90, -180),
                            const LatLng(90, 180),
                          ),
                        ),
                        onTap: (_, latlng) {
                          FocusManager.instance.primaryFocus?.unfocus(); 
                        },
                        onLongPress: (_, latlng) async {
                          if (_isActionBlocked()) {
                            _showPaymentDialog();
                            return;
                          }

                          int emptyIndex = -1;
                          for (int i = 0; i < beacons.length; i++) {
                            if (beacons[i].location == null) {
                              emptyIndex = i;
                              break;
                            }
                          }

                          int targetIndex = 0;

                          setState(() {
                            if (emptyIndex != -1) {
                              beacons[emptyIndex].location = latlng;
                              targetIndex = emptyIndex;
                              selectedIndex = targetIndex;
                              isMockingTarget = false;
                            } else if (selectedIndex != null && !isMockingTarget) {
                              beacons[selectedIndex!].location = latlng;
                              targetIndex = selectedIndex!;
                            } else {
                              String unitToUse = beacons.isNotEmpty ? beacons.last.unit : 'km';
                              beacons.add(Beacon(location: latlng, color: colorPalette[beacons.length % colorPalette.length], unit: unitToUse));
                              targetIndex = beacons.length - 1;
                              selectedIndex = targetIndex;
                              isMockingTarget = false;
                            }
                            targetPoints.clear();
                          });

                          _requestFocus(targetIndex);
                          await _setMock(latlng.latitude, latlng.longitude);
                          _showMsg("Đã gán và MOCK ${_getBeaconName(targetIndex)}");
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.khoa.findtarget',
                          tileProvider: CachedTileProvider(store: _mapCacheStore),
                        ),
                        CircleLayer(
                          circles: [
                            for (var b in beacons)
                              if (b.location != null && b.controller.text.isNotEmpty)
                                CircleMarker(
                                  point: b.location!,
                                  color: b.color.withOpacity(0.05),
                                  borderColor: b.color,
                                  borderStrokeWidth: 1.5,
                                  useRadiusInMeter: true,
                                  radius: _getRadiusInMeters(b),
                                )
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            if (myRealLocation != null) Marker(point: myRealLocation!, width: 20, height: 20, child: const CircleAvatar(backgroundColor: Colors.blue, radius: 4)),
                            if (searchMarker != null) Marker(point: searchMarker!, width: 60, height: 60, child: GestureDetector(onTap: _showSearchOptions, child: const Icon(Icons.location_on, color: Colors.red, size: 40))),
                            for (int i = 0; i < beacons.length; i++)
                              if (beacons[i].location != null)
                                Marker(point: beacons[i].location!, width: 30, height: 30, child: Container(decoration: BoxDecoration(color: selectedIndex == i ? Colors.red : _getBeaconColor(i, beacons[i].color), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text(_getBeaconShortName(i), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))))),
                            for (int i = 0; i < targetPoints.length; i++)
                              Marker(point: targetPoints[i], width: 60, height: 60, child: const Icon(Icons.location_searching, color: Colors.green, size: 35)),
                            for (int i = 0; i < savedTargets.length; i++)
                              Marker(point: savedTargets[i].location, width: 70, height: 60, child: GestureDetector(onTap: () => _showTargetOptions(i), child: const Icon(Icons.bookmark, color: Colors.blue, size: 20))),
                          ],
                        ),
                      ],
                    ),
                  
                  if (!_isLoadingLocation && isSearchVisible)
                    Positioned(top: 10, left: 15, right: 15, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)), child: TextField(controller: _searchCtrl, autofocus: true, decoration: InputDecoration(hintText: "Tìm kiếm...", border: InputBorder.none, prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { if (_searchCtrl.text.isEmpty) { setState(() => isSearchVisible = false); } else { _searchCtrl.clear(); } })), onSubmitted: (_) => _searchLocation()))),
                  
                  if (!_isLoadingLocation)
                    Positioned(
                      right: 15, 
                      top: 15, 
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                          width: 36, 
                          height: 36, 
                          child: FloatingActionButton(
                            heroTag: "listBtn", 
                            elevation: 2, 
                            backgroundColor: Colors.blue.shade600, 
                            onPressed: _showSavedTargetsSheet, 
                            child: const Icon(Icons.list, color: Colors.white, size: 20),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 36, 
                          height: 36, 
                          child: FloatingActionButton(
                            heroTag: "locBtn", 
                            elevation: 2, 
                            backgroundColor: Colors.white, 
                            onPressed: () async { 
                              Position p = await Geolocator.getCurrentPosition(); 
                              _mapController.move(LatLng(p.latitude, p.longitude), 15); 
                            }, 
                            child: const Icon(Icons.my_location, color: Colors.blue, size: 20),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} //////////////////////ok