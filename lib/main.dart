import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MockApp()));

// Class quản lý từng điểm mốc (Beacon)
class Beacon {
  LatLng? location;
  final TextEditingController controller;
  Beacon({this.location, String dist = ""}) : controller = TextEditingController(text: dist);
}

class MockApp extends StatefulWidget {
  const MockApp({super.key});
  @override
  State<MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<MockApp> {
  static const platform = MethodChannel('com.example.mock/gps');
  final MapController _mapController = MapController();
  
  // 1. GIỮ NGUYÊN DANH SÁCH ĐIỂM (Khởi tạo sẵn 3 điểm như cũ nhưng cho phép thêm)
  List<Beacon> beacons = [Beacon(), Beacon(), Beacon()];
  
  String selectedUnit = 'm'; 
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0, 'mi': 1609.34};

  int? selectedIndex; 
  LatLng? targetPoint;
  LatLng? myRealLocation;
  String resultDisplay = "0.000000, 0.000000";
  String accuracyInfo = "Residual: --";
  bool isMockingTarget = false;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  // --- ENGINE ĐỊNH VỊ TỐI ƯU HÓA (NON-LINEAR LEAST SQUARES) ---

  void _calculateTrilateration() {
    FocusScope.of(context).unfocus();
    
    // Lấy các điểm đã nhập đủ dữ liệu
    var validBeacons = beacons.where((b) => b.location != null && b.controller.text.isNotEmpty).toList();
    
    if (validBeacons.length < 3) {
      _showMsg("Cần ít nhất 3 điểm (P1, P2, P3...) để tính toán!");
      return;
    }

    try {
      // 1. Điểm đoán ban đầu (Trọng tâm các beacon)
      double avgLat = validBeacons.map((e) => e.location!.latitude).reduce((a, b) => a + b) / validBeacons.length;
      double avgLng = validBeacons.map((e) => e.location!.longitude).reduce((a, b) => a + b) / validBeacons.length;
      LatLng estimate = LatLng(avgLat, avgLng);

      // 2. Thuật toán Gauss-Newton (Lặp để giảm sai số bình phương)
      for (int iteration = 0; iteration < 50; iteration++) {
        double dLat = 0, dLng = 0;
        double totalWeight = 0;

        for (var b in validBeacons) {
          double r_measured = double.parse(b.controller.text) * unitToMeter[selectedUnit]!;
          double r_calc = Geolocator.distanceBetween(estimate.latitude, estimate.longitude, b.location!.latitude, b.location!.longitude);
          
          if (r_calc < 0.1) continue; 

          double error = r_measured - r_calc;
          // Gradient hướng tới beacon
          double latStep = (estimate.latitude - b.location!.latitude) / r_calc;
          double lngStep = (estimate.longitude - b.location!.longitude) / r_calc;

          dLat += error * latStep;
          dLng += error * lngStep;
          totalWeight += 1.0;
        }

        // Cập nhật vị trí (Learning rate 0.1 để mượt mà)
        estimate = LatLng(
          estimate.latitude + (dLat / totalWeight) * 0.1,
          estimate.longitude + (dLng / totalWeight) * 0.1
        );
      }

      // 3. Tính Residual (Độ tin cậy)
      double residual = _calculateResidual(estimate, validBeacons);

      setState(() {
        targetPoint = estimate;
        resultDisplay = "${estimate.latitude.toStringAsFixed(6)}, ${estimate.longitude.toStringAsFixed(6)}";
        accuracyInfo = "Sai số TB: ±${residual.toStringAsFixed(1)}m";
      });
      _mapController.move(estimate, 15);
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

  // --- GIAO DIỆN & MOCK GPS (GIỮ NGUYÊN 100%) ---

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.redAccent));

  Future<void> _requestPermission() async {
    var status = await [Permission.location].request();
    if (status[Permission.location]!.isGranted) {
      Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .listen((p) { if (mounted) setState(() => myRealLocation = LatLng(p.latitude, p.longitude)); });
    }
  }

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

