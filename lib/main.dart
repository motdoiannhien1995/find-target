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

// --- THƯ VIỆN CACHE ---
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart'; 
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';

// --- THƯ VIỆN MỞ RỘNG ---
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';

// ==========================================
// PHẦN 1: ENTRY POINT CHO OVERLAY (CỬA SỔ NỔI)
// ==========================================
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
  final String _myPackage = "com.khoa.fakegpstracetarget"; 
  String? _targetPackage;
  
  bool _isReturning = false; 
  Color _bgColor = Colors.blueAccent;
  IconData _icon = Icons.login; 
  bool _isLoading = false;

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
      print("Overlay lỗi đọc disk: $e");
    }
  }

  Future<void> _launchApp(String pkg) async {
    try {
      bool? success = await InstalledApps.startApp(pkg);
      if (success == true) return; 
    } catch (e) {
      print("Cách 1 lỗi: $e");
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
            
            // --- TAP: CHUYỂN ĐỔI APP ---
            onTap: () {
              if (_isLoading) return;
              
              setState(() {
                _isLoading = true;
                _bgColor = Colors.orange;
              });

              Future.delayed(const Duration(milliseconds: 50), () async {
                if (_targetPackage == null) await _loadTargetFromDisk();
                
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

                if (mounted) setState(() => _isLoading = false);
              });
            },

            // --- LONG PRESS: ĐÓNG VÀ RESET TRẠNG THÁI ---
            onLongPress: () async {
              if (mounted) {
                setState(() {
                  _bgColor = Colors.red;
                  _icon = Icons.close;
                });
              }
              
              await Future.delayed(const Duration(milliseconds: 300));
              await FlutterOverlayWindow.closeOverlay();

              if (mounted) {
                setState(() {
                  _bgColor = Colors.blueAccent;
                  _icon = Icons.login;
                });
              }
            },

            child: _isLoading 
              ? const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                )
              : Icon(_icon, color: Colors.white, size: 32),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// PHẦN 2: APP CHÍNH (MAIN)
// ==========================================

late final CacheStore _mapCacheStore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final dir = await getTemporaryDirectory();
    _mapCacheStore = FileCacheStore('${dir.path}/map_tiles');
  } catch (e) {
    _mapCacheStore = MemCacheStore(); 
  }
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MockApp()));
}

// --- MODELS ---
class Beacon {
  LatLng? location;
  final TextEditingController controller;
  final FocusNode focusNode;
  Color color;
  int resetStep = 0; 
  String unit; 
   
  Beacon({this.location, String dist = "", Color? color, this.unit = 'ft'}) 
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

// --- MAIN WIDGET ---
class MockApp extends StatefulWidget {
  const MockApp({super.key});
  @override
  State<MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<MockApp> {
  static const platform = MethodChannel('com.example.mock/gps');
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _mockTimer;

  // Khởi tạo Beacon đầu tiên
  List<Beacon> beacons = [Beacon(color: Colors.blue, unit: 'ft')];
  List<SavedTarget> savedTargets = [];
  
  String defaultUnit = 'ft'; 
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0, 'mi': 1609.34};
  final List<String> availableUnits = ['ft', 'mi', 'm', 'km'];

  int? selectedIndex; 
  List<LatLng> targetPoints = [];
  LatLng? myRealLocation;
  LatLng? searchMarker; 
  String resultDisplay = "0.000000, 0.000000";
  String accuracyInfo = "Chờ nhập liệu...";
  Color accuracyColor = Colors.grey; 
  bool isMockingTarget = false;
  int mockingTargetIndex = 0;
  bool isSearchVisible = false;
  String? targetAppPackage; 

  static const double earthRadius = 6371000.0;
  
  final List<Color> colorPalette = [Colors.orange, Colors.teal, Colors.pink, Colors.brown, Colors.indigo, Colors.lime];

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadData(); 
    _requestOverlayPermission();
  }

  Future<void> _requestOverlayPermission() async {
    bool status = await FlutterOverlayWindow.isPermissionGranted();
    if (!status) await FlutterOverlayWindow.requestPermission();
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _mapController.dispose();
    _searchCtrl.dispose();
    for (var b in beacons) b.dispose();
    super.dispose();
  }

