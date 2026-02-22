import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
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
  final String _myPackage = "com.khoa.trilaterat"; 
  String? _targetPackage;
  
  bool _isReturning = false; 
  Color _bgColor = Colors.blueAccent;
  IconData _icon = Icons.login; 

  @override
  void initState() {
    super.initState();
    _loadTargetFromDisk();
  }

  Future<void> _loadTargetFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); 
      setState(() {
        _targetPackage = prefs.getString('target_app_package');
      });
    } catch (e) {
      print("Overlay lỗi đọc disk");
    }
  }

  Future<void> _launchApp(String pkg) async {
    try {
      bool? success = await InstalledApps.startApp(pkg);
      if (success == true) return; 
    } catch (e) {
      print("Cách 1 lỗi");
    }

    try {
      final Uri uri = Uri.parse(
          "intent:#Intent;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;launchFlags=0x10000000;package=$pkg;end");
      await launchUrl(uri);
    } catch (e) {
      if (mounted) setState(() => _bgColor = Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 75, 
          height: 75,
          decoration: BoxDecoration(
            color: _bgColor.withOpacity(0.9),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black45)],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            
            onTap: () async {
              setState(() {
                _bgColor = Colors.orange;
              });

              await _loadTargetFromDisk();
              
              if (_targetPackage != null) {
                if (_isReturning) {
                  await _launchApp(_myPackage);
                  if (mounted) setState(() {
                    _isReturning = false;
                    _icon = Icons.login;
                    _bgColor = Colors.blueAccent;
                  });
                } else {
                  await _launchApp(_targetPackage!);
                  if (mounted) setState(() {
                    _isReturning = true;
                    _icon = Icons.undo;
                    _bgColor = Colors.green;
                  });
                }
              } else {
                  if (mounted) setState(() => _bgColor = Colors.grey);
              }
            },

            child: Icon(_icon, color: Colors.white, size: 32),
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

  SavedTarget({required this.location, required this.name, required this.timestamp, String? id}) 
    : id = id ?? DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(100).toString();

  Map<String, dynamic> toJson() => {
    'lat': location.latitude,
    'lng': location.longitude,
    'name': name,
    'time': timestamp.toIso8601String(),
    'id': id,
  };

  factory SavedTarget.fromJson(Map<String, dynamic> json) => SavedTarget(
    location: LatLng(json['lat'], json['lng']),
    name: json['name'],
    timestamp: DateTime.parse(json['time']),
    id: json['id'],
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

  final GlobalKey _addBeaconKey = GlobalKey();
  final GlobalKey _linkAppKey = GlobalKey(); 
  final GlobalKey _helpKey = GlobalKey(); 
  
  late TutorialCoachMark tutorialCoachMark;
  List<TargetFocus> targets = [];
  bool _isTutorialShowing = false;
  bool _isMockDialogShowing = false; 

  bool isPro = false;
  int trialCount = 0;
  final int maxTrial = 50;
  bool allowTrialFromServer = true; 
  String? deviceId;

  List<Beacon> beacons = [];
  List<SavedTarget> savedTargets = [];
  
  String defaultUnit = 'km'; 
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0, 'mi': 1609.34};
  final List<String> availableUnits = ['m', 'km', 'ft', 'mi'];

  int? selectedIndex; 
  List<LatLng> targetPoints = [];
  LatLng? myRealLocation;
  LatLng? searchMarker; 
  
  String coordDisplay = "0.000000, 0.000000";
  String addressDisplay = "Chưa có vị trí";
  Color addressColor = Colors.grey; 

  bool isMockingTarget = false;
  bool isSearchVisible = false;
  String? targetAppPackage; 
  
  bool _isLoadingLocation = true; 

  static const double earthRadius = 6371000.0;
  
  final List<Color> colorPalette = [Colors.orange, Colors.teal, Colors.pink, Colors.brown, Colors.indigo, Colors.lime];

  int? _lastFocusedIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _checkStatus(); 
    _loadData(); 
    _requestOverlayPermission();
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initLocation();
      bool isGranted = await platform.invokeMethod('checkMockPermission');
      if (!isGranted) {
        _showMockPermissionDialog();
      } else {
        _checkAndShowTutorial();
      }
    });
  }

  // CÁC HÀM HELPER XỬ LÝ TÊN VÀ MÀU SẮC ĐIỂM
  String _getBeaconName(int index) {
    if (index < 3) return "Mốc ${index + 1}";
    return "Mục tiêu ${index - 2}";
  }

  String _getBeaconShortName(int index) {
    if (index < 3) return "M${index + 1}";
    return "T${index - 2}";
  }

  Color _getBeaconColor(int index, Color originalColor) {
    if (index < 3) return Colors.blueGrey.shade800; // Màu tối cho 3 mốc đầu
    return originalColor;
  }

  void _showInstructionBoard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book, color: Colors.blue),
            SizedBox(width: 8),
            Text("HƯỚNG DẪN", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Các nút công cụ chính:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
                const SizedBox(height: 10),
                _buildInstructionRow(Icons.layers, Colors.blueAccent, "Nhấn giữ để chọn App mục tiêu đo (HeeSay, Grindr...). Bấm để bật/tắt nút cửa sổ nổi chuyển App nhanh."),
                _buildInstructionRow(Icons.add_circle, Colors.green, "Thêm không giới hạn Mốc/Mục tiêu ra bản đồ để đo khoảng cách tới mục tiêu."),
                _buildInstructionRow(Icons.delete_sweep, Colors.red, "Xóa sạch toàn bộ Mốc/Mục tiêu, điểm tìm kiếm và mục tiêu trên bản đồ để bắt đầu tính toán lại."),
                _buildInstructionRow(Icons.looks_one, Colors.teal, "Lấy tọa độ đang chạy gán vào Mốc 1 mới để tiếp tục dò đường."),
                _buildInstructionRow(Icons.refresh, Colors.orange, "Tính lại vị trí cho điểm hiện tại. Nếu chỉ có 2 điểm tham chiếu sẽ đảo qua lại giữa 2 giao điểm (K1, K2). Nếu có 3 điểm trở lên sẽ tìm vị trí chính xác."),
                _buildInstructionRow(Icons.map, Colors.indigo, "Xem tọa độ trên ứng dụng bản đồ khác (Google Maps..)."),
                _buildInstructionRow(Icons.play_circle, Colors.green, "Bắt đầu/Dừng phát vị trí mô phỏng đến máy."),
                _buildInstructionRow(Icons.save, Colors.blue, "Lưu lại tọa độ của mục tiêu vào danh sách để sử dụng lại sau."),
                _buildInstructionRow(Icons.search, Colors.blue, "Tìm kiếm địa danh hoặc dán trực tiếp tọa độ để di chuyển đến."),
                _buildInstructionRow(Icons.list, Colors.purple, "Mở danh sách các vị trí bạn đã lưu để xem lại hoặc dẫn đường."),
                const SizedBox(height: 10),
                const Text("Nguyên lý đo tọa độ:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.orange)),
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, top: 4.0),
                  child: Text(
                    "- Tạo các Mốc đo và nhập khoảng cách để tính toán ra vị trí Mục tiêu (tọa độ cần tìm).\n"
                    "- Nếu Mục tiêu tính được đo trên app đích vẫn chưa là 0m, hãy tiếp tục nhập khoảng cách đó và thêm Mục tiêu mới để app tính lại.\n"
                    "- Lặp lại cho tới khi thấy khoảng cách báo 0m - đó chính là tọa độ chính xác của mục tiêu cần tìm.\n"
                    "- App tự động cách ly và xóa những điểm bị nhập sai số quá lớn.", 
                    style: TextStyle(fontSize: 13, height: 1.4)
                  ),
                ),
                const SizedBox(height: 15),
                const Divider(),
                const Text("Hỗ trợ trực tuyến:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue)),
                const SizedBox(height: 10),
                Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.forum, size: 22),
                    label: const Text("Tham gia nhóm Zalo hỗ trợ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    onPressed: () async {
                      final Uri url = Uri.parse('https://zalo.me/g/lpzusw024');
                      try {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      } catch (e) {
                         _showMsg("Không thể mở link Zalo");
                      }
                    },
                  ),
                ),
                const SizedBox(height: 15),
              ],
            ),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("TÔI ĐÃ HIỂU", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          )
        ],
      )
    );
  }

  Widget _buildInstructionRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
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
                Text("Nhấn giữ vào biểu tượng này để chọn app dùng để đo khoảng cách (HeeSay, Grindr, ...).", style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "add_beacon_btn",
        keyTarget: _addBeaconKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) => const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("BƯỚC 2: Thêm điểm mô phỏng", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 22)),
                SizedBox(height: 10),
                Text("Bấm vào dấu cộng để bắt đầu thêm các Mốc (Mốc 1, 2, 3) ra bản đồ để đo khoảng cách. Khi đã đủ 3 mốc, các điểm tiếp theo sẽ là Mục tiêu (Mục tiêu 1, 2...).", style: TextStyle(color: Colors.white, fontSize: 16)),
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
                Text("Bấm vào đây để đọc bảng hướng dẫn chi tiết và vào nhóm hỗ trợ nhé!", style: TextStyle(color: Colors.white, fontSize: 16)),
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

  void _showMockPermissionDialog() {
    if (_isMockDialogShowing) return;
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
                const Text(
                  "Cách bật Tùy chọn nhà phát triển (nếu chưa có):",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  "Vào Cài đặt máy -> Giới thiệu điện thoại -> Nhấn liên tục 7 lần vào 'Số hiệu bản tạo' (hoặc 'Phiên bản MIUI/OS').",
                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // NÚT CHÍNH ĐƯỢC ĐƯA LÊN TRÊN ĐÂY
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
                    child: const Text("Tới Cài Đặt Ngay", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(), // KẺ NGANG
                const SizedBox(height: 8),
                
                // PHẦN PHỤ HỖ TRỢ ZALO Ở DƯỚI
                const Text(
                  "Cần hỗ trợ trực tiếp?",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  icon: const Icon(Icons.forum, size: 20),
                  label: const Text("Tham gia nhóm Zalo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () async {
                    final Uri url = Uri.parse('https://zalo.me/g/lpzusw024');
                    try {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    } catch (e) {
                       _showMsg("Không thể mở link Zalo");
                    }
                  },
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
    String amount = "50000"; 
    String description = "PRO $deviceId"; 
    
    String encodedDesc = Uri.encodeComponent(description);
    String qrUrl = "https://img.vietqr.io/image/$bankId-$accountNo-compact.png?amount=$amount&addInfo=$encodedDesc";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Mở khóa bản PRO vĩnh viễn", textAlign: TextAlign.center),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView( 
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Bạn đã hết 50 lượt dùng thử.\nQuét mã QR dưới đây để thanh toán nâng cấp PRO:", textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
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
                const Text("Giá: 50.000 VNĐ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
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
    _mapController.dispose();
    _searchCtrl.dispose();
    for (var b in beacons) b.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      int currentFocus = beacons.indexWhere((b) => b.focusNode.hasFocus);
      if (currentFocus != -1) {
        _lastFocusedIndex = currentFocus;
        FocusManager.instance.primaryFocus?.unfocus();
      }
    } else if (state == AppLifecycleState.resumed) {
      _checkMockOnResume();

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

  Future<void> _pickTargetApp() async {
    _showMsg("Đang quét danh sách ứng dụng...");
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps();
      apps.sort((a, b) => (a.name ?? "").toLowerCase().compareTo((b.name ?? "").toLowerCase()));
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
                    Navigator.pop(ctx);
                    _showMsg("Đã liên kết: ${app.name}");
                    _showInvincibleOverlay(); 
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

    bool isActive = await FlutterOverlayWindow.isActive();
    if (isActive) {
      await FlutterOverlayWindow.closeOverlay();
      _showMsg("Đã tắt nút nổi");
    } else {
      await _showInvincibleOverlay();
      _showMsg("Đã bật nút nổi");
    }
  }

  Future<void> _showInvincibleOverlay() async {
    if (await FlutterOverlayWindow.isActive()) return;
    await FlutterOverlayWindow.showOverlay(
      enableDrag: true,
      flag: OverlayFlag.defaultFlag, 
      visibility: NotificationVisibility.visibilitySecret,
      alignment: OverlayAlignment.centerLeft, 
      positionGravity: PositionGravity.none,
      height: 130, 
      width: 130, 
      startPosition: const OverlayPosition(0, -100),
    );
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
      _showInvincibleOverlay(); 
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

  double _haversineDistance(LatLng p1, LatLng p2) {
    double dLat = _toRadians(p2.latitude - p1.latitude);
    double dLon = _toRadians(p2.longitude - p1.longitude);
    double lat1 = _toRadians(p1.latitude);
    double lat2 = _toRadians(p2.latitude);
    double a = pow(sin(dLat / 2), 2) + pow(sin(dLon / 2), 2) * cos(lat1) * cos(lat2);
    double c = 2 * asin(sqrt(a));
    return earthRadius * c;
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
    double bearingRad = _toRadians(bearingDegrees); 
    double startLat = _toRadians(start.latitude);
    double startLng = _toRadians(start.longitude);
    double distRatio = distanceMeters / earthRadius;
    
    double endLat = asin(sin(startLat) * cos(distRatio) + cos(startLat) * sin(distRatio) * cos(bearingRad));
    double endLng = startLng + atan2(sin(bearingRad) * sin(distRatio) * cos(startLat), cos(distRatio) - sin(startLat) * sin(endLat));
    return LatLng(_toDegrees(endLat), _toDegrees(endLng));
  }

  List<LatLng> _calculateTwoCircleIntersectionPrecise(LatLng p1, double r1, LatLng p2, double r2) {
    double d = _haversineDistance(p1, p2);

    double tolerance = 2.0;
    
    if (d > r1 + r2 + tolerance || d < (r1 - r2).abs() - tolerance || d == 0) {
      return []; 
    }

    if (d > r1 + r2) d = r1 + r2;
    if (d < (r1 - r2).abs()) d = (r1 - r2).abs();

    double cosAlpha = (r1 * r1 + d * d - r2 * r2) / (2 * r1 * d);
    cosAlpha = max(-1.0, min(1.0, cosAlpha));
    double alphaRad = acos(cosAlpha);
    double alphaDeg = _toDegrees(alphaRad);

    double bearing12 = _calculateBearing(p1, p2);
    double bearingK1 = bearing12 - alphaDeg;
    double bearingK2 = bearing12 + alphaDeg;

    LatLng k1 = _calculatePointFromBearing(p1, r1, bearingK1);
    LatLng k2 = _calculatePointFromBearing(p1, r1, bearingK2);

    return [k1, k2];
  }

  LatLng _optimizePoint(LatLng startPoint, List<Beacon> beacons) {
    LatLng currentPos = startPoint;
    double stepSize = 0.0001; 
    double minStep = 0.000000001; 
    int maxIterations = 5000; 
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
      double d = _haversineDistance(p, b.location!);
      double r = _getRadiusInMeters(b);
      if (r <= 0) continue; 
      
      double weight = 1.0 / (r * r + 1.0); 
      double err = (d - r).abs();
      double loss = err < 50.0 ? 0.5 * err * err : 50.0 * (err - 25.0);
      totalError += loss * weight; 
    }
    return totalError;
  }

  // Hàm tính điểm Best Fit (chính xác) dành cho 3 điểm trở lên
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

  // HÀM MỚI: Tự động phát hiện và xóa điểm bị sai số
  LatLng? _internalCalculateBestFit() {
      var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
      if (validBeacons.length < 2) return null;
      if (validBeacons.length == 2) return _calculateBestFit(validBeacons);

      List<Beacon> filtered = List.from(validBeacons);
      LatLng? bestPos;
      List<Beacon> toRemove = [];

      int maxIterations = validBeacons.length - 2; 
      for (int i = 0; i < maxIterations; i++) {
          bestPos = _calculateBestFit(filtered);
          if (bestPos == null) break;

          double maxErr = 0;
          Beacon? worstB;
          
          for (var b in filtered) {
              double r = _getRadiusInMeters(b);
              if (r <= 0) continue;
              double d = _haversineDistance(bestPos, b.location!);
              double err = (d - r).abs();
              
              if (err > maxErr && err > 50.0 && err > r * 0.1) {
                  maxErr = err;
                  worstB = b;
              }
          }

          if (worstB != null) {
              filtered.remove(worstB);
              toRemove.add(worstB);
          } else {
              break; 
          }
      }

      if (toRemove.isNotEmpty) {
          for (var b in toRemove) {
              int idx = beacons.indexOf(b);
              if (idx != -1) {
                  if (selectedIndex == idx) selectedIndex = null;
                  else if (selectedIndex != null && selectedIndex! > idx) selectedIndex = selectedIndex! - 1;
                  
                  b.dispose();
                  beacons.removeAt(idx);
                  
                  Future.delayed(Duration.zero, () {
                      _showMsg("Đã xóa ${_getBeaconName(idx)} do phát hiện khoảng cách bị nhập sai!");
                  });
              }
          }
      }

      return bestPos ?? _calculateBestFit(filtered.isNotEmpty ? filtered : validBeacons);
  }

  void _requestFocus(int index) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (index >= 0 && index < beacons.length) {
        beacons[index].focusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show'); 
      }
    });
  }

  void _assignSavedTargetToP(LatLng location) {
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
    _setMock(location.latitude, location.longitude);
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
      _setMock(finalPos.latitude, finalPos.longitude);
    } catch (e) { _showMsg("Lỗi"); }
  }

  // --- HÀM REFRESH PHÂN TÁCH LOGIC CHO TRƯỜNG HỢP < 3 ĐIỂM VÀ >= 3 ĐIỂM ---
  Future<void> _resetCurrentBeacon() async {
    if (selectedIndex == null) {
      _showMsg("Chưa chọn điểm nào để tính lại!");
      return;
    }
    int index = selectedIndex!;

    List<Beacon> otherBeacons = [];
    for (int i = 0; i < beacons.length; i++) {
      if (i != index && beacons[i].location != null && beacons[i].controller.text.isNotEmpty) {
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
        if (intersections.length == 2 && beacons[index].location != null) {
          LatLng currentPos = beacons[index].location!;
          double d1 = _haversineDistance(currentPos, intersections[0]);
          double d2 = _haversineDistance(currentPos, intersections[1]);
          newPos = (d1 > d2) ? intersections[0] : intersections[1];
        } else {
          newPos = intersections[0];
        }
      }
    } else if (otherBeacons.length == 1) {
      var ref = otherBeacons[0];
      double r = _getRadiusInMeters(ref);
      if (beacons[index].location != null) {
        double bearing = _calculateBearing(ref.location!, beacons[index].location!);
        newPos = _calculatePointFromBearing(ref.location!, r, bearing);
      } else {
        newPos = _calculatePointFromBearing(ref.location!, r, 0);
      }
    }

    if (newPos != null) {
      setState(() {
        beacons[index].location = newPos;
        targetPoints.clear();
      });
      _requestFocus(index); 
      _mapController.move(newPos, _mapController.camera.zoom);
      _setMock(newPos.latitude, newPos.longitude);
      _zoomToFitAll();
      _showMsg(otherBeacons.length >= 3 ? "Đã tính lại vị trí chính xác!" : "Đã đảo vị trí K1/K2 thành công!");
    } else {
      _showMsg("Không đủ dữ liệu để tính lại! Cần ít nhất 1-2 điểm khác.");
    }
  }

  void _restartWithResultAsP1() {
    LatLng? newStart;
    if (isMockingTarget && targetPoints.isNotEmpty) { newStart = targetPoints[0]; } 
    else if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) { newStart = beacons[selectedIndex!].location; }
    else if (targetPoints.isNotEmpty) { newStart = targetPoints[0]; }

    if (newStart == null) { _showMsg("Chưa có tọa độ nào để gán!"); return; }
    
    String unitP1 = 'km';

    setState(() {
      defaultUnit = 'km'; 
      beacons = [Beacon(location: newStart, color: Colors.blue, unit: unitP1)];
      targetPoints.clear();
      coordDisplay = "0.000000, 0.000000";
      addressDisplay = "Chưa có vị trí";
      searchMarker = null;
      selectedIndex = 0; 
      isMockingTarget = false;
    });
    _requestFocus(0); 
    _mapController.move(newStart, 16);
    _setMock(newStart.latitude, newStart.longitude);
    _showMsg("Đã gán và chạy Mốc 1 mới!");
  }

  Future<void> _searchLocation() async {
    String query = _searchCtrl.text.trim();
    if (query.isEmpty) return;
    final coordRegExp = RegExp(r'^([-+]?\d*\.?\d+),\s*([-+]?\d*\.?\d+)$');
    final match = coordRegExp.firstMatch(query);
    if (match != null) {
      double lat = double.parse(match.group(1)!);
      double lng = double.parse(match.group(2)!);
      LatLng pos = LatLng(lat, lng);
      _mapController.move(pos, 15);
      setState(() { searchMarker = pos; isSearchVisible = false; });
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
          setState(() { searchMarker = pos; isSearchVisible = false; });
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
            setState(() => savedTargets.add(SavedTarget(location: pointToSave!, name: nameCtrl.text, timestamp: DateTime.now())));
            _saveData(); Navigator.pop(ctx); _showMsg("Đã lưu!");
          }, child: const Text("LƯU")),
        ],
      ),
    );
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedData = jsonEncode(savedTargets.map((e) => e.toJson()).toList());
    await prefs.setString('saved_targets', encodedData);
  }
   
  Future<void> _saveTargetApp(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('target_app_package', packageName);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    String? encodedData = prefs.getString('saved_targets');
    if (encodedData != null) {
      Iterable l = jsonDecode(encodedData);
      setState(() { savedTargets = List<SavedTarget>.from(l.map((model) => SavedTarget.fromJson(model))); });
    }
    String? pkg = prefs.getString('target_app_package');
    if (pkg != null) setState(() => targetAppPackage = pkg);
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    while (true) {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text("Yêu cầu bật GPS"),
            content: const Text("Ứng dụng cần bạn bật Dịch vụ vị trí (GPS) để có thể hiển thị bản đồ ở vị trí hiện tại."),
            actions: [
              TextButton(
                onPressed: () => Geolocator.openLocationSettings(),
                child: const Text("Mở Cài đặt"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Đã bật, tiếp tục"),
              )
            ],
          )
        );
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
            builder: (ctx) => AlertDialog(
              title: const Text("Yêu cầu quyền Vị trí"),
              content: const Text("Bạn cần cấp quyền truy cập vị trí để ứng dụng định vị bản đồ."),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Đồng ý"),
                )
              ],
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
          builder: (ctx) => AlertDialog(
            title: const Text("Quyền Vị trí bị từ chối"),
            content: const Text("Bạn đã từ chối quyền vị trí. Vui lòng vào Cài đặt ứng dụng -> Quyền -> Bật Vị trí để tiếp tục."),
            actions: [
              TextButton(
                onPressed: () => Geolocator.openAppSettings(),
                child: const Text("Mở Cài đặt App"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Đã cấp quyền"),
              )
            ],
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

  void _editTargetName(int index) {
    TextEditingController editCtrl = TextEditingController(text: savedTargets[index].name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Đổi tên"),
        content: TextField(controller: editCtrl, decoration: const InputDecoration(labelText: "Tên mới")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
          ElevatedButton(onPressed: () { setState(() => savedTargets[index].name = editCtrl.text); _saveData(); Navigator.pop(ctx); }, child: const Text("OK")),
        ],
      ),
    );
  }

  void _confirmDeleteTarget(int index, {VoidCallback? onDeleted}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: Text("Xóa '${savedTargets[index].name}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("KHÔNG")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { 
            setState(() => savedTargets.removeAt(index)); _saveData(); Navigator.pop(ctx); 
            if (onDeleted != null) onDeleted();
          }, child: const Text("XÓA", style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  // HÀM MỚI: Hiển thị thông báo ở trên cùng màn hình
  void _showMsg(String m) {
    ScaffoldMessenger.of(context).clearSnackBars(); 
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          m, 
          textAlign: TextAlign.center, 
          style: const TextStyle(color: Colors.white, fontSize: 13) // Đã bỏ in đậm
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black.withOpacity(0.7), // Bớt đen đặc
        elevation: 2, // Giảm độ nổi bóng
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.8, 
          left: 20,
          right: 20,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 35), onPressed: () { Navigator.pop(ctx); _assignSavedTargetToP(searchMarker!); }),
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

  void _showTargetOptions(int index) {
    String coords = "${savedTargets[index].location.latitude.toStringAsFixed(6)}, ${savedTargets[index].location.longitude.toStringAsFixed(6)}";
    String address = "Đang lấy địa chỉ...";
    bool fetched = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          if (!fetched) {
            fetched = true;
            final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${savedTargets[index].location.latitude}&lon=${savedTargets[index].location.longitude}&zoom=18&addressdetails=1');
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
            title: Text(savedTargets[index].name, textAlign: TextAlign.center),
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
              IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 32), onPressed: () { Navigator.pop(ctx); _assignSavedTargetToP(savedTargets[index].location); }),
              IconButton(icon: const Icon(Icons.directions, color: Colors.orange, size: 32), onPressed: () { Navigator.pop(ctx); _openNavigation(savedTargets[index].location); }),
              IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 32), onPressed: () { Navigator.pop(ctx); _editTargetName(index); }),
              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 32), onPressed: () { Navigator.pop(ctx); _confirmDeleteTarget(index); }),
            ],
          );
        }
      ),
    );
  }

  void _showSavedTargetsSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.6,
            child: ListView.builder(
              itemCount: savedTargets.length,
              itemBuilder: (c, i) => ListTile(
                leading: const Icon(Icons.location_on, color: Colors.purple),
                title: Text(savedTargets[i].name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add_location_alt, color: Colors.green),
                      onPressed: () { 
                        _assignSavedTargetToP(savedTargets[i].location); 
                        Navigator.pop(ctx); 
                      }
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () { 
                        _confirmDeleteTarget(i, onDeleted: () {
                          setModalState(() {});
                        }); 
                      }
                    ),
                  ],
                ),
                onTap: () { 
                  _mapController.move(savedTargets[i].location, 15); 
                  Navigator.pop(ctx); 
                },
              ),
            ),
          );
        }
      ),
    );
  }

  void _setUnitForSelectedBeacon(String unit) {
    setState(() {
      int focusedIndex = beacons.indexWhere((b) => b.focusNode.hasFocus);
      
      if (focusedIndex != -1) {
          beacons[focusedIndex].unit = unit;
      } 
      else if (selectedIndex != null && selectedIndex! < beacons.length) { 
        beacons[selectedIndex!].unit = unit; 
      } 
      else {
        defaultUnit = unit; 
      }
    });
  }

  void _addNewBeacon() {
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
    }

    setState(() {
      String defaultNewUnit = beacons.isNotEmpty ? beacons.last.unit : defaultUnit;

      if (beacons.length >= 3) {
        LatLng? bestK = _internalCalculateBestFit();

        int countM = beacons.where((b) => b.unit == 'm').length;
        int countKm = beacons.where((b) => b.unit == 'km').length;
        int countMi = beacons.where((b) => b.unit == 'mi').length;
        int countFt = beacons.where((b) => b.unit == 'ft').length;

        bool isRefereeMode = (countM == 2 && countKm == 1) || (countMi == 2 && countFt == 1);
        LatLng? finalPoint;

        if (isRefereeMode) {
            String pairUnit = (countM == 2) ? 'm' : 'mi';
            var pair = beacons.where((b) => b.unit == pairUnit).toList();
            var referee = beacons.firstWhere((b) => b.unit != pairUnit);
            
            if (pair.length == 2 && pair[0].location != null && pair[1].location != null && referee.location != null) {
                 var roots = _calculateTwoCircleIntersectionPrecise(
                    pair[0].location!, _getRadiusInMeters(pair[0]), 
                    pair[1].location!, _getRadiusInMeters(pair[1])
                 );
                 
                 if (roots.length == 2) {
                     double rRef = _getRadiusInMeters(referee);
                     
                     double distRefToK1 = _haversineDistance(referee.location!, roots[0]);
                     double errorRadius1 = (distRefToK1 - rRef).abs();
                     double errorFit1 = bestK != null ? _haversineDistance(bestK, roots[0]) : 0;
                     double totalScore1 = errorRadius1 + errorFit1;

                     double distRefToK2 = _haversineDistance(referee.location!, roots[1]);
                     double errorRadius2 = (distRefToK2 - rRef).abs();
                     double errorFit2 = bestK != null ? _haversineDistance(bestK, roots[1]) : 0;
                     double totalScore2 = errorRadius2 + errorFit2;

                     finalPoint = (totalScore1 < totalScore2) ? roots[0] : roots[1];
                 }
            }
        }

        if (finalPoint == null && bestK != null) {
           finalPoint = bestK;
        }

        if (finalPoint != null) {
            beacons.add(Beacon(location: finalPoint, color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
            
            selectedIndex = beacons.length - 1;
            targetPoints.clear();
            isMockingTarget = false;
            
            _setMock(finalPoint.latitude, finalPoint.longitude);
            _zoomToFitAll();
            _requestFocus(beacons.length - 1); 
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
        beacons.add(Beacon(location: finalPos, color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
        selectedIndex = beacons.length - 1;
        targetPoints.clear();
        isMockingTarget = false;
        _setMock(finalPos.latitude, finalPos.longitude);
        _zoomToFitAll();
      } else {
        beacons.add(Beacon(color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
      }
      _requestFocus(beacons.length - 1); 
    });
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
                          height: 70,
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
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true), 
                                      textAlign: TextAlign.center, 
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      onTap: () {
                                        setState(() {});
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
                      // NÚT HƯỚNG DẪN Ở GÓC TRÊN CÙNG BÊN PHẢI
                      Container(
                        margin: const EdgeInsets.only(left: 4, top: 2),
                        child: ElevatedButton.icon(
                          key: _helpKey,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 36),
                            elevation: 0,
                            side: BorderSide(color: Colors.blue.shade200),
                          ),
                          icon: const Icon(Icons.menu_book, size: 14),
                          label: const Text("Hướng dẫn", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: _showInstructionBoard,
                        ),
                      )
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
                                child: ChoiceChip(
                                  showCheckmark: false, 
                                  label: Text(unit, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: activeUnitForChip == unit ? Colors.white : Colors.black87)), 
                                  selected: activeUnitForChip == unit, 
                                  selectedColor: Colors.blue, 
                                  backgroundColor: Colors.grey.shade200,
                                  visualDensity: VisualDensity.compact,
                                  onSelected: (val) {
                                    if (val) _setUnitForSelectedBeacon(unit);
                                  },
                                ),
                              )).toList(),
                            ),
                          ),
                        ),
                        
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              key: _linkAppKey, 
                              onLongPress: _pickTargetApp, 
                              onTap: _triggerOverlay,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                child: Icon(
                                  Icons.layers, 
                                  color: targetAppPackage != null ? Colors.blueAccent : Colors.grey, 
                                  size: 26
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(isSearchVisible ? Icons.search_off : Icons.search, color: Colors.blue, size: 26),
                              onPressed: () => setState(() => isSearchVisible = !isSearchVisible),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  // THANH CÔNG CỤ CỐ ĐỊNH, DÙNG VISIBILITY ĐỂ ẨN NHƯNG GIỮ CHỖ
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
                            // Nút 1: Add (Luôn hiện và đứng im)
                            IconButton(
                              key: _addBeaconKey,
                              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                              icon: const Icon(Icons.add_circle, color: Colors.green, size: 36), 
                              onPressed: _addNewBeacon 
                            ),
                            const SizedBox(width: 18),
                            
                            // Nút 2: Delete
                            Visibility(
                              visible: beacons.isNotEmpty || targetPoints.isNotEmpty || searchMarker != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 32), 
                                onPressed: () {
                                  setState(() { 
                                    beacons = []; 
                                    targetPoints.clear(); 
                                    searchMarker = null; 
                                    coordDisplay = "0.000000, 0.000000"; 
                                    addressDisplay = "Chưa có vị trí"; 
                                    addressColor = Colors.grey; 
                                    selectedIndex = null; 
                                  });
                                  _stopMock();
                                  _zoomToFitAll();
                                }
                              ),
                            ),
                            const SizedBox(width: 18),
                            
                            // Nút 3: Restart as Mốc 1
                            Visibility(
                              visible: targetPoints.isNotEmpty || selectedIndex != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                icon: const Icon(Icons.looks_one, color: Colors.teal, size: 32), 
                                onPressed: _restartWithResultAsP1
                              ),
                            ),
                            const SizedBox(width: 18),

                            // Nút 5: Refresh
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

                            // Nút 6: Map
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

                            // Nút 7: Play/Stop
                            Visibility(
                              visible: targetPoints.isNotEmpty || selectedIndex != null,
                              maintainSize: true, maintainAnimation: true, maintainState: true,
                              child: IconButton(
                                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                onPressed: isAnyMocking ? _stopMock : () { 
                                   if (selectedIndex != null && beacons[selectedIndex!].location != null) {
                                     _setMock(beacons[selectedIndex!].location!.latitude, beacons[selectedIndex!].location!.longitude);
                                   } else if (targetPoints.isNotEmpty) {
                                     _setMock(targetPoints[0].latitude, targetPoints[0].longitude, fromTarget: true);
                                   }
                                },
                                icon: Icon(isAnyMocking ? Icons.stop_circle : Icons.play_circle, color: isAnyMocking ? Colors.red : Colors.green, size: 32),
                              ),
                            ),
                            const SizedBox(width: 18),

                            // Nút 8: Save
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
                        onLongPress: (_, latlng) {
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
                          _setMock(latlng.latitude, latlng.longitude);
                          _showMsg("Đã gán và MOCK ${_getBeaconName(targetIndex)}");
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.khoa.fakegpstracetarget',
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
                              Marker(point: savedTargets[i].location, width: 70, height: 60, child: GestureDetector(onTap: () => _showTargetOptions(i), child: const Icon(Icons.bookmark, color: Colors.purple, size: 20))),
                          ],
                        ),
                      ],
                    ),
                  
                  if (!_isLoadingLocation && isSearchVisible)
                    Positioned(top: 10, left: 15, right: 15, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)), child: TextField(controller: _searchCtrl, autofocus: true, decoration: InputDecoration(hintText: "Tìm kiếm...", border: InputBorder.none, prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => isSearchVisible = false))), onSubmitted: (_) => _searchLocation()))),
                  
                  if (!_isLoadingLocation)
                    Positioned(right: 15, bottom: 15, child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (savedTargets.isNotEmpty) FloatingActionButton(heroTag: "listBtn", mini: true, backgroundColor: Colors.purple, onPressed: _showSavedTargetsSheet, child: const Icon(Icons.list, color: Colors.white)),
                      const SizedBox(height: 10),
                      FloatingActionButton(heroTag: "locBtn", mini: true, backgroundColor: Colors.white, onPressed: () async { Position p = await Geolocator.getCurrentPosition(); _mapController.move(LatLng(p.latitude, p.longitude), 15); }, child: const Icon(Icons.my_location, color: Colors.blue)),
                    ])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} // ok