  @override
  Widget build(BuildContext context) {
    bool isAnyMocking = isMockingTarget || selectedIndex != null;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            // PANEL ĐIỀU KHIỂN (Full tính năng cũ + Nút Add)
            Container(
              padding: const EdgeInsets.all(8), color: Colors.white,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['ft', 'm', 'km', 'mi'].map((unit) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(label: Text(unit), selected: selectedUnit == unit, onSelected: (val) => setState(() => selectedUnit = unit)),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  // DANH SÁCH ĐIỂM NGANG (Có thể cuộn nếu nhiều điểm)
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
                          width: 70,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (selectedIndex == i) { _stopMock(); } 
                                  else {
                                    setState(() { selectedIndex = i; isMockingTarget = false; });
                                    if (beacons[i].location != null) { 
                                      _mapController.move(beacons[i].location!, 14); 
                                      _setMock(beacons[i].location!.latitude, beacons[i].location!.longitude); 
                                    }
                                  }
                                },
                                child: Container(
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
                  // THANH CÔNG CỤ (Copy, Gán, Tính toán)
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () {
                        setState(() { beacons = [Beacon(), Beacon(), Beacon()]; targetPoint = null; resultDisplay = "0.000000, 0.000000"; accuracyInfo = "Residual: --"; });
                        _stopMock();
                      }),
                      Expanded(
                        child: GestureDetector(
                          onLongPress: () { Clipboard.setData(ClipboardData(text: resultDisplay)); _showMsg("Đã copy tọa độ!"); },
                          child: Column(
                            children: [
                              Text(resultDisplay, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(accuracyInfo, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                            ],
                          ),
                        ),
                      ),
                      if (targetPoint != null)
                        PopupMenuButton<int>(
                          icon: const Icon(Icons.assignment_returned, color: Colors.blue),
                          onSelected: (i) => setState(() => beacons[i].location = targetPoint),
                          itemBuilder: (ctx) => List.generate(beacons.length, (index) => PopupMenuItem(value: index, child: Text("Gán vào P${index+1}"))),
                        ),
                      IconButton(
                        onPressed: (targetPoint == null && selectedIndex == null) ? null : (isAnyMocking ? _stopMock : () { if (targetPoint != null) _setMock(targetPoint!.latitude, targetPoint!.longitude, fromTarget: true); }),
                        icon: Icon(isAnyMocking ? Icons.stop_circle : Icons.play_circle, color: isAnyMocking ? Colors.red : Colors.green, size: 30),
                      ),
                      ElevatedButton(onPressed: _calculateTrilateration, child: const Text("TÍNH")),
                    ],
                  ),
                ],
              ),
            ),
            // MAP (GIỮ NGUYÊN LOGIC HIỂN THỊ)
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
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                      MarkerLayer(
                        markers: [
                          if (myRealLocation != null) Marker(point: myRealLocation!, width: 20, height: 20, child: const CircleAvatar(backgroundColor: Colors.blue, radius: 5)),
                          for (int i = 0; i < beacons.length; i++)
                            if (beacons[i].location != null)
                              Marker(point: beacons[i].location!, width: 30, height: 30, child: Container(decoration: BoxDecoration(color: selectedIndex == i ? Colors.red : Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text("${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))))),
                          if (targetPoint != null) Marker(point: targetPoint!, width: 30, height: 30, child: const Icon(Icons.location_searching, color: Colors.orange, size: 30)),
                        ],
                      ),
                    ],
                  ),
                  Positioned(right: 15, bottom: 15, child: FloatingActionButton(mini: true, backgroundColor: Colors.white, onPressed: () async {
                    Position p = await Geolocator.getCurrentPosition();
                    _mapController.move(LatLng(p.latitude, p.longitude), 15);
                  }, child: const Icon(Icons.my_location, color: Colors.blue))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}