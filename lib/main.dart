import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MockApp()));

class MockApp extends StatefulWidget {
  const MockApp({super.key});
  @override
  State<MockApp> createState() => _MockAppState();
}

class _MockAppState extends State<MockApp> {
  static const platform = MethodChannel('com.example.mock/gps');
  final MapController _mapController = MapController();
  
  List<LatLng?> points = [null, null, null];
  final List<TextEditingController> dists = List.generate(3, (i) => TextEditingController(text: ""));
  
  String selectedUnit = 'ft'; 
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0, 'mi': 1609.34};

  int? selectedIndex; 
  LatLng? targetPoint;
  LatLng? myRealLocation;
  String resultDisplay = "0.000000, 0.000000";
  String accuracyInfo = "Residual: --";
  bool isMockingTarget = false;

  static const double WGS84_A = 6378137.0; 
  static const double WGS84_B = 6356752.314245;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  // --- ENGINE ĐỊNH VỊ CHUYÊN NGHIỆP ---

  List<double> _latLngToECEF(LatLng loc) {
    double lat = loc.latitude * pi / 180;
    double lon = loc.longitude * pi / 180;
    double eSq = (pow(WGS84_A, 2).toDouble() - pow(WGS84_B, 2).toDouble()) / pow(WGS84_A, 2).toDouble();
    double N = WGS84_A / sqrt(1 - eSq * pow(sin(lat), 2).toDouble());
    return [N * cos(lat) * cos(lon), N * cos(lat) * sin(lon), (N * (1 - eSq)) * sin(lat)];
  }

  LatLng _ecefToLatLng(double x, double y, double z) {
    double lon = atan2(y, x);
    double p = sqrt(x * x + y * y);
    double eSq = (pow(WGS84_A, 2).toDouble() - pow(WGS84_B, 2).toDouble()) / pow(WGS84_A, 2).toDouble();
    double lat = atan2(z, p * (1 - eSq));
    for (int i = 0; i < 5; i++) {
      double N = WGS84_A / sqrt(1 - eSq * pow(sin(lat), 2).toDouble());
      lat = atan2(z + eSq * N * sin(lat), p);
    }
    return LatLng(lat * 180 / pi, lon * 180 / pi);
  }

  void _calculateTrilateration() {
    FocusScope.of(context).unfocus();
    try {
      if (points.any((p) => p == null) || dists.any((c) => c.text.isEmpty)) return;

      var p1 = _latLngToECEF(points[0]!);
      var p2 = _latLngToECEF(points[1]!);
      var p3 = _latLngToECEF(points[2]!);
      
      double r1 = double.parse(dists[0].text) * unitToMeter[selectedUnit]!;
      double r2 = double.parse(dists[1].text) * unitToMeter[selectedUnit]!;
      double r3 = double.parse(dists[2].text) * unitToMeter[selectedUnit]!;

      // 1. Tạo hệ trục tọa độ cục bộ (Local Reference Frame)
      List<double> ex = [0,0,0], p2p1 = [0,0,0];
      for (int k=0; k<3; k++) p2p1[k] = p2[k] - p1[k];
      double d = sqrt(p2p1[0]*p2p1[0] + p2p1[1]*p2p1[1] + p2p1[2]*p2p1[2]);
      for (int k=0; k<3; k++) ex[k] = p2p1[k] / d;

      List<double> p3p1 = [0,0,0];
      for (int k=0; k<3; k++) p3p1[k] = p3[k] - p1[k];
      double i = ex[0]*p3p1[0] + ex[1]*p3p1[1] + ex[2]*p3p1[2];

      List<double> ey = [0,0,0], p3p1iEx = [0,0,0];
      for (int k=0; k<3; k++) p3p1iEx[k] = p3p1[k] - (i * ex[k]);
      double yLen = sqrt(p3p1iEx[0]*p3p1iEx[0] + p3p1iEx[1]*p3p1iEx[1] + p3p1iEx[2]*p3p1iEx[2]);
      for (int k=0; k<3; k++) ey[k] = p3p1iEx[k] / yLen;
      double j = ey[0]*p3p1[0] + ey[1]*p3p1[1] + ey[2]*p3p1[2];

      // 2. Tính X, Y trong hệ tọa độ phẳng
      double xVal = (pow(r1, 2).toDouble() - pow(r2, 2).toDouble() + pow(d, 2).toDouble()) / (2 * d);
      double yVal = ((pow(r1, 2).toDouble() - pow(r3, 2).toDouble() + pow(i, 2).toDouble() + pow(j, 2).toDouble()) / (2 * j)) - ((i / j) * xVal);
      double zSq = pow(r1, 2).toDouble() - pow(xVal, 2).toDouble() - pow(yVal, 2).toDouble();
      double zVal = sqrt(max(0.0, zSq)); 

      List<double> ez = [ex[1]*ey[2]-ex[2]*ey[1], ex[2]*ey[0]-ex[0]*ey[2], ex[0]*ey[1]-ex[1]*ey[0]];

      // 3. TÌM 2 NGHIỆM KHÔNG GIAN (A & B)
      List<double> solA = [0,0,0], solB = [0,0,0];
      for (int k=0; k<3; k++) {
        double base = p1[k] + xVal*ex[k] + yVal*ey[k];
        solA[k] = base + zVal*ez[k];
        solB[k] = base - zVal*ez[k];
      }

      // 4. BỘ LỌC CHỌN NGHIỆM THÔNG MINH (Smart Filter)
      LatLng resA = _ecefToLatLng(solA[0], solA[1], solA[2]);
      LatLng resB = _ecefToLatLng(solB[0], solB[1], solB[2]);

      // Cách 1: So sánh với bán kính Trái đất (6,371km)
      double rA = sqrt(solA[0]*solA[0] + solA[1]*solA[1] + solA[2]*solA[2]);
      double rB = sqrt(solB[0]*solB[0] + solB[1]*solB[1] + solB[2]*solB[2]);
      double scoreA = (rA - 6371000).abs();
      double scoreB = (rB - 6371000).abs();

      // Cách 2: Ưu tiên GPS thật nếu có dữ liệu
      if (myRealLocation != null) {
        double distA = Geolocator.distanceBetween(myRealLocation!.latitude, myRealLocation!.longitude, resA.latitude, resA.longitude);
        double distB = Geolocator.distanceBetween(myRealLocation!.latitude, myRealLocation!.longitude, resB.latitude, resB.longitude);
        scoreA = distA; scoreB = distB;
      }

      LatLng finalRes = (scoreA < scoreB) ? resA : resB;
      
      // 5. Tính Residual Error (Độ tin cậy)
      double residual = _calculateResidual(finalRes, [r1, r2, r3]);

      setState(() {
        targetPoint = finalRes;
        resultDisplay = "${finalRes.latitude.toStringAsFixed(6)}, ${finalRes.longitude.toStringAsFixed(6)}";
        accuracyInfo = "Residual: ±${residual.toStringAsFixed(1)}m";
      });
      _mapController.move(finalRes, 14);
    } catch (e) { _showMsg("Lỗi: $e"); }
  }

  double _calculateResidual(LatLng target, List<double> radii) {
    double sumSq = 0;
    for (int i=0; i<3; i++) {
      double d = Geolocator.distanceBetween(target.latitude, target.longitude, points[i]!.latitude, points[i]!.longitude);
      sumSq += pow(d - radii[i], 2).toDouble();
    }
    return sqrt(sumSq / 3);
  }

  // --- GIAO DIỆN & MOCK GPS ---

  void _showMsg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.redAccent));

  Future<void> _requestPermission() async {
    var status = await [Permission.location, Permission.locationWhenInUse].request();
    if (status[Permission.location]!.isGranted) {
      Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
          .listen((p) { if (mounted) setState(() => myRealLocation = LatLng(p.latitude, p.longitude)); });
    }
  }

  Future<void> _getCurrentLocation() async {
    Position p = await Geolocator.getCurrentPosition();
    _mapController.move(LatLng(p.latitude, p.longitude), 15);
  }

  Future<void> _setMock(double lat, double lng, {bool fromTarget = false}) async {
    try {
      await platform.invokeMethod('setMockLocation', {"lat": lat, "lng": lng});
      setState(() { isMockingTarget = fromTarget; if (fromTarget) selectedIndex = null; });
    } catch (e) { print(e); }
  }

  Future<void> _stopMock() async {
    try { await platform.invokeMethod('stopMockLocation'); setState(() { isMockingTarget = false; selectedIndex = null; }); } 
    catch (e) { print(e); }
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['ft', 'm', 'km', 'mi'].map((unit) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(label: Text(unit), selected: selectedUnit == unit, onSelected: (val) => setState(() => selectedUnit = unit)),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(3, (i) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (selectedIndex == i) { _stopMock(); } 
                                else {
                                  setState(() { selectedIndex = i; isMockingTarget = false; });
                                  if (points[i] != null) { _mapController.move(points[i]!, 14); _setMock(points[i]!.latitude, points[i]!.longitude); }
                                }
                              },
                              child: Container(
                                alignment: Alignment.center, padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: selectedIndex == i ? Colors.red : (points[i] != null ? Colors.green : Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text("P${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            TextField(controller: dists[i], keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12), decoration: InputDecoration(hintText: selectedUnit, isDense: true)),
                          ],
                        ),
                      ),
                    )),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () {
                        setState(() { points = [null,null,null]; targetPoint = null; resultDisplay = "0.000000, 0.000000"; accuracyInfo = "Residual: --"; });
                        _stopMock();
                      }),
                      Expanded(
                        child: GestureDetector(
                          onLongPress: () { Clipboard.setData(ClipboardData(text: resultDisplay)); _showMsg("Đã copy tọa độ!"); },
                          child: Column(
                            children: [
                              Text(resultDisplay, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                              Text(accuracyInfo, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                            ],
                          ),
                        ),
                      ),
                      if (targetPoint != null)
                        PopupMenuButton<int>(
                          icon: const Icon(Icons.assignment_returned, color: Colors.blue),
                          onSelected: (i) => setState(() => points[i] = targetPoint),
                          itemBuilder: (ctx) => [0, 1, 2].map((i) => PopupMenuItem(value: i, child: Text("Gán vào P${i+1}"))).toList(),
                        ),
                      IconButton(
                        onPressed: (targetPoint == null && selectedIndex == null) ? null : (isAnyMocking ? _stopMock : () { if (targetPoint != null) _setMock(targetPoint!.latitude, targetPoint!.longitude, fromTarget: true); }),
                        icon: Icon(isAnyMocking ? Icons.stop_circle : Icons.play_circle, color: isAnyMocking ? Colors.red : Colors.green, size: 34),
                      ),
                      ElevatedButton(onPressed: _calculateTrilateration, child: const Text("TÍNH")),
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
                          setState(() { points[selectedIndex!] = latlng; });
                          _setMock(latlng.latitude, latlng.longitude);
                        }
                      },
                    ),
                    children: [
                      TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                      MarkerLayer(
                        markers: [
                          if (myRealLocation != null) Marker(point: myRealLocation!, width: 20, height: 20, child: const CircleAvatar(backgroundColor: Colors.blue, radius: 5)),
                          for (int i = 0; i < 3; i++)
                            if (points[i] != null)
                              Marker(point: points[i]!, width: 30, height: 30, child: Container(decoration: BoxDecoration(color: selectedIndex == i ? Colors.red : Colors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: Center(child: Text("${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
                          if (targetPoint != null) Marker(point: targetPoint!, width: 30, height: 30, child: const Icon(Icons.location_searching, color: Colors.orange, size: 30)),
                        ],
                      ),
                    ],
                  ),
                  Positioned(right: 15, bottom: 15, child: FloatingActionButton(mini: true, backgroundColor: Colors.white, onPressed: _getCurrentLocation, child: const Icon(Icons.my_location, color: Colors.blue))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}