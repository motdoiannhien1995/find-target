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

// --- MAIN WIDGET ---
class MockApp extends StatefulWidget {
  const MockApp({super.key});
  @override
  State<MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<MockApp> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.example.mock/gps');
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _mockTimer;

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

  static const double earthRadius = 6371000.0;
  
  final List<Color> colorPalette = [Colors.orange, Colors.teal, Colors.pink, Colors.brown, Colors.indigo, Colors.lime];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
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
    WidgetsBinding.instance.removeObserver(this);
    _mockTimer?.cancel();
    _mapController.dispose();
    _searchCtrl.dispose();
    for (var b in beacons) b.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreKeyboardFocus();
    }
  }

  void _restoreKeyboardFocus() {
    if (selectedIndex != null && selectedIndex! < beacons.length) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          beacons[selectedIndex!].focusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    }
  }

  double _getRadiusInMeters(Beacon b) {
    double inputVal = double.tryParse(b.controller.text) ?? 0;
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
      print("Lỗi fit camera: $e");
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

  Future<void> _setMock(double lat, double lng, {bool fromTarget = false}) async {
    _mockTimer?.cancel();
    void pushMock() {
      try { platform.invokeMethod('setMockLocation', {"lat": lat, "lng": lng}); } catch (e) { print("Lỗi Mock: $e"); }
    }
    pushMock();
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (timer) { pushMock(); });
    _showInvincibleOverlay(); 
    
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

  LatLng? _internalCalculateBestFit() {
      var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
      if (validBeacons.length < 2) return null;

      LatLng p1 = validBeacons[0].location!;
      LatLng p2 = validBeacons[1].location!;
      double r1 = _getRadiusInMeters(validBeacons[0]);
      double r2 = _getRadiusInMeters(validBeacons[1]);

      var roots = _calculateTwoCircleIntersectionPrecise(p1, r1, p2, r2);
      LatLng bestStartNode;
      
      if (roots.isEmpty) {
        double sLat = 0, sLng = 0;
        for (var b in validBeacons) { sLat += b.location!.latitude; sLng += b.location!.longitude; }
        bestStartNode = LatLng(sLat/validBeacons.length, sLng/validBeacons.length);
      } else {
        if (roots.length == 2 && validBeacons.length >= 3) {
           double err1 = _calculateTotalError(roots[0], validBeacons);
           double err2 = _calculateTotalError(roots[1], validBeacons);
           bestStartNode = (err1 < err2) ? roots[0] : roots[1];
        } else {
           bestStartNode = roots[0];
        }
      }
      return _optimizePoint(bestStartNode, validBeacons);
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
    _showMsg("Đang chạy P${targetIndex + 1}");
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

             // Lấy điểm K gần với vị trí P3 hiện tại nhất (tính lại K cập nhật theo dữ liệu P1, P2)
             LatLng newPos = (dist1 < dist2) ? k1 : k2;

             setState(() {
               beacons[index].location = newPos;
               targetPoints.clear(); 
             });
             _setMock(newPos.latitude, newPos.longitude);
             _zoomToFitAll(); 
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
      beacons[index].resetStep++; 
      newPos = _calculatePointFromBearing(center, distMeters, fixedBearing);
    } else {
      Position p = await Geolocator.getCurrentPosition();
      newPos = LatLng(p.latitude, p.longitude);
    }

    setState(() {
      beacons[index].location = newPos;
      beacons[index].controller.clear();
      targetPoints.clear();
    });
    _requestFocus(index); 
    _mapController.move(newPos, _mapController.camera.zoom);
    _setMock(newPos.latitude, newPos.longitude);
    _zoomToFitAll(); 
  }

  void _restartWithResultAsP1() {
    LatLng? newStart;
    if (isMockingTarget && targetPoints.isNotEmpty) { newStart = targetPoints[0]; } 
    else if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) { newStart = beacons[selectedIndex!].location; }
    else if (targetPoints.isNotEmpty) { newStart = targetPoints[0]; }

    if (newStart == null) { _showMsg("Chưa có tọa độ nào để gán!"); return; }
    
    String unitP1 = beacons.isNotEmpty ? beacons[0].unit : 'km';

    _stopMock();
    setState(() {
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
    _showMsg("Đã gán gốc P1 mới!");
  }

  void _assignResultToNextP() {
    if (targetPoints.isEmpty) return;
    LatLng pointToUse = targetPoints[0];
    int nextIndex = -1;
    String unitToUse = 'km'; 
    if (beacons.isNotEmpty) unitToUse = beacons.last.unit;

    for (int i = 0; i < beacons.length; i++) {
      if (beacons[i].location == null) { nextIndex = i; break; }
    }
    setState(() {
      if (nextIndex != -1) {
        beacons[nextIndex].location = pointToUse;
      } else {
        beacons.add(Beacon(location: pointToUse, color: colorPalette[beacons.length % colorPalette.length], unit: unitToUse));
        nextIndex = beacons.length - 1;
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
    if (isMockingTarget && targetPoints.isNotEmpty) { pointToSave = targetPoints[0]; defaultName = "Mục tiêu ${savedTargets.length + 1}"; } 
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
    _zoomToFitAll(); 
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
      else if (selectedIndex != null && selectedIndex! < beacons.length) { 
        beacons[selectedIndex!].unit = unit; 
      } 
      else {
        defaultUnit = unit; 
      }
    });
  }

  // HÀM MỚI: Logic thêm P được tách riêng biệt để gọn gàng hơn
  void _addNewBeacon() {
    if (beacons.isNotEmpty) {
      Beacon last = beacons.last;
      if (last.location == null || last.controller.text.trim().isEmpty) {
        _showMsg("P${beacons.length} chưa hoàn thành!");
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
            bool allUnder100m = true;
            for (var b in beacons) {
                double r = _getRadiusInMeters(b);
                if (r >= 100 || r == 0) {
                    allUnder100m = false;
                    break;
                }
            }

            int worstIndex = -1;

            if (allUnder100m) {
                worstIndex = 0;
            } else {
                double maxDist = -1;
                for (int k = 0; k < beacons.length; k++) {
                  if (beacons[k].location != null) {
                    double d = _haversineDistance(beacons[k].location!, finalPoint);
                    if (d > maxDist) { maxDist = d; worstIndex = k; }
                  }
                }
            }

            if (worstIndex != -1) {
              beacons[worstIndex].dispose();
              beacons.removeAt(worstIndex);
            }

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
        _zoomToFitAll();
      } else {
        beacons.add(Beacon(color: colorPalette[beacons.length % colorPalette.length], unit: defaultNewUnit));
      }
      _requestFocus(beacons.length - 1); 
    });
  }

  // --- BUILD UI ---
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
                  SizedBox(
                    height: 70,
                    child: Row(
                      children: [
                        // Danh sách các điểm P
                        Expanded(
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
                      ],
                    ),
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
                  
                  // HÀNG GỘP ĐƠN VỊ & CÁC NÚT (TÌM KIẾM, OVERLAY)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Cụm 1: Các nút đơn vị (màu xanh dương)
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: availableUnits.map((unit) => Padding(
                                padding: const EdgeInsets.only(right: 6.0),
                                child: ChoiceChip(
                                  showCheckmark: false, // Ẩn dấu tick
                                  label: Text(unit, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: activeUnitForChip == unit ? Colors.white : Colors.black87)), 
                                  selected: activeUnitForChip == unit, 
                                  selectedColor: Colors.blue, // Chuyển sang xanh thay vì tím
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
                        
                        // Cụm 2: Nút nổi và nút tìm kiếm (bên phải)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onLongPress: _pickTargetApp, 
                              child: IconButton(
                                icon: Icon(Icons.layers, color: targetAppPackage != null ? Colors.blueAccent : Colors.grey, size: 26), 
                                onPressed: _triggerOverlay, 
                                tooltip: "Bật/Tắt Nút Nổi",
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ),
                            const SizedBox(width: 16),
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

                  // HÀNG 7 NÚT (SẼ KHÔNG BỊ CO GIÃN KHI ẨN DO DÙNG MAINTAINSIZE: TRUE)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 1. Nút (+) thêm P - Luôn hiển thị
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green, size: 35), 
                        onPressed: _addNewBeacon
                      ),

                      // 2. Nút Xóa tất cả (thùng rác)
                      Visibility(
                        visible: beacons.isNotEmpty || targetPoints.isNotEmpty || searchMarker != null,
                        maintainSize: true, maintainAnimation: true, maintainState: true,
                        child: IconButton(
                          icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 30), 
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

                      // 3. Nút Gán P1
                      Visibility(
                        visible: targetPoints.isNotEmpty || selectedIndex != null,
                        maintainSize: true, maintainAnimation: true, maintainState: true,
                        child: IconButton(icon: const Icon(Icons.looks_one, color: Colors.teal, size: 28), onPressed: _restartWithResultAsP1),
                      ),
                      
                      // 4. Nút Gán P tiếp theo
                      Visibility(
                        visible: targetPoints.isNotEmpty,
                        maintainSize: true, maintainAnimation: true, maintainState: true,
                        child: IconButton(icon: const Icon(Icons.playlist_add_check, color: Colors.green, size: 28), onPressed: _assignResultToNextP),
                      ),
                      
                      // 5. Nút Refresh
                      Visibility(
                        visible: selectedIndex != null,
                        maintainSize: true, maintainAnimation: true, maintainState: true,
                        child: IconButton(icon: const Icon(Icons.refresh, color: Colors.orange, size: 28), onPressed: _resetCurrentBeacon),
                      ),
                      
                      // 6. Nút Play/Stop
                      Visibility(
                        visible: targetPoints.isNotEmpty || selectedIndex != null,
                        maintainSize: true, maintainAnimation: true, maintainState: true,
                        child: IconButton(
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
                      
                      // 7. Nút Save
                      Visibility(
                        visible: targetPoints.isNotEmpty || selectedIndex != null,
                        maintainSize: true, maintainAnimation: true, maintainState: true,
                        child: IconButton(icon: const Icon(Icons.save, color: Colors.blue), onPressed: _saveCurrentTarget),
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
                      minZoom: 3.0, 
                      maxZoom: 18.0,
                      cameraConstraint: CameraConstraint.contain(
                        bounds: LatLngBounds(
                          const LatLng(-90, -180),
                          const LatLng(90, 180),
                        ),
                      ),
                      onTap: (_, latlng) {
                        if (selectedIndex != null && !isMockingTarget) {
                          setState(() { beacons[selectedIndex!].location = latlng; targetPoints.clear(); });
                          _setMock(latlng.latitude, latlng.longitude);
                          _requestFocus(selectedIndex!); 
                        }
                      },
                      onLongPress: (_, latlng) {
                        int targetIndex = -1;
                        String unitToUse = 'km'; 
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
                        _showMsg("Đã gán và MOCK P${targetIndex + 1}");
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
                              Marker(point: beacons[i].location!, width: 30, height: 30, child: Container(decoration: BoxDecoration(color: selectedIndex == i ? Colors.red : beacons[i].color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text("${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))))),
                          for (int i = 0; i < targetPoints.length; i++)
                            Marker(point: targetPoints[i], width: 60, height: 60, child: const Icon(Icons.location_searching, color: Colors.green, size: 35)),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}