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

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MockApp()));

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

  // Bán kính Trái Đất trung bình (cho Haversine)
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

  // --- LOGIC: TỰ ĐỘNG TÍNH VỊ TRÍ ---
  Future<void> _smartSetLocation(int index) async {
    if (selectedIndex == index) { _stopMock(); return; }
    try {
      LatLng newPos;
      bool shouldUseRandomLogic = index > 0 && beacons[index - 1].location != null && beacons[index - 1].controller.text.isNotEmpty;
      if (!shouldUseRandomLogic) {
        Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        newPos = LatLng(p.latitude, p.longitude);
        _showMsg("P${index + 1}: Đã lấy vị trí hiện tại");
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

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    String? encodedData = prefs.getString('saved_targets');
    if (encodedData != null) {
      Iterable l = jsonDecode(encodedData);
      setState(() { savedTargets = List<SavedTarget>.from(l.map((model) => SavedTarget.fromJson(model))); });
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

  // --- CÔNG THỨC HAVERSINE VÀ TOÁN HỌC ---
  
  // 1. Chuyển đổi độ sang radian
  double _toRadians(double degree) => degree * pi / 180.0;
  // 2. Chuyển đổi radian sang độ
  double _toDegrees(double radian) => radian * 180.0 / pi;

  // 3. Tính khoảng cách Haversine giữa 2 điểm (trả về mét)
  double _haversineDistance(LatLng p1, LatLng p2) {
    double dLat = _toRadians(p2.latitude - p1.latitude);
    double dLon = _toRadians(p2.longitude - p1.longitude);
    double lat1 = _toRadians(p1.latitude);
    double lat2 = _toRadians(p2.latitude);

    double a = pow(sin(dLat / 2), 2) + pow(sin(dLon / 2), 2) * cos(lat1) * cos(lat2);
    double c = 2 * asin(sqrt(a));
    return EARTH_RADIUS * c;
  }

  // 4. Tính góc phương vị (Bearing) giữa 2 điểm
  double _calculateBearing(LatLng start, LatLng end) {
    double startLat = _toRadians(start.latitude);
    double startLng = _toRadians(start.longitude);
    double endLat = _toRadians(end.latitude);
    double endLng = _toRadians(end.longitude);
    double dLng = endLng - startLng;

    double y = sin(dLng) * cos(endLat);
    double x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(dLng);
    double bearing = atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360; // Chuẩn hóa 0-360 độ
  }

  // 5. Tính điểm mới từ điểm bắt đầu, khoảng cách và góc phương vị
  LatLng _computeOffset(LatLng from, double distance, double heading) {
    double distRatio = distance / EARTH_RADIUS;
    double headingRad = _toRadians(heading);
    double fromLat = _toRadians(from.latitude);
    double fromLng = _toRadians(from.longitude);

    double toLat = asin(sin(fromLat) * cos(distRatio) + cos(fromLat) * sin(distRatio) * cos(headingRad));
    double toLng = fromLng + atan2(sin(headingRad) * sin(distRatio) * cos(fromLat), cos(distRatio) - sin(fromLat) * sin(toLat));
    return LatLng(_toDegrees(toLat), _toDegrees(toLng));
  }

  // --- THUẬT TOÁN TỐI ƯU HÓA DỰA TRÊN HAVERSINE ---
  void _calculateTrilateration() {
    FocusScope.of(context).unfocus();
    var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
    if (validBeacons.length < 3) { _showMsg("Cần ít nhất 3 điểm!"); return; }

    try {
      // B1: Điểm khởi đầu (Trung bình cộng)
      double sumLat = 0, sumLng = 0;
      for (var b in validBeacons) {
        sumLat += b.location!.latitude;
        sumLng += b.location!.longitude;
      }
      LatLng currentEst = LatLng(sumLat / validBeacons.length, sumLng / validBeacons.length);

      // B2: Vòng lặp tối ưu hóa (Gradient Descent trên mặt cầu)
      double learningRate = 0.5; // Tốc độ học ban đầu
      
      for (int i = 0; i < 500; i++) { // Lặp 500 lần cho chính xác
        double latShift = 0;
        double lngShift = 0;
        
        for (var b in validBeacons) {
          // Tính khoảng cách Haversine từ điểm ước lượng đến P
          double estimatedDist = _haversineDistance(currentEst, b.location!);
          
          // Khoảng cách người dùng nhập (R)
          double inputDist = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
          
          // Sai số (Error): Nếu estimated > input (xa quá) -> Error dương -> Cần kéo lại gần
          double error = estimatedDist - inputDist;

          // Tính hướng từ ước lượng đến P
          double bearingToP = _calculateBearing(currentEst, b.location!);

          // Di chuyển điểm ước lượng về phía P (hoặc ra xa P)
          // Ta cần tính vector di chuyển. Vì đây là Lat/Lng, ta dùng xấp xỉ nhỏ.
          
          // Tính thành phần dịch chuyển (Vector addition)
          // Di chuyển một đoạn = error * learningRate về hướng bearingToP
          double moveDist = error * learningRate;
          
          // Để đơn giản hóa trong vòng lặp gradient, ta cộng dồn vector
          // (Lưu ý: đây là vector lực, không phải tọa độ chính xác, nhưng đủ tốt để hội tụ)
          latShift += moveDist * cos(_toRadians(bearingToP));
          lngShift += moveDist * sin(_toRadians(bearingToP));
        }

        // Trung bình hóa vector dịch chuyển
        double avgMoveLat = latShift / validBeacons.length;
        double avgMoveLng = lngShift / validBeacons.length;
        
        // Cập nhật vị trí mới bằng cách di chuyển điểm cũ
        // Tổng hợp lực di chuyển
        double totalMoveDist = sqrt(avgMoveLat*avgMoveLat + avgMoveLng*avgMoveLng);
        double moveBearing = _toDegrees(atan2(avgMoveLng, avgMoveLat));

        if (totalMoveDist > 0.0001) { // Chỉ di chuyển nếu lực đủ lớn
           currentEst = _computeOffset(currentEst, totalMoveDist, moveBearing);
        }

        learningRate *= 0.99; // Giảm dần tốc độ học
      }

      double finalResidual = _calculateResidual(currentEst, validBeacons);
      setState(() {
        targetPoint = currentEst;
        resultDisplay = "${currentEst.latitude.toStringAsFixed(6)}, ${currentEst.longitude.toStringAsFixed(6)}";
        accuracyInfo = "Sai số (Haversine): ±${finalResidual.toStringAsFixed(2)}m";
      });
      _mapController.move(currentEst, 16);

    } catch (e) { _showMsg("Lỗi: $e"); }
  }

  double _calculateResidual(LatLng target, List<Beacon> validOnes) {
    double totalDiff = 0;
    for (var b in validOnes) {
      double realDist = _haversineDistance(target, b.location!); // Dùng Haversine kiểm tra lại
      double inputDist = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
      totalDiff += (realDist - inputDist).abs();
    }
    return totalDiff / validOnes.length;
  }
  // ---------------------------------------------------

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
              Text("1. Nhấn vào ô P1: Lấy vị trí thật (GPS)."),
              Text("2. Nhập khoảng cách P1 và Nhấn P2: Tạo điểm ngẫu nhiên cách P1."),
              Text("3. Nút Play xanh: Bắt đầu Mock GPS."),
              Text("4. Nút Số 1 (Teal): Lấy kết quả làm P1 và reset."),
              Text("5. Nút List (+): Gán kết quả vào P tiếp theo."),
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
                  // --- TOP BAR ---
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
                            onSelected: (val) => setState(() => selectedUnit = unit)
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
                  // --- BEACONS LIST (ĐÃ XÓA NÚT GPS) ---
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
                  // --- INFO DISPLAY ---
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
                  // --- CONTROL BUTTONS ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () {
                        setState(() { beacons = [Beacon(), Beacon(), Beacon()]; targetPoint = null; searchMarker = null; resultDisplay = "0.000000, 0.000000"; accuracyInfo = "Residual: --"; });
                        _stopMock();
                      }),
                      
                      if (targetPoint != null)
                         Tooltip(
                           message: "Bắt đầu lại với kết quả là P1",
                           child: IconButton(
                             icon: const Icon(Icons.looks_one, color: Colors.teal, size: 28),
                             onPressed: _restartWithResultAsP1,
                           ),
                         ),

                      if (targetPoint != null)
                         Tooltip(
                           message: "Gán kết quả vào P trống tiếp theo",
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
            
            // --- MAP ---
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
                          setState(() { beacons[selectedIndex!].location = latlng; });
                          _setMock(latlng.latitude, latlng.longitude);
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.mockapp_fix', 
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
            const Text("Tọa độ (Nhấn giữ để copy):", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 5),
            GestureDetector(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: coords));
                _showMsg("Đã copy tọa độ!");
              },
              child: Text(
                coords,
                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.red),
              ),
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
}