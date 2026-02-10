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
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';

// Biến toàn cục lưu Store Cache
late final CacheStore _mapCacheStore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. KHỞI TẠO CACHE STORE
  try {
    final dir = await getTemporaryDirectory();
    _mapCacheStore = FileCacheStore('${dir.path}/map_tiles');
  } catch (e) {
    print("Lỗi khởi tạo cache: $e");
    _mapCacheStore = MemCacheStore(); 
  }

  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MockApp()));
}

// --- MODELS ---
class Beacon {
  LatLng? location;
  final TextEditingController controller;
  Beacon({this.location, String dist = ""}) : controller = TextEditingController(text: dist);
}

class SavedTarget {
  LatLng location;
  String name;
  final DateTime timestamp;
  final String id;

  SavedTarget({
    required this.location, 
    required this.name, 
    required this.timestamp,
    String? id,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(100).toString();

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

  List<Beacon> beacons = [Beacon(), Beacon(), Beacon()];
  List<SavedTarget> savedTargets = [];
  
  // ft, m: Dùng công thức phẳng (Gần). km, mi: Dùng công thức cầu (Xa)
  String selectedUnit = 'm'; 
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0, 'mi': 1609.34};

  int? selectedIndex; 
  LatLng? targetPoint;
  LatLng? myRealLocation;
  LatLng? searchMarker; 
  String resultDisplay = "0.000000, 0.000000";
  String accuracyInfo = "Residual: --";
  bool isMockingTarget = false;
  bool isSearchVisible = false;

  static const double EARTH_RADIUS = 6371000.0;

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
    for (var b in beacons) b.controller.dispose();
    super.dispose();
  }

