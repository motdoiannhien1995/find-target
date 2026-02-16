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
  
  Beacon({this.location, String dist = "", Color? color}) 
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

  // Mặc định chỉ có 1 điểm P1
  List<Beacon> beacons = [Beacon(color: Colors.blue)];
  
  List<SavedTarget> savedTargets = [];
  String selectedUnit = 'm'; 
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0, 'mi': 1609.34};

  int? selectedIndex; 
  List<LatLng> targetPoints = [];
  LatLng? myRealLocation;
  LatLng? searchMarker; 
  String resultDisplay = "0.000000, 0.000000";
  String accuracyInfo = "Chờ nhập dữ liệu...";
  Color accuracyColor = Colors.grey; 
  bool isMockingTarget = false;
  int mockingTargetIndex = 0;
  bool isSearchVisible = false;

  static const double earthRadius = 6371000.0;
  static const double strictThreshold = 10.0; 
  final List<Color> colorPalette = [Colors.orange, Colors.teal, Colors.pink, Colors.brown, Colors.indigo, Colors.lime];

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadData(); 
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    _mapController.dispose();
    _searchCtrl.dispose();
    for (var b in beacons) b.dispose();
    super.dispose();
  }

  void _requestFocus(int index) {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (index >= 0 && index < beacons.length) {
        beacons[index].focusNode.requestFocus();
      }
    });
  }

  // --- LOGIC MOCK ---
  Future<void> _setMock(double lat, double lng, {bool fromTarget = false, int targetIndex = 0}) async {
    _mockTimer?.cancel();
    void pushMock() {
      try { platform.invokeMethod('setMockLocation', {"lat": lat, "lng": lng}); } catch (e) { print("Lỗi Mock: $e"); }
    }
    pushMock();
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (timer) { pushMock(); });
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
    } catch (e) { print(e); }
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

  void _assignSavedTargetToP(LatLng location) {
    int targetIndex = -1;
    for (int i = 0; i < beacons.length; i++) {
      if (beacons[i].location == null) { targetIndex = i; break; }
    }
    setState(() {
      if (targetIndex != -1) {
        beacons[targetIndex].location = location;
      } else {
        beacons.add(Beacon(location: location, color: colorPalette[beacons.length % colorPalette.length]));
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
          double distMeters = (minDistance * 1.0) * unitToMeter[selectedUnit]!;
          double optimalBearing = _calculateOptimalBearing(baseLoc, index);
          finalPos = _calculatePointFromBearing(baseLoc, distMeters, optimalBearing);
          _showMsg("P${index + 1}: Tạo cách P${bestReferenceIndex + 1} đúng 1 bán kính");
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
      double distMeters = (minRefDist * 1.0) * unitToMeter[selectedUnit]!;
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

  double _toRadians(double degree) => degree * pi / 180.0;
  double _toDegrees(double radian) => radian * 180.0 / pi;

  LatLng _calculatePointFromBearing(LatLng start, double distanceMeters, double bearingDegrees) {
    double bearingRad = bearingDegrees * (pi / 180); 
    double startLat = start.latitude * (pi / 180);
    double startLng = start.longitude * (pi / 180);
    double distRatio = distanceMeters / earthRadius;
    double endLat = asin(sin(startLat) * cos(distRatio) + cos(startLat) * sin(distRatio) * cos(bearingRad));
    double endLng = startLng + atan2(sin(bearingRad) * sin(distRatio) * cos(startLat), cos(distRatio) - sin(startLat) * sin(endLat));
    return LatLng(endLat * (180 / pi), endLng * (180 / pi));
  }

  Point<double> _latLngToXy(LatLng origin, LatLng p) {
    double latAvg = _toRadians((origin.latitude + p.latitude) / 2);
    double mPerLat = 111320.0; 
    double mPerLng = 111320.0 * cos(latAvg); 
    double dy = (p.latitude - origin.latitude) * mPerLat;
    double dx = (p.longitude - origin.longitude) * mPerLng;
    return Point(dx, dy);
  }

  LatLng _xyToLatLng(LatLng origin, double x, double y) {
    double mPerLat = 111320.0;
    double latNew = origin.latitude + (y / mPerLat);
    double latAvg = _toRadians((origin.latitude + latNew) / 2);
    double mPerLng = 111320.0 * cos(latAvg);
    double lngNew = origin.longitude + (x / mPerLng);
    return LatLng(latNew, lngNew);
  }

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

  LatLng _computeOffset(LatLng from, double distance, double heading) {
    double distRatio = distance / earthRadius;
    double headingRad = _toRadians(heading);
    double fromLat = _toRadians(from.latitude);
    double fromLng = _toRadians(from.longitude);
    double toLat = asin(sin(fromLat) * cos(distRatio) + cos(fromLat) * sin(distRatio) * cos(headingRad));
    double toLng = fromLng + atan2(sin(headingRad) * sin(distRatio) * cos(fromLat), cos(distRatio) - sin(fromLat) * sin(toLat));
    return LatLng(_toDegrees(toLat), _toDegrees(toLng));
  }

  List<LatLng> _calculateTwoCircleIntersection(LatLng p1, double r1, LatLng p2, double r2) {
    Point<double> c1 = const Point(0, 0); 
    Point<double> c2 = _latLngToXy(p1, p2);
    double d = sqrt(pow(c2.x, 2) + pow(c2.y, 2));
    if (d > r1 + r2 || d < (r1 - r2).abs() || d == 0) return []; 
    double a = (r1 * r1 - r2 * r2 + d * d) / (2 * d);
    double h = sqrt(max(0, r1 * r1 - a * a));
    double x2 = c2.x * a / d;
    double y2 = c2.y * a / d;
    double x3_1 = x2 + h * c2.y / d;
    double y3_1 = y2 - h * c2.x / d;
    double x3_2 = x2 - h * c2.y / d;
    double y3_2 = y2 + h * c2.x / d;
    return [_xyToLatLng(p1, x3_1, y3_1), _xyToLatLng(p1, x3_2, y3_2)];
  }

  void _calculateTrilateration() {
    FocusScope.of(context).unfocus();
    var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
    if (validBeacons.length < 2) { _showMsg("Cần ít nhất 2 điểm!"); return; }

    try {
      List<LatLng> results = [];
      double finalResidual = 0;
      bool isTwoPoints = false;

      if (validBeacons.length == 2) {
         double r1 = double.parse(validBeacons[0].controller.text) * unitToMeter[selectedUnit]!;
         double r2 = double.parse(validBeacons[1].controller.text) * unitToMeter[selectedUnit]!;
         results = _calculateTwoCircleIntersection(validBeacons[0].location!, r1, validBeacons[1].location!, r2);
         if (results.isEmpty) {
           setState(() { targetPoints = []; resultDisplay = "KHÔNG CẮT NHAU"; accuracyInfo = "Khoảng cách sai lệch"; accuracyColor = Colors.red; });
           return;
         }
         isTwoPoints = true;
         finalResidual = 0;
      } 
      else {
        LatLng finalResult;
        bool isShortRange = (selectedUnit == 'm' || selectedUnit == 'ft');
        if (isShortRange) {
          LatLng origin = validBeacons[0].location!;
          List<Point<double>> points = [];
          List<double> radii = [];
          for (var b in validBeacons) {
            points.add(_latLngToXy(origin, b.location!));
            radii.add(double.parse(b.controller.text) * unitToMeter[selectedUnit]!);
          }
          double estX = 0, estY = 0;
          for (var p in points) { estX += p.x; estY += p.y; }
          estX /= points.length; estY /= points.length;
          double learningRate = 0.2;
          for (int i = 0; i < 5000; i++) {
            double shiftX = 0, shiftY = 0;
            for (int j = 0; j < points.length; j++) {
              double dx = estX - points[j].x;
              double dy = estY - points[j].y;
              double currentDist = sqrt(dx*dx + dy*dy);
              if (currentDist == 0) currentDist = 0.000001;
              double error = currentDist - radii[j];
              shiftX += -error * (dx / currentDist);
              shiftY += -error * (dy / currentDist);
            }
            estX += shiftX * learningRate / points.length;
            estY += shiftY * learningRate / points.length;
            if (shiftX.abs() < 1e-10 && shiftY.abs() < 1e-10) break;
            learningRate *= 0.995;
          }
          finalResult = _xyToLatLng(origin, estX, estY);
          double totalRes = 0;
          for (int i = 0; i < points.length; i++) {
             double dist = sqrt(pow(estX - points[i].x, 2) + pow(estY - points[i].y, 2));
             totalRes += (dist - radii[i]).abs();
          }
          finalResidual = totalRes / points.length;
        } else {
          double sumLat = 0, sumLng = 0;
          for (var b in validBeacons) { sumLat += b.location!.latitude; sumLng += b.location!.longitude; }
          LatLng currentEst = LatLng(sumLat / validBeacons.length, sumLng / validBeacons.length);
          double learningRate = 0.5;
          for (int i = 0; i < 2000; i++) {
            double moveLat = 0, moveLng = 0; 
            for (var b in validBeacons) {
              double currentDist = _haversineDistance(currentEst, b.location!);
              double targetDist = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
              double error = currentDist - targetDist;
              double bearingToB = _calculateBearing(currentEst, b.location!);
              double moveDist = error * learningRate;
              double rad = _toRadians(bearingToB);
              moveLat += moveDist * cos(rad); moveLng += moveDist * sin(rad);
            }
            double totalMoveMeters = sqrt(moveLat*moveLat + moveLng*moveLng) / validBeacons.length;
            double moveBearing = _toDegrees(atan2(moveLng, moveLat));
            if (totalMoveMeters > 0.0001) { currentEst = _computeOffset(currentEst, totalMoveMeters, moveBearing); } else { break; }
            learningRate *= 0.99;
          }
          finalResult = currentEst;
          double totalRes = 0;
          for (var b in validBeacons) {
            double realDist = _haversineDistance(finalResult, b.location!);
            double targetDist = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
            totalRes += (realDist - targetDist).abs();
          }
          finalResidual = totalRes / validBeacons.length;
        }
        results.add(finalResult);
      }

      setState(() {
        targetPoints = results;
        if (isTwoPoints) {
          resultDisplay = "TÌM THẤY 2 ĐIỂM";
          accuracyInfo = "Đang chạy Mock Điểm K1...";
          accuracyColor = Colors.orange;
        } else {
          bool isAccurate = finalResidual <= strictThreshold;
          resultDisplay = "${results[0].latitude.toStringAsFixed(7)}, ${results[0].longitude.toStringAsFixed(7)}";
          if (isAccurate) {
             accuracyInfo = "Tuyệt đối (±${(finalResidual*100).toStringAsFixed(1)}cm)";
             accuracyColor = Colors.green;
          } else {
             accuracyInfo = "CẢNH BÁO: Sai số ${(finalResidual).toStringAsFixed(2)}m!";
             accuracyColor = Colors.red;
          }
        }
      });
      if (results.isNotEmpty) _setMock(results[0].latitude, results[0].longitude, fromTarget: true, targetIndex: 0);
    } catch (e) { _showMsg("Lỗi: $e"); }
  }

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
            Text("1. Nhấn vào P(x): Lấy vị trí hoặc MOCK ngay."),
            Text("2. NHẤN GIỮ BẢN ĐỒ: Tự gán vào P trống và chạy MOCK."),
            Text("3. Nút Refresh: Di chuyển P theo 4 hướng cố định (Nhớ vị trí)."),
            Text("4. Dấu (+): Thêm P mới. Nếu P cũ có dữ liệu -> Tự tính P mới và Mock ngay."),
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

  void _assignResultToNextP() {
    if (targetPoints.isEmpty) return;
    LatLng pointToUse = targetPoints[isMockingTarget ? mockingTargetIndex : 0];
    int nextIndex = -1;
    for (int i = 0; i < beacons.length; i++) {
      if (beacons[i].location == null) { nextIndex = i; break; }
    }
    setState(() {
      if (nextIndex != -1) {
        beacons[nextIndex].location = pointToUse;
        _showMsg("Đã chuyển kết quả vào P${nextIndex + 1}");
      } else {
        beacons.add(Beacon(location: pointToUse, color: colorPalette[beacons.length % colorPalette.length]));
        nextIndex = beacons.length - 1;
        _showMsg("Đã tạo P${beacons.length} mới từ kết quả");
      }
    });
    _requestFocus(nextIndex); 
  }

  void _restartWithResultAsP1() {
    LatLng? newStart;
    if (isMockingTarget && targetPoints.isNotEmpty) { newStart = targetPoints[mockingTargetIndex]; } 
    else if (selectedIndex != null && selectedIndex! < beacons.length && beacons[selectedIndex!].location != null) { newStart = beacons[selectedIndex!].location; }
    else if (targetPoints.isNotEmpty) { newStart = targetPoints[0]; }

    if (newStart == null) { _showMsg("Chưa có tọa độ nào để gán!"); return; }
    _stopMock();
    setState(() {
      beacons = [Beacon(location: newStart, color: Colors.blue), Beacon(color: Colors.purple)];
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

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    String encodedData = jsonEncode(savedTargets.map((e) => e.toJson()).toList());
    await prefs.setString('saved_targets', encodedData);
  }
  
  Future<void> _saveUnit(String unit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_unit', unit);
    setState(() => selectedUnit = unit);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    String? encodedData = prefs.getString('saved_targets');
    if (encodedData != null) {
      Iterable l = jsonDecode(encodedData);
      setState(() { savedTargets = List<SavedTarget>.from(l.map((model) => SavedTarget.fromJson(model))); });
    }
    String? savedUnit = prefs.getString('selected_unit');
    if (savedUnit != null) { setState(() => selectedUnit = savedUnit); }
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

  @override
  Widget build(BuildContext context) {
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
                      Row(
                        children: ['ft', 'm', 'km', 'mi'].map((unit) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ChoiceChip(
                            label: Text(unit, style: const TextStyle(fontSize: 10)), 
                            selected: selectedUnit == unit, 
                            onSelected: (val) => _saveUnit(unit),
                          ),
                        )).toList(),
                      ),
                      IconButton(
                        icon: Icon(isSearchVisible ? Icons.search_off : Icons.search, color: Colors.blue),
                        onPressed: () => setState(() => isSearchVisible = !isSearchVisible),
                      ),
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
                              setState(() {
                                Beacon newBeacon = Beacon(color: colorPalette[beacons.length % colorPalette.length]);
                                beacons.add(newBeacon);
                                int newIndex = beacons.length - 1;

                                if (newIndex > 0) {
                                   Beacon prevBeacon = beacons[newIndex - 1];
                                   if (prevBeacon.location != null && prevBeacon.controller.text.isNotEmpty) {
                                       double? r = double.tryParse(prevBeacon.controller.text);
                                       if (r != null && r > 0) {
                                           double distMeters = (r * 1.0) * unitToMeter[selectedUnit]!;
                                           LatLng center = prevBeacon.location!;
                                           double bearing = _calculateOptimalBearing(center, newIndex);
                                           LatLng newPos = _calculatePointFromBearing(center, distMeters, bearing);
                                           newBeacon.location = newPos;
                                           selectedIndex = newIndex;
                                           targetPoints.clear();
                                           isMockingTarget = false;
                                           _setMock(newPos.latitude, newPos.longitude);
                                           _showMsg("Đã tạo P${newIndex + 1} và chạy Mock ngay!");
                                       }
                                   }
                                }
                                
                                _requestFocus(newIndex); 
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
                                style: const TextStyle(fontSize: 10), 
                                decoration: InputDecoration(hintText: selectedUnit, isDense: true)
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
                        // Sửa thành reset chỉ còn 1 điểm P1
                        setState(() { beacons = [Beacon(color: Colors.blue)]; targetPoints.clear(); searchMarker = null; resultDisplay = "0.000000, 0.000000"; accuracyInfo = "Chờ nhập liệu..."; accuracyColor = Colors.grey; });
                        _stopMock();
                      }),
                      if (targetPoints.isNotEmpty || selectedIndex != null) IconButton(icon: const Icon(Icons.looks_one, color: Colors.teal, size: 28), onPressed: _restartWithResultAsP1),
                      if (targetPoints.isNotEmpty) IconButton(icon: const Icon(Icons.playlist_add_check, color: Colors.green, size: 28), onPressed: _assignResultToNextP),
                      
                      // --- NÚT RESET VÀ NÚT SAVE ĐÃ ĐỔI CHỖ ---
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
                            beacons.add(Beacon(location: latlng, color: colorPalette[beacons.length % colorPalette.length]));
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
                        userAgentPackageName: 'com.heesay.trilateration.app',
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
                                radius: (double.tryParse(b.controller.text) ?? 0) * unitToMeter[selectedUnit]!,
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

  void _showTargetOptions(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(savedTargets[index].name),
        actions: [
          IconButton(icon: const Icon(Icons.play_circle_fill, color: Colors.green), onPressed: () { Navigator.pop(ctx); _assignSavedTargetToP(savedTargets[index].location); }),
          IconButton(icon: const Icon(Icons.directions, color: Colors.orange), onPressed: () { Navigator.pop(ctx); _openNavigation(savedTargets[index].location); }),
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
}