  // --- HÀM HELPER: TÍNH BÁN KÍNH CÓ BÙ SAI SỐ ---
  double _getRadiusInMeters(Beacon b) {
    double inputVal = double.tryParse(b.controller.text) ?? 0;
    if (inputVal == 0) return 0;

    // Nếu là km hoặc mi, cộng thêm 0.5
    if (b.unit == 'km' || b.unit == 'mi') {
      inputVal += 0.5;
    }

    return inputVal * unitToMeter[b.unit]!;
  }

  // --- LOGIC CHỌN APP ---
  Future<void> _pickTargetApp() async {
    _showMsg("Đang quét danh sách ứng dụng...");
    try {
      List<AppInfo> apps = await InstalledApps.getInstalledApps();
      apps.sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
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
                  leading: app.icon != null ? Image.memory(app.icon!, width: 40) : const Icon(Icons.android),
                  title: Text(app.name ?? "Unknown"),
                  subtitle: Text(app.packageName ?? "", style: const TextStyle(fontSize: 10)),
                  onTap: () {
                    setState(() => targetAppPackage = app.packageName);
                    _saveTargetApp(app.packageName!);
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
    } catch (e) { _showMsg("Lỗi lấy danh sách app: $e"); }
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

  // --- LOGIC MOCK GPS ---
  Future<void> _setMock(double lat, double lng, {bool fromTarget = false, int targetIndex = 0}) async {
    _mockTimer?.cancel();
    void pushMock() {
      try { platform.invokeMethod('setMockLocation', {"lat": lat, "lng": lng}); } catch (e) { print("Lỗi Mock: $e"); }
    }
    pushMock();
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (timer) { pushMock(); });
    _showInvincibleOverlay(); 
    if (mounted) {
      setState(() {
        isMockingTarget = fromTarget;
        if (fromTarget) {
          selectedIndex = null;
          mockingTargetIndex = targetIndex;
          if (targetPoints.isNotEmpty && targetIndex < targetPoints.length) {
             _mapController.move(targetPoints[targetIndex], 17);
          }
        }
      });
    }
  }

  Future<void> _stopMock() async {
    _mockTimer?.cancel();
    _mockTimer = null;
    try { 
      await platform.invokeMethod('stopMockLocation'); 
      if (mounted) { setState(() { isMockingTarget = false; selectedIndex = null; }); }
      _showMsg("Đã dừng Mock");
    } catch (e) { print(e); }
  }

  // ======================================================
  // PHẦN THUẬT TOÁN TÍNH TOÁN
  // ======================================================

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

    if (d >= r1 + r2 || d <= (r1 - r2).abs() || d == 0) {
      return []; 
    }

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
    double stepSize = 0.001; 
    double minStep = 0.0000001; 
    int maxIterations = 3000; 
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
      double d = _haversineDistance(p, b.location!);
      double r = _getRadiusInMeters(b);
      totalError += pow(d - r, 2); 
    }
    return totalError;
  }

  // --- HÀM TÍNH TOÁN K (ĐÃ SỬA LỖI) ---
  LatLng? _internalCalculateBestFit() {
     var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
     if (validBeacons.length < 2) return null;

     LatLng p1 = validBeacons[0].location!;
     LatLng p2 = validBeacons[1].location!;
     double r1 = _getRadiusInMeters(validBeacons[0]);
     double r2 = _getRadiusInMeters(validBeacons[1]);

     // Tính cả 2 giao điểm
     var roots = _calculateTwoCircleIntersectionPrecise(p1, r1, p2, r2);
     LatLng bestStartNode;
     
     if (roots.isEmpty) {
       // Nếu không cắt nhau, lấy trung bình cộng làm điểm bắt đầu
       double sLat = 0, sLng = 0;
       for (var b in validBeacons) { sLat += b.location!.latitude; sLng += b.location!.longitude; }
       bestStartNode = LatLng(sLat/validBeacons.length, sLng/validBeacons.length);
     } else {
       // NẾU CÓ 2 GIAO ĐIỂM, CHỌN ĐIỂM NÀO SAI SỐ THẤP HƠN VỚI TẤT CẢ CÁC P CÒN LẠI
       if (roots.length == 2 && validBeacons.length >= 3) {
          double err1 = _calculateTotalError(roots[0], validBeacons);
          double err2 = _calculateTotalError(roots[1], validBeacons);
          bestStartNode = (err1 < err2) ? roots[0] : roots[1];
       } else {
          bestStartNode = roots[0];
       }
     }

     // Chạy tối ưu hóa từ điểm xuất phát tốt nhất đã chọn
     return _optimizePoint(bestStartNode, validBeacons);
  }

  void _calculateTrilateration() {
    FocusScope.of(context).unfocus();
    var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
    
    if (validBeacons.length < 2) { 
      _showMsg("Cần ít nhất 2 điểm P để tính toán!");
      setState(() { accuracyInfo = "Thiếu dữ liệu"; accuracyColor = Colors.red; });
      return; 
    }

    try {
      List<LatLng> results = [];
      String displayMsg = "";
      String infoMsg = "";
      Color infoColor = Colors.black;

      LatLng? optimalK = _internalCalculateBestFit();

      if (optimalK != null) {
        if (validBeacons.length == 2) {
           LatLng p1 = validBeacons[0].location!;
           LatLng p2 = validBeacons[1].location!;
           double r1 = _getRadiusInMeters(validBeacons[0]);
           double r2 = _getRadiusInMeters(validBeacons[1]);
           var roots = _calculateTwoCircleIntersectionPrecise(p1, r1, p2, r2);
           if (roots.isEmpty) {
              displayMsg = "KHÔNG CẮT NHAU";
              infoMsg = "Sai khoảng cách (đã bù sai số)";
              infoColor = Colors.red;
              results = [];
           } else {
              displayMsg = "TÌM THẤY K";
              infoMsg = "Đã cộng thêm 0.5 cho mi/km";
              infoColor = Colors.green;
              results = roots;
           }
        } else {
           results = [optimalK];
           displayMsg = "ĐA GIÁC LƯỢNG (3P+)";
           infoMsg = "Đã tối ưu hóa vị trí";
           infoColor = Colors.purple;
        }
      }

      setState(() {
          targetPoints = results;
          resultDisplay = displayMsg;
          accuracyInfo = infoMsg;
          accuracyColor = infoColor;
          if (results.isNotEmpty) {
             _setMock(results[0].latitude, results[0].longitude, fromTarget: true, targetIndex: 0);
          }
      });
    } catch (e) { 
      _showMsg("Lỗi tính toán: $e"); 
    }
  }

  void _prevTarget() {
    if (targetPoints.isEmpty) return;
    int newIndex = mockingTargetIndex - 1;
    if (newIndex < 0) newIndex = targetPoints.length - 1; 
    _setMock(targetPoints[newIndex].latitude, targetPoints[newIndex].longitude, fromTarget: true, targetIndex: newIndex);
    _showMsg("Đang Mock: K${newIndex + 1}");
  }

  void _nextTarget() {
    if (targetPoints.isEmpty) return;
    int newIndex = mockingTargetIndex + 1;
    if (newIndex >= targetPoints.length) newIndex = 0;
    _setMock(targetPoints[newIndex].latitude, targetPoints[newIndex].longitude, fromTarget: true, targetIndex: newIndex);
    _showMsg("Đang Mock: K${newIndex + 1}");
  }

  void _requestFocus(int index) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (index >= 0 && index < beacons.length) {
        beacons[index].focusNode.requestFocus();
      }
    });
  }

  void _assignSavedTargetToP(LatLng location) {
    int targetIndex = -1;
    String unitToUse = 'ft'; 
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
      resultDisplay = "Đang chạy điểm lưu";
      accuracyInfo = "Nguồn: Danh sách đã lưu";
      selectedIndex = targetIndex;
      isMockingTarget = false;
      searchMarker = null;
      _mapController.move(location, 17);
    });
    _requestFocus(targetIndex); 
    _setMock(location.latitude, location.longitude);
    _showMsg("Đã gán và chạy Mock tại P${targetIndex + 1}");
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
          _showMsg("Đang chạy Mock P${index + 1} (Vị trí cũ)");
      } 
      else {
        int bestReferenceIndex = -1;
        double minDistance = double.infinity;
        for (int i = 0; i < beacons.length; i++) {
          if (i == index) continue;
          if (beacons[i].location != null && beacons[i].controller.text.isNotEmpty) {
             double? dist = double.tryParse(beacons[i].controller.text);
             if (dist != null && dist > 0 && dist < minDistance) {
                 minDistance = dist;
                 bestReferenceIndex = i;
             }
          }
        }

        if (bestReferenceIndex == -1) {
          Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
          finalPos = LatLng(p.latitude, p.longitude);
          _showMsg("P${index + 1}: Đã lấy vị trí GPS thật");
        } else {
          LatLng baseLoc = beacons[bestReferenceIndex].location!;
          double distMeters = _getRadiusInMeters(beacons[bestReferenceIndex]);
          double optimalBearing = _calculateOptimalBearing(baseLoc, index);
          finalPos = _calculatePointFromBearing(baseLoc, distMeters, optimalBearing);
          _showMsg("P${index + 1}: Tạo cách P${bestReferenceIndex + 1} (có bù sai số)");
        }
      }

      setState(() {
        beacons[index].location = finalPos;
        selectedIndex = index;
        targetPoints.clear(); 
        resultDisplay = "Dữ liệu P thay đổi";
        accuracyInfo = "Cần tính toán lại";
        isMockingTarget = false;
        if (myRealLocation == null && index == 0) { myRealLocation = finalPos; }
      });
      _mapController.move(finalPos, 16);
      _setMock(finalPos.latitude, finalPos.longitude);
    } catch (e) { _showMsg("Lỗi: $e"); }
  }

  Future<void> _resetCurrentBeacon() async {
    if (selectedIndex == null) { _showMsg("Chưa chọn điểm P nào để reset!"); return; }
    int index = selectedIndex!;

    if (index == 2 && beacons.length >= 3) {
       var b1 = beacons[0];
       var b2 = beacons[1];
       if (b1.location != null && b1.controller.text.isNotEmpty &&
           b2.location != null && b2.controller.text.isNotEmpty) {
           
           double r1 = _getRadiusInMeters(b1);
           double r2 = _getRadiusInMeters(b2);
           List<LatLng> roots = _calculateTwoCircleIntersectionPrecise(b1.location!, r1, b2.location!, r2);

           if (roots.length == 2) {
              LatLng k1 = roots[0];
              LatLng k2 = roots[1];
              LatLng currentP3 = beacons[index].location ?? k1; 
              double dist1 = _haversineDistance(currentP3, k1);
              double dist2 = _haversineDistance(currentP3, k2);

              LatLng newPos;
              String msg;
              if (dist1 < dist2) {
                 newPos = k2; 
                 msg = "Đã chuyển P3 sang K2";
              } else {
                 newPos = k1; 
                 msg = "Đã chuyển P3 sang K1";
              }

              setState(() {
                beacons[index].location = newPos;
                beacons[index].controller.clear(); 
                targetPoints.clear(); 
              });
              _setMock(newPos.latitude, newPos.longitude);
              _mapController.move(newPos, 17);
              _showMsg(msg);
              return; 
           }
       }
    }

    int bestRefIndex = -1;
    double minRefDist = double.infinity;

    for (int i = 0; i < beacons.length; i++) {
      if (i == index) continue;
      if (beacons[i].location != null && beacons[i].controller.text.isNotEmpty) {
         double? d = double.tryParse(beacons[i].controller.text);
         if (d != null && d > 0 && d < minRefDist) { minRefDist = d; bestRefIndex = i; }
      }
    }

    LatLng newPos;
    if (bestRefIndex != -1) {
      double distMeters = _getRadiusInMeters(beacons[bestRefIndex]);
      LatLng center = beacons[bestRefIndex].location!;
      int currentStep = beacons[index].resetStep; 
      double fixedBearing = 0.0;
      switch (currentStep % 4) {
        case 0: fixedBearing = 0.0; break;
        case 1: fixedBearing = 180.0; break;
        case 2: fixedBearing = 270.0; break;
        case 3: fixedBearing = 90.0; break;
      }
      String directionName = "";
      if (currentStep % 4 == 0) directionName = "Bắc (0°)";
      else if (currentStep % 4 == 1) directionName = "Nam (180°)";
      else if (currentStep % 4 == 2) directionName = "Tây (270°)";
      else directionName = "Đông (90°)";
      beacons[index].resetStep++; 
      newPos = _calculatePointFromBearing(center, distMeters, fixedBearing);
      _showMsg("P${index+1}: Đang ở hướng $directionName");
    } else {
      Position p = await Geolocator.getCurrentPosition();
      newPos = LatLng(p.latitude, p.longitude);
      _showMsg("Không có P làm tâm, lấy lại GPS thật");
    }

    setState(() {
      beacons[index].location = newPos;
      beacons[index].controller.clear();
      targetPoints.clear();
      resultDisplay = "P${index+1} đã làm mới";
      accuracyInfo = "Dữ liệu đã reset";
      accuracyColor = Colors.orange;
    });
    _requestFocus(index); 
    _mapController.move(newPos, _mapController.camera.zoom);
    _setMock(newPos.latitude, newPos.longitude);
  }

  void _restartWithResultAsP1() {
    LatLng? newStart;
    if (isMockingTarget && targetPoints.isNotEmpty) { newStart = targetPoints[mockingTargetIndex]; } 
    else if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) { newStart = beacons[selectedIndex!].location; }
    else if (targetPoints.isNotEmpty) { newStart = targetPoints[0]; }

    if (newStart == null) { _showMsg("Chưa có tọa độ nào để gán!"); return; }
    
    String unitP1 = beacons.isNotEmpty ? beacons[0].unit : 'ft';

    _stopMock();
    setState(() {
      beacons = [Beacon(location: newStart, color: Colors.blue, unit: unitP1)];
      targetPoints.clear();
      resultDisplay = "0.000000, 0.000000";
      accuracyInfo = "Chờ nhập liệu...";
      accuracyColor = Colors.grey;
      searchMarker = null;
      selectedIndex = 0; 
      isMockingTarget = false;
    });
    _requestFocus(0); 
    _mapController.move(newStart, 16);
    _setMock(newStart.latitude, newStart.longitude);
    _showMsg("Đã lấy vị trí đang chạy làm gốc P1!");
  }

  void _assignResultToNextP() {
    if (targetPoints.isEmpty) return;
    LatLng pointToUse = targetPoints[isMockingTarget ? mockingTargetIndex : 0];
    int nextIndex = -1;
    String unitToUse = 'ft';
    if (beacons.isNotEmpty) unitToUse = beacons.last.unit;

    for (int i = 0; i < beacons.length; i++) {
      if (beacons[i].location == null) { nextIndex = i; break; }
    }
    setState(() {
      if (nextIndex != -1) {
        beacons[nextIndex].location = pointToUse;
        _showMsg("Đã chuyển kết quả vào P${nextIndex + 1}");
      } else {
        beacons.add(Beacon(location: pointToUse, color: colorPalette[beacons.length % colorPalette.length], unit: unitToUse));
        nextIndex = beacons.length - 1;
        _showMsg("Đã tạo P${beacons.length} mới từ kết quả");
      }
    });
    _requestFocus(nextIndex); 
  }

  // --- LOGIC TÌM KIẾM ---
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

  // --- LOGIC LƯU TRỮ ---
  void _saveCurrentTarget() {
    LatLng? pointToSave;
    String defaultName = "";
    if (isMockingTarget && targetPoints.isNotEmpty) { pointToSave = targetPoints[mockingTargetIndex]; defaultName = "Mục tiêu ${savedTargets.length + 1}"; } 
    else if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) { pointToSave = beacons[selectedIndex!].location; defaultName = "Điểm P${selectedIndex! + 1}"; }
    else if (targetPoints.isNotEmpty) { pointToSave = targetPoints[0]; defaultName = "Mục tiêu ${savedTargets.length + 1}"; }

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
    var status = await [Permission.location].request();
    if (status[Permission.location]!.isGranted) {
      Position p = await Geolocator.getCurrentPosition();
      LatLng current = LatLng(p.latitude, p.longitude);
      setState(() => myRealLocation = current);
      _mapController.move(current, 15);
      Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5))
          .listen((p) { if (mounted) setState(() => myRealLocation = LatLng(p.latitude, p.longitude)); });
    }
  }

  Future<void> _openNavigation(LatLng destination) async {
    Uri uri = Platform.isAndroid 
      ? Uri.parse('google.navigation:q=${destination.latitude},${destination.longitude}')
      : Uri.parse('maps://?q=${destination.latitude},${destination.longitude}');
    if (await canLaunchUrl(uri)) { await launchUrl(uri); } else { _showMsg("Lỗi mở bản đồ"); }
  }

  // --- CÁC HÀM UI PHỤ TRỢ ---
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

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 1)));

  void _showInstructions() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.help_outline, color: Colors.blue), SizedBox(width: 10), Text("Hướng dẫn")]),
        content: const SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text("1. Nhập khoảng cách cho các điểm P."),
            Text("2. Nếu chọn mi hoặc km, hệ thống TỰ ĐỘNG CỘNG 0.5 để bù sai số làm tròn."),
            Text("3. Thanh ở trên dùng để đổi đơn vị cho P đang nhập liệu hoặc đang Mock."),
            Text("4. Nút (+) tạo P mới (Chỉ khi P hiện tại đã hoàn thành)."),
            Text("5. NHẤN GIỮ NÚT NỔI để ĐÓNG ứng dụng."),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ),
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
        title: Text("Xóa điểm P${index + 1}?"),
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
    _showMsg("Đã xóa P${index + 1} cũ");
  }

  void _showTargetOptions(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(savedTargets[index].name),
        actions: [
          IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.green), onPressed: () { Navigator.pop(ctx); _assignSavedTargetToP(savedTargets[index].location); }),
          IconButton(icon: const Icon(Icons.directions, color: Colors.orange), onPressed: () { Navigator.pop(ctx); _openNavigation(savedTargets[index].location); }),
          IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () { Navigator.pop(ctx); _editTargetName(index); }),
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { Navigator.pop(ctx); _confirmDeleteTarget(index); }),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ĐÓNG")),
        ],
      ),
    );
  }

  void _showSavedTargetsSheet() {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView.builder(
          itemCount: savedTargets.length,
          itemBuilder: (c, i) => ListTile(
            leading: const Icon(Icons.location_on, color: Colors.purple),
            title: Text(savedTargets[i].name),
            trailing: IconButton(icon: const Icon(Icons.add_location_alt, color: Colors.green), onPressed: () { _assignSavedTargetToP(savedTargets[i].location); Navigator.pop(ctx); }),
            onTap: () { _mapController.move(savedTargets[i].location, 15); Navigator.pop(ctx); },
          ),
        ),
      ),
    );
  }

  // --- LOGIC ĐỔI ĐƠN VỊ THÔNG MINH ---
  void _setUnitForSelectedBeacon(String unit) {
    setState(() {
      int focusedIndex = beacons.indexWhere((b) => b.focusNode.hasFocus);
      
      if (focusedIndex != -1) {
         beacons[focusedIndex].unit = unit;
      } 
      else if (selectedIndex != null) {
        beacons[selectedIndex!].unit = unit; 
      } 
      else {
        defaultUnit = unit; 
      }
    });
  }

  // --- BUILD UI ---
  @override
  Widget build(BuildContext context) {
    String activeUnitForChip = defaultUnit;
    int focusedIndex = beacons.indexWhere((b) => b.focusNode.hasFocus);
    
    if (focusedIndex != -1) {
      activeUnitForChip = beacons[focusedIndex].unit;
    } else if (selectedIndex != null) {
      activeUnitForChip = beacons[selectedIndex!].unit;
    }

    bool isAnyMocking = isMockingTarget || selectedIndex != null;
    return Scaffold(
      resizeToAvoidBottomInset: true, 
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8), color: Colors.white,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(onPressed: _showInstructions, icon: const Icon(Icons.help_outline, color: Colors.blue)),
                      
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: availableUnits.map((unit) => Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: ChoiceChip(
                                label: Text(unit, style: const TextStyle(fontSize: 10)), 
                                selected: activeUnitForChip == unit, 
                                onSelected: (val) {
                                  if (val) _setUnitForSelectedBeacon(unit);
                                },
                              ),
                            )).toList(),
                          ),
                        ),
                      ),

                      Row(
                        children: [
                            GestureDetector(
                             onLongPress: _pickTargetApp, 
                             child: IconButton(
                              icon: Icon(Icons.chat_bubble, color: targetAppPackage != null ? Colors.blueAccent : Colors.grey),
                              onPressed: _triggerOverlay, 
                              tooltip: "Bật/Tắt Nút Nổi (Nhấn giữ để chọn App)",
                             ),
                            ),
                            IconButton(
                             icon: Icon(isSearchVisible ? Icons.search_off : Icons.search, color: Colors.blue),
                             onPressed: () => setState(() => isSearchVisible = !isSearchVisible),
                           ),
                        ],
                      )
                    ],
                  ),
                  SizedBox(
                    height: 70,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: beacons.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == beacons.length) {
                          return IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.green, size: 35), 
                            onPressed: () {
                              // CHECK: P CUỐI CÙNG ĐÃ HOÀN THÀNH CHƯA?
                              if (beacons.isNotEmpty) {
                                Beacon last = beacons.last;
                                if (last.location == null || last.controller.text.trim().isEmpty) {
                                  _showMsg("P${beacons.length} chưa hoàn thành (thiếu vị trí hoặc khoảng cách)!");
                                  return;
                                }
                              }

                              setState(() {
                                // --- LOGIC MỚI: TÍNH K -> XÓA XA NHẤT -> THÊM K VÀO ---
                                String defaultNewUnit = 'ft';
                                if (beacons.isNotEmpty) {
                                  defaultNewUnit = beacons.last.unit;
                                } else {
                                  defaultNewUnit = defaultUnit;
                                }

                                if (beacons.length >= 3) {
                                  LatLng? bestK = _internalCalculateBestFit();

                                  if (bestK != null) {
                                      int worstIndex = -1;
                                      double maxDist = -1;
                                      
                                      for (int k = 0; k < beacons.length; k++) {
                                        if (beacons[k].location != null) {
                                          double d = _haversineDistance(beacons[k].location!, bestK);
                                          if (d > maxDist) {
                                            maxDist = d;
                                            worstIndex = k;
                                          }
                                        }
                                      }

                                      if (worstIndex != -1) {
                                        beacons[worstIndex].dispose();
                                        beacons.removeAt(worstIndex);
                                      }

                                      beacons.add(Beacon(location: bestK, color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
                                      
                                      selectedIndex = beacons.length - 1;
                                      targetPoints.clear();
                                      isMockingTarget = false;
                                      
                                      _setMock(bestK.latitude, bestK.longitude);
                                      _mapController.move(bestK, 17);
                                      _requestFocus(beacons.length - 1); 
                                      
                                      _showMsg("Đã thay thế P xa nhất bằng K vừa tính!");
                                      return; 
                                  }
                                }

                                LatLng? finalPos; 
                                bool autoPlaced = false;

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
                                        finalPos = intersections[0]; // K1
                                        autoPlaced = true;
                                        _showMsg("Đã tạo P${beacons.length + 1} tại giao điểm K1 (tự động)");
                                      }
                                    } catch (e) {}
                                  }
                                }
                                
                                if (!autoPlaced) {
                                  int newIndex = beacons.length; 
                                  if (newIndex > 0) {
                                     Beacon prevBeacon = beacons[newIndex - 1];
                                     if (prevBeacon.location != null && prevBeacon.controller.text.isNotEmpty) {
                                           double? r = double.tryParse(prevBeacon.controller.text);
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
                                  
                                  _setMock(finalPos!.latitude, finalPos!.longitude);
                                  _mapController.move(finalPos!, 17);
                                } else {
                                  beacons.add(Beacon(color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
                                }
                                
                                _requestFocus(beacons.length - 1); 
                              });
                            }
                          );
                        }
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
                                    color: selectedIndex == i ? Colors.red : (beacons[i].location != null ? beacons[i].color : Colors.grey.shade400),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text("P${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                              TextField(
                                controller: beacons[i].controller, 
                                focusNode: beacons[i].focusNode, 
                                keyboardType: TextInputType.number, 
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
                  const SizedBox(height: 8),
                  GestureDetector(
                    onLongPress: () { Clipboard.setData(ClipboardData(text: resultDisplay)); _showMsg("Đã copy!"); },
                    child: Column(
                      children: [
                        Text(resultDisplay, style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 15, color: accuracyColor)),
                        Text(accuracyInfo, style: TextStyle(fontSize: 11, color: accuracyColor, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const Divider(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () {
                        setState(() { beacons = [Beacon(color: Colors.blue, unit: 'ft')]; targetPoints.clear(); searchMarker = null; resultDisplay = "0.000000, 0.000000"; accuracyInfo = "Chờ nhập liệu..."; accuracyColor = Colors.grey; });
                        _stopMock();
                      }),
                      if (targetPoints.isNotEmpty || selectedIndex != null) IconButton(icon: const Icon(Icons.looks_one, color: Colors.teal, size: 28), onPressed: _restartWithResultAsP1),
                      if (targetPoints.isNotEmpty) IconButton(icon: const Icon(Icons.playlist_add_check, color: Colors.green, size: 28), onPressed: _assignResultToNextP),
                      
                      if (selectedIndex != null) IconButton(icon: const Icon(Icons.refresh, color: Colors.orange, size: 28), onPressed: _resetCurrentBeacon),
                      
                      IconButton(
                        onPressed: (targetPoints.isEmpty && selectedIndex == null) ? null : (isAnyMocking ? _stopMock : () { 
                          if (targetPoints.isNotEmpty) _setMock(targetPoints[mockingTargetIndex].latitude, targetPoints[mockingTargetIndex].longitude, fromTarget: true, targetIndex: mockingTargetIndex); 
                        }),
                        icon: Icon(isAnyMocking ? Icons.stop_circle : Icons.play_circle, color: isAnyMocking ? Colors.red : Colors.green, size: 32),
                      ),
                      
                      if (targetPoints.isNotEmpty || selectedIndex != null) IconButton(icon: const Icon(Icons.save, color: Colors.blue), onPressed: _saveCurrentTarget),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                        onPressed: _calculateTrilateration, 
                        child: const Text("TÍNH", style: TextStyle(fontWeight: FontWeight.bold))
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const LatLng(10.7626, 106.6601),
                      initialZoom: 13,
                      onTap: (_, latlng) {
                        if (selectedIndex != null && !isMockingTarget) {
                          setState(() { beacons[selectedIndex!].location = latlng; targetPoints.clear(); });
                          _setMock(latlng.latitude, latlng.longitude);
                          _requestFocus(selectedIndex!); 
                        }
                      },
                      onLongPress: (_, latlng) {
                        int targetIndex = -1;
                        String unitToUse = 'ft';
                        if (beacons.isNotEmpty) unitToUse = beacons.last.unit;

                        for (int i = 0; i < beacons.length; i++) {
                          if (beacons[i].location == null) {
                            targetIndex = i;
                            break;
                          }
                        }

                        setState(() {
                          if (targetIndex != -1) {
                            beacons[targetIndex].location = latlng;
                            selectedIndex = targetIndex;
                          } else {
                            beacons.add(Beacon(location: latlng, color: colorPalette[beacons.length % colorPalette.length], unit: unitToUse));
                            targetIndex = beacons.length - 1;
                            selectedIndex = targetIndex;
                          }
                          targetPoints.clear();
                          isMockingTarget = false;
                        });

                        _requestFocus(targetIndex);
                        _setMock(latlng.latitude, latlng.longitude);
                        _showMsg("Đã gán và MOCK P${targetIndex + 1} từ điểm nhấn giữ");
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                              Marker(point: beacons[i].location!, width: 30, height: 30, child: Container(decoration: BoxDecoration(color: selectedIndex == i ? Colors.red : beacons[i].color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text("${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))))),
                          for (int i = 0; i < targetPoints.length; i++)
                            Marker(point: targetPoints[i], width: 60, height: 60, child: Icon(Icons.location_searching, color: (isMockingTarget && mockingTargetIndex == i) ? Colors.red : Colors.green, size: 35)),
                          for (int i = 0; i < savedTargets.length; i++)
                            Marker(point: savedTargets[i].location, width: 70, height: 60, child: GestureDetector(onTap: () => _showTargetOptions(i), child: const Icon(Icons.bookmark, color: Colors.purple, size: 20))),
                        ],
                      ),
                    ],
                  ),
                  if (isSearchVisible)
                    Positioned(top: 10, left: 15, right: 15, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)), child: TextField(controller: _searchCtrl, autofocus: true, decoration: InputDecoration(hintText: "Tìm kiếm...", border: InputBorder.none, prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => isSearchVisible = false))), onSubmitted: (_) => _searchLocation()))),
                  Positioned(right: 15, bottom: 15, child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (savedTargets.isNotEmpty) FloatingActionButton(heroTag: "listBtn", mini: true, backgroundColor: Colors.purple, onPressed: _showSavedTargetsSheet, child: const Icon(Icons.list, color: Colors.white)),
                    const SizedBox(height: 10),
                    FloatingActionButton(heroTag: "locBtn", mini: true, backgroundColor: Colors.white, onPressed: () async { Position p = await Geolocator.getCurrentPosition(); _mapController.move(LatLng(p.latitude, p.longitude), 15); }, child: const Icon(Icons.my_location, color: Colors.blue)),
                  ])),
                  if (targetPoints.length > 1 && isMockingTarget)
                    Positioned(bottom: 20, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)), child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: _prevTarget),
                      Text("K${mockingTargetIndex + 1} / ${targetPoints.length}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20), onPressed: _nextTarget),
                    ])))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}