  // --- LOGIC MOCK GPS ---
  Future<void> _setMock(double lat, double lng, {bool fromTarget = false}) async {
    _mockTimer?.cancel();
    void pushMock() {
      try {
        platform.invokeMethod('setMockLocation', {"lat": lat, "lng": lng});
      } catch (e) { print("Lỗi Mock: $e"); }
    }
    pushMock();
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (timer) { pushMock(); });
    if (mounted) {
      setState(() {
        isMockingTarget = fromTarget;
        if (fromTarget) selectedIndex = null;
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

  // --- LOGIC: TỰ ĐỘNG TÍNH VỊ TRÍ P ---
  Future<void> _smartSetLocation(int index) async {
    if (selectedIndex == index) { _stopMock(); return; }
    try {
      LatLng newPos;
      bool shouldUseRandomLogic = index > 0 && beacons[index - 1].location != null && beacons[index - 1].controller.text.isNotEmpty;
      
      if (!shouldUseRandomLogic) {
        Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        newPos = LatLng(p.latitude, p.longitude);
        _showMsg("P${index + 1}: Đã lấy vị trí GPS thật");
      } else {
        LatLng prevLoc = beacons[index - 1].location!;
        double distValue = double.tryParse(beacons[index - 1].controller.text) ?? 0;
        double distMeters = distValue * unitToMeter[selectedUnit]!;
        newPos = _calculateRandomPoint(prevLoc, distMeters);
        _showMsg("P${index + 1}: Ngẫu nhiên cách P$index ${distValue}$selectedUnit");
      }
      setState(() {
        beacons[index].location = newPos;
        selectedIndex = index;
        isMockingTarget = false;
        if (!shouldUseRandomLogic) { myRealLocation = newPos; }
      });
      _mapController.move(newPos, 16);
      _setMock(newPos.latitude, newPos.longitude);
    } catch (e) { _showMsg("Lỗi: $e"); }
  }

  void _assignResultToNextP() {
    if (targetPoint == null) return;
    int nextIndex = -1;
    for (int i = 0; i < beacons.length; i++) {
      if (beacons[i].location == null) { nextIndex = i; break; }
    }
    setState(() {
      if (nextIndex != -1) {
        beacons[nextIndex].location = targetPoint;
        _showMsg("Đã chuyển kết quả vào P${nextIndex + 1}");
      } else {
        beacons.add(Beacon(location: targetPoint));
        _showMsg("Đã tạo P${beacons.length} mới từ kết quả");
      }
    });
  }

  void _restartWithResultAsP1() {
    if (targetPoint == null) return;
    LatLng newStart = targetPoint!;
    _mockTimer?.cancel();
    setState(() {
      beacons = [Beacon(location: newStart), Beacon(), Beacon()];
      targetPoint = null;
      resultDisplay = "0.000000, 0.000000";
      accuracyInfo = "Residual: --";
      searchMarker = null;
      selectedIndex = 0; 
      isMockingTarget = false;
    });
    _mapController.move(newStart, 16);
    _setMock(newStart.latitude, newStart.longitude);
    _showMsg("Đã lấy kết quả làm gốc P1!");
  }

  LatLng _calculateRandomPoint(LatLng start, double distanceMeters) {
    Random random = Random();
    double bearing = random.nextDouble() * 2 * pi; 
    double startLat = start.latitude * (pi / 180);
    double startLng = start.longitude * (pi / 180);
    double distRatio = distanceMeters / EARTH_RADIUS;
    double endLat = asin(sin(startLat) * cos(distRatio) + cos(startLat) * sin(distRatio) * cos(bearing));
    double endLng = startLng + atan2(sin(bearing) * sin(distRatio) * cos(startLat), cos(distRatio) - sin(startLat) * sin(endLat));
    return LatLng(endLat * (180 / pi), endLng * (180 / pi));
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
    if (savedUnit != null) {
      setState(() => selectedUnit = savedUnit);
    }
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

  // ==========================================================
  //      PHẦN TOÁN HỌC: XỬ LÝ SONG SONG (NGẮN & XA)
  // ==========================================================

  double _toRadians(double degree) => degree * pi / 180.0;
  double _toDegrees(double radian) => radian * 180.0 / pi;

  // --- CÔNG THỨC 1: HỆ PHẲNG (CHO m/ft) ---
  Point<double> _latLngToXy(LatLng origin, LatLng p) {
    double latAvg = _toRadians((origin.latitude + p.latitude) / 2);
    // Hằng số trắc địa gần đúng cho khoảng cách ngắn
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

  // --- CÔNG THỨC 2: HỆ CẦU (CHO km/mi) ---
  double _haversineDistance(LatLng p1, LatLng p2) {
    double dLat = _toRadians(p2.latitude - p1.latitude);
    double dLon = _toRadians(p2.longitude - p1.longitude);
    double lat1 = _toRadians(p1.latitude);
    double lat2 = _toRadians(p2.latitude);
    double a = pow(sin(dLat / 2), 2) + pow(sin(dLon / 2), 2) * cos(lat1) * cos(lat2);
    double c = 2 * asin(sqrt(a));
    return EARTH_RADIUS * c;
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
    double distRatio = distance / EARTH_RADIUS;
    double headingRad = _toRadians(heading);
    double fromLat = _toRadians(from.latitude);
    double fromLng = _toRadians(from.longitude);
    double toLat = asin(sin(fromLat) * cos(distRatio) + cos(fromLat) * sin(distRatio) * cos(headingRad));
    double toLng = fromLng + atan2(sin(headingRad) * sin(distRatio) * cos(fromLat), cos(distRatio) - sin(fromLat) * sin(toLat));
    return LatLng(_toDegrees(toLat), _toDegrees(toLng));
  }

  // --- HÀM TÍNH TOÁN CHÍNH (THÔNG MINH) ---
  void _calculateTrilateration() {
    FocusScope.of(context).unfocus();
    var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
    if (validBeacons.length < 3) { _showMsg("Cần ít nhất 3 điểm!"); return; }

    try {
      LatLng finalResult;
      double finalResidual;
      
      // KIỂM TRA ĐƠN VỊ ĐỂ CHỌN CHIẾN THUẬT
      bool isShortRange = (selectedUnit == 'm' || selectedUnit == 'ft');

      if (isShortRange) {
        // --- CHIẾN THUẬT 1: PHẲNG HÓA (Siêu chính xác cho ft/m) ---
        LatLng origin = validBeacons[0].location!;
        List<Point<double>> points = [];
        List<double> radii = [];

        // Chuyển sang hệ mét phẳng (XY)
        for (var b in validBeacons) {
          points.add(_latLngToXy(origin, b.location!));
          radii.add(double.parse(b.controller.text) * unitToMeter[selectedUnit]!);
        }

        // Ước lượng ban đầu (Trung tâm)
        double estX = 0, estY = 0;
        for (var p in points) { estX += p.x; estY += p.y; }
        estX /= points.length;
        estY /= points.length;

        // Vòng lặp tối ưu hóa Levenberg-Marquardt (5000 lần)
        double learningRate = 0.2;
        for (int i = 0; i < 5000; i++) {
          double shiftX = 0, shiftY = 0;
          for (int j = 0; j < points.length; j++) {
            double dx = estX - points[j].x;
            double dy = estY - points[j].y;
            double currentDist = sqrt(dx*dx + dy*dy);
            if (currentDist == 0) currentDist = 0.000001;
            
            double error = currentDist - radii[j];
            double uX = dx / currentDist;
            double uY = dy / currentDist;
            
            shiftX += -error * uX;
            shiftY += -error * uY;
          }
          estX += shiftX * learningRate / points.length;
          estY += shiftY * learningRate / points.length;
          
          if (shiftX.abs() < 1e-10 && shiftY.abs() < 1e-10) break;
          learningRate *= 0.995;
        }

        finalResult = _xyToLatLng(origin, estX, estY);
        
        // Tính sai số dư (Residual) theo công thức phẳng
        double totalRes = 0;
        for (int i = 0; i < points.length; i++) {
           double dist = sqrt(pow(estX - points[i].x, 2) + pow(estY - points[i].y, 2));
           totalRes += (dist - radii[i]).abs();
        }
        finalResidual = totalRes / points.length;

      } else {
        // --- CHIẾN THUẬT 2: HÌNH CẦU (Cho km/mi - Bù độ cong trái đất) ---
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
            moveLat += moveDist * cos(rad);
            moveLng += moveDist * sin(rad);
          }
          double avgMoveLat = moveLat / validBeacons.length;
          double avgMoveLng = moveLng / validBeacons.length;
          double totalMoveMeters = sqrt(avgMoveLat*avgMoveLat + avgMoveLng*avgMoveLng);
          double moveBearing = _toDegrees(atan2(avgMoveLng, avgMoveLat));

          if (totalMoveMeters > 0.0001) {
             currentEst = _computeOffset(currentEst, totalMoveMeters, moveBearing);
          } else { break; }
          learningRate *= 0.99;
        }
        finalResult = currentEst;
        
        // Tính sai số dư theo công thức cầu
        double totalRes = 0;
        for (var b in validBeacons) {
          double realDist = _haversineDistance(finalResult, b.location!);
          double targetDist = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
          totalRes += (realDist - targetDist).abs();
        }
        finalResidual = totalRes / validBeacons.length;
      }

      // HIỂN THỊ KẾT QUẢ
      setState(() {
        targetPoint = finalResult;
        resultDisplay = "${finalResult.latitude.toStringAsFixed(7)}, ${finalResult.longitude.toStringAsFixed(7)}";
        
        String unitName = isShortRange ? "m" : "m (Cầu)";
        if (finalResidual < 0.1) {
          accuracyInfo = "Tuyệt đối (±${(finalResidual*100).toStringAsFixed(1)}cm)";
        } else {
          accuracyInfo = "Sai lệch: ±${finalResidual.toStringAsFixed(2)}$unitName";
        }
      });
      _mapController.move(finalResult, 17); // Zoom sát để xem

    } catch (e) { _showMsg("Lỗi: $e"); }
  }

  void _saveCurrentTarget() {
    if (targetPoint == null) return;
    TextEditingController nameCtrl = TextEditingController(text: "Mục tiêu ${savedTargets.length + 1}");
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Lưu điểm mục tiêu"),
        content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Tên điểm")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
          ElevatedButton(onPressed: () {
            setState(() => savedTargets.add(SavedTarget(location: targetPoint!, name: nameCtrl.text, timestamp: DateTime.now())));
            _saveData();
            Navigator.pop(ctx);
            _showMsg("Đã lưu!");
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
          ElevatedButton(onPressed: () {
            setState(() => savedTargets[index].name = editCtrl.text);
            _saveData();
            Navigator.pop(ctx);
          }, child: const Text("OK")),
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
            setState(() => savedTargets.removeAt(index)); 
            _saveData();
            Navigator.pop(ctx); 
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("1. Nhấn vào ô P1: Lấy vị trí GPS thật."),
              Text("2. Nhập khoảng cách P1 -> Nhấn P2: Tạo điểm ngẫu nhiên."),
              Text("3. Chọn đơn vị ft/m cho khoảng cách gần (chính xác cao)."),
              Text("4. Chọn đơn vị km/mi cho khoảng cách xa (bù độ cong trái đất)."),
              Text("5. Bấm TÍNH để tìm giao điểm."),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 70,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: beacons.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == beacons.length) {
                          return IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 35), onPressed: () => setState(() => beacons.add(Beacon())));
                        }
                        return Container(
                          width: 80, 
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () => _smartSetLocation(i),
                                child: Container(
                                  width: double.infinity,
                                  alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: selectedIndex == i ? Colors.red : (beacons[i].location != null ? Colors.green : Colors.grey.shade400),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text("P${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                              TextField(controller: beacons[i].controller, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10), decoration: InputDecoration(hintText: selectedUnit, isDense: true)),
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
                        Text(resultDisplay, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red)),
                        Text(accuracyInfo, style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const Divider(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () {
                        setState(() { beacons = [Beacon(), Beacon(), Beacon()]; targetPoint = null; searchMarker = null; resultDisplay = "0.000000, 0.000000"; accuracyInfo = "Residual: --"; });
                        _stopMock();
                      }),
                      
                      if (targetPoint != null)
                         Tooltip(
                           message: "Lấy kết quả làm P1 (Reset)",
                           child: IconButton(
                             icon: const Icon(Icons.looks_one, color: Colors.teal, size: 28),
                             onPressed: _restartWithResultAsP1,
                           ),
                         ),

                      if (targetPoint != null)
                         Tooltip(
                           message: "Gán vào P trống tiếp theo",
                           child: IconButton(
                             icon: const Icon(Icons.playlist_add_check, color: Colors.green, size: 28),
                             onPressed: _assignResultToNextP,
                           ),
                         ),

                      if (targetPoint != null)
                        IconButton(icon: const Icon(Icons.save, color: Colors.blue), onPressed: _saveCurrentTarget),
                      
                      IconButton(
                        onPressed: (targetPoint == null && selectedIndex == null) ? null : (isAnyMocking ? _stopMock : () { if (targetPoint != null) _setMock(targetPoint!.latitude, targetPoint!.longitude, fromTarget: true); }),
                        icon: Icon(isAnyMocking ? Icons.stop_circle : Icons.play_circle, color: isAnyMocking ? Colors.red : Colors.green, size: 32),
                      ),
                      
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
                      minZoom: 4.0, 
                      maxZoom: 18.0, 
                      onTap: (_, latlng) {
                        if (selectedIndex != null && !isMockingTarget) {
                          setState(() { beacons[selectedIndex!].location = latlng; });
                          _setMock(latlng.latitude, latlng.longitude);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.mockapp_fix',
                        tileProvider: CachedTileProvider(
                          store: _mapCacheStore,
                        ),
                      ),
                      MarkerLayer(
                        markers: [
                          if (myRealLocation != null) Marker(point: myRealLocation!, width: 20, height: 20, child: const CircleAvatar(backgroundColor: Colors.blue, radius: 4)),
                          if (searchMarker != null) Marker(point: searchMarker!, width: 35, height: 35, child: const Icon(Icons.location_on, color: Colors.red, size: 35)),
                          for (int i = 0; i < beacons.length; i++)
                            if (beacons[i].location != null)
                              Marker(point: beacons[i].location!, width: 30, height: 30, child: Container(decoration: BoxDecoration(color: selectedIndex == i ? Colors.red : Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text("${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))))),
                          if (targetPoint != null) Marker(point: targetPoint!, width: 25, height: 25, child: const Icon(Icons.location_searching, color: Colors.orange, size: 25)),
                          for (int i = 0; i < savedTargets.length; i++)
                            Marker(
                              point: savedTargets[i].location,
                              width: 70, height: 60,
                              child: GestureDetector(
                                onTap: () => _showTargetOptions(i),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bookmark, color: Colors.purple, size: 20),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(3)),
                                      child: Text(savedTargets[i].name, style: const TextStyle(color: Colors.white, fontSize: 8), overflow: TextOverflow.ellipsis),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (isSearchVisible)
                    Positioned(
                      top: 10, left: 15, right: 15,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)]),
                        child: TextField(
                          controller: _searchCtrl, 
                          autofocus: true, 
                          decoration: InputDecoration(hintText: "Tìm kiếm...", border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), prefixIcon: const Icon(Icons.search, color: Colors.blue), suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => isSearchVisible = false))),
                          onSubmitted: (_) => _searchLocation(),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 15, bottom: 15,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (savedTargets.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FloatingActionButton(heroTag: "listBtn", mini: true, backgroundColor: Colors.purple, onPressed: _showSavedTargetsSheet, child: const Icon(Icons.list, color: Colors.white)),
                          ),
                        FloatingActionButton(
                          heroTag: "locBtn", mini: true, backgroundColor: Colors.white,
                          onPressed: () async {
                            Position p = await Geolocator.getCurrentPosition();
                            _mapController.move(LatLng(p.latitude, p.longitude), 15);
                          }, child: const Icon(Icons.my_location, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTargetOptions(int index) {
    String coords = "${savedTargets[index].location.latitude.toStringAsFixed(6)}, ${savedTargets[index].location.longitude.toStringAsFixed(6)}";
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(savedTargets[index].name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Tọa độ:", style: TextStyle(fontSize: 12, color: Colors.grey)),
            GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: coords));
                _showMsg("Đã copy!");
              },
              child: Text(coords, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.red)),
            ),
          ],
        ),
        actions: [
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              const Text("MỤC TIÊU ĐÃ LƯU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: savedTargets.length,
                  itemBuilder: (c, i) => ListTile(
                    key: ValueKey(savedTargets[i].id),
                    leading: const Icon(Icons.location_on, color: Colors.purple),
                    title: Text(savedTargets[i].name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("${savedTargets[i].location.latitude.toStringAsFixed(6)}, ${savedTargets[i].location.longitude.toStringAsFixed(6)}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDeleteTarget(i, onDeleted: () => setSheetState(() {})),
                    ),
                    onTap: () { _mapController.move(savedTargets[i].location, 15); Navigator.pop(ctx); },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}   //////// công thức chuẩn gần với mặt phẳng và xa với hình cầu