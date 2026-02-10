import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MockApp()));

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

class MockApp extends StatefulWidget {
  const MockApp({super.key});
  @override
  State<MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<MockApp> {
  static const platform = MethodChannel('com.example.mock/gps');
  final MapController _mapController = MapController();
  final TextEditingController _searchCtrl = TextEditingController();
  
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

  static const double WGS84_A = 6378137.0;
  static const double WGS84_B = 6356752.314245;
  static const double E2 = (WGS84_A * WGS84_A - WGS84_B * WGS84_B) / (WGS84_A * WGS84_A);

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadData();
  }

  // --- LOGIC: TỰ ĐỘNG TÍNH VỊ TRÍ (THỰC TẾ HOẶC NGẪU NHIÊN) ---
  Future<void> _smartSetLocation(int index) async {
    if (selectedIndex == index) {
      _stopMock();
      return;
    }

    try {
      LatLng newPos;
      
      bool shouldUseRandomLogic = index > 0 && 
                                  beacons[index - 1].location != null && 
                                  beacons[index - 1].controller.text.isNotEmpty;

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
        if (!shouldUseRandomLogic) {
          myRealLocation = newPos;
        }
      });

      _mapController.move(newPos, 16);
      _setMock(newPos.latitude, newPos.longitude);

    } catch (e) {
      _showMsg("Lỗi: $e");
    }
  }

  // --- LOGIC: GÁN KẾT QUẢ VÀO P TIẾP THEO ---
  void _assignResultToNextP() {
    if (targetPoint == null) return;
    int nextIndex = -1;
    for (int i = 0; i < beacons.length; i++) {
      if (beacons[i].location == null) {
        nextIndex = i;
        break;
      }
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

  // --- LOGIC MỚI: RESET VÀ GÁN KẾT QUẢ VÀO P1 ---
  void _restartWithResultAsP1() {
    if (targetPoint == null) return;
    LatLng newStart = targetPoint!;
    
    setState(() {
      // 1. Tạo danh sách mới, P1 là kết quả vừa tính, P2, P3 trống
      beacons = [
        Beacon(location: newStart), 
        Beacon(), 
        Beacon()
      ];
      
      // 2. Xóa kết quả tính toán cũ để bắt đầu phiên mới
      targetPoint = null;
      resultDisplay = "0.000000, 0.000000";
      accuracyInfo = "Residual: --";
      searchMarker = null;
      selectedIndex = 0; // Chọn P1 luôn để người dùng biết đang ở đâu
      isMockingTarget = false;
    });

    // 3. Di chuyển map về P1 mới và Mock GPS tại đó
    _mapController.move(newStart, 16);
    _setMock(newStart.latitude, newStart.longitude);
    _showMsg("Đã lấy kết quả làm gốc P1. Sẵn sàng đo tiếp!");
  }

  LatLng _calculateRandomPoint(LatLng start, double distanceMeters) {
    const double earthRadius = 6371000;
    Random random = Random();
    double bearing = random.nextDouble() * 2 * pi; 
    
    double startLat = start.latitude * (pi / 180);
    double startLng = start.longitude * (pi / 180);
    double distRatio = distanceMeters / earthRadius;

    double endLat = asin(sin(startLat) * cos(distRatio) + 
                    cos(startLat) * sin(distRatio) * cos(bearing));
    
    double endLng = startLng + atan2(sin(bearing) * sin(distRatio) * cos(startLat), 
                    cos(distRatio) - sin(startLat) * sin(endLat));

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

  List<double> _latLngToECEF(LatLng loc) {
    double lat = loc.latitude * pi / 180;
    double lon = loc.longitude * pi / 180;
    double N = WGS84_A / sqrt(1 - E2 * pow(sin(lat), 2));
    return [N * cos(lat) * cos(lon), N * cos(lat) * sin(lon), (N * (1 - E2)) * sin(lat)];
  }

  LatLng _ecefToLatLng(double x, double y, double z) {
    double lon = atan2(y, x);
    double p = sqrt(x * x + y * y);
    double lat = atan2(z, p * (1 - E2));
    for (int i = 0; i < 5; i++) {
      double N = WGS84_A / sqrt(1 - E2 * pow(sin(lat), 2));
      lat = atan2(z + E2 * N * sin(lat), p);
    }
    return LatLng(lat * 180 / pi, lon * 180 / pi);
  }

  void _calculateTrilateration() {
    FocusScope.of(context).unfocus();
    var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
    if (validBeacons.length < 3) { _showMsg("Cần ít nhất 3 điểm!"); return; }
    try {
      List<double> est = [0, 0, 0];
      for (var b in validBeacons) {
        var p = _latLngToECEF(b.location!);
        est[0] += p[0]; est[1] += p[1]; est[2] += p[2];
      }
      est = est.map((e) => e / validBeacons.length).toList();
      for (int iter = 0; iter < 40; iter++) {
        double dx = 0, dy = 0, dz = 0;
        for (var b in validBeacons) {
          var p = _latLngToECEF(b.location!);
          double r_measured = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
          double vx = est[0] - p[0]; double vy = est[1] - p[1]; double vz = est[2] - p[2];
          double dist = sqrt(vx * vx + vy * vy + vz * vz);
          if (dist < 0.1) continue;
          double error = dist - r_measured;
          dx += error * (vx / dist); dy += error * (vy / dist); dz += error * (vz / dist);
        }
        est[0] -= (dx / validBeacons.length) * 0.2;
        est[1] -= (dy / validBeacons.length) * 0.2;
        est[2] -= (dz / validBeacons.length) * 0.2;
      }
      LatLng finalRes = _ecefToLatLng(est[0], est[1], est[2]);
      double residual = _calculateResidual(finalRes, validBeacons);
      setState(() {
        targetPoint = finalRes;
        resultDisplay = "${finalRes.latitude.toStringAsFixed(6)}, ${finalRes.longitude.toStringAsFixed(6)}";
        accuracyInfo = "Sai số TB: ±${residual.toStringAsFixed(1)}m";
      });
      _mapController.move(finalRes, 15);
    } catch (e) { _showMsg("Lỗi: $e"); }
  }

  double _calculateResidual(LatLng target, List<Beacon> validOnes) {
    double sumSq = 0;
    for (var b in validOnes) {
      double d = Geolocator.distanceBetween(target.latitude, target.longitude, b.location!.latitude, b.location!.longitude);
      double r = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
      sumSq += pow(d - r, 2).toDouble();
    }
    return sqrt(sumSq / validOnes.length);
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

  Future<void> _setMock(double lat, double lng, {bool fromTarget = false}) async {
    try {
      await platform.invokeMethod('setMockLocation', {"lat": lat, "lng": lng});
      setState(() { isMockingTarget = fromTarget; if (fromTarget) selectedIndex = null; });
    } catch (e) { print(e); }
  }

  Future<void> _stopMock() async {
    try { 
      await platform.invokeMethod('stopMockLocation'); 
      setState(() { isMockingTarget = false; selectedIndex = null; }); 
    } catch (e) { print(e); }
  }

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
              Text("1. Nhấn nút GPS (bên cạnh P): Lấy vị trí thật."),
              Text("2. Nhấn P: Nếu P trước đó có dữ liệu -> Tạo điểm ngẫu nhiên."),
              Text("3. Nút Play xanh: Chuyển vị trí ảo đến P hoặc Mục tiêu."),
              Text("4. Nút Số 1 (Teal): Lấy kết quả làm P1 và tính toán lại từ đầu."),
              Text("5. Nút List (+): Chỉ gán kết quả vào P trống kế tiếp (giữ nguyên các P cũ)."),
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
                          width: 100, margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => _smartSetLocation(i),
                                      child: Container(
                                        alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 4),
                                        decoration: BoxDecoration(
                                          color: selectedIndex == i ? Colors.red : (beacons[i].location != null ? Colors.green : Colors.grey.shade400),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text("P${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                        Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
                                        setState(() {
                                          beacons[i].location = LatLng(p.latitude, p.longitude);
                                          _showMsg("Gán GPS thật vào P${i+1}");
                                        });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(Icons.my_location, size: 20, color: Colors.blue),
                                    ),
                                  ),
                                ],
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
                      
                      // NÚT MỚI: RESET & GÁN VÀO P1
                      if (targetPoint != null)
                         Tooltip(
                           message: "Bắt đầu lại với kết quả là P1",
                           child: IconButton(
                             icon: const Icon(Icons.looks_one, color: Colors.teal, size: 28),
                             onPressed: _restartWithResultAsP1,
                           ),
                         ),

                      // NÚT CŨ: GÁN VÀO P TIẾP THEO
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