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
  final Map<String, double> unitToMeter = {'ft': 0.3048, 'm': 1.0, 'km': 1000.0};

  int? selectedIndex; 
  LatLng? targetPoint;
  LatLng? myRealLocation;
  String resultDisplay = "0.000000, 0.000000";
  bool isMockingTarget = false;
  bool isCalculated = false;

  static const double WGS84_A = 6378137.0; 
  static const double WGS84_B = 6356752.314245;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  // --- THUẬT TOÁN TRẮC ĐỊA ECEF ---

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
      
      double factor = unitToMeter[selectedUnit]!;
      double r1 = double.parse(dists[0].text) * factor;
      double r2 = double.parse(dists[1].text) * factor;
      double r3 = double.parse(dists[2].text) * factor;

      if (r1 <= 0 || r2 <= 0 || r3 <= 0) throw "Bán kính phải > 0";

      List<double> ex = [0,0,0], p2p1 = [0,0,0];
      for (int k=0; k<3; k++) p2p1[k] = p2[k] - p1[k];
      double d = sqrt(p2p1[0]*p2p1[0] + p2p1[1]*p2p1[1] + p2p1[2]*p2p1[2]);
      if (d < 0.1) throw "Điểm trùng nhau!";
      for (int k=0; k<3; k++) ex[k] = p2p1[k] / d;

      List<double> p3p1 = [0,0,0];
      for (int k=0; k<3; k++) p3p1[k] = p3[k] - p1[k];
      double i = ex[0]*p3p1[0] + ex[1]*p3p1[1] + ex[2]*p3p1[2];

      List<double> ey = [0,0,0], p3p1iEx = [0,0,0];
      for (int k=0; k<3; k++) p3p1iEx[k] = p3p1[k] - (i * ex[k]);
      double yLen = sqrt(p3p1iEx[0]*p3p1iEx[0] + p3p1iEx[1]*p3p1iEx[1] + p3p1iEx[2]*p3p1iEx[2]);
      if (yLen < 0.1) throw "3 điểm thẳng hàng!";
      for (int k=0; k<3; k++) ey[k] = p3p1iEx[k] / yLen;
      double j = ey[0]*p3p1[0] + ey[1]*p3p1[1] + ey[2]*p3p1[2];

      double xVal = (pow(r1,2).toDouble() - pow(r2,2).toDouble() + pow(d,2).toDouble()) / (2*d);
      double yVal = ((pow(r1,2).toDouble() - pow(r3,2).toDouble() + pow(i,2).toDouble() + pow(j,2).toDouble()) / (2*j)) - ((i/j) * xVal);
      double zSq = pow(r1,2).toDouble() - pow(xVal,2).toDouble() - pow(yVal,2).toDouble();
      double zVal = sqrt(max(0.0, zSq)); 

      List<double> ez = [ex[1]*ey[2]-ex[2]*ey[1], ex[2]*ey[0]-ex[0]*ey[2], ex[0]*ey[1]-ex[1]*ey[0]];

      double fX = p1[0] + xVal*ex[0] + yVal*ey[0] + zVal*ez[0];
      double fY = p1[1] + xVal*ex[1] + yVal*ey[1] + zVal*ez[1];
      double fZ = p1[2] + xVal*ex[2] + yVal*ey[2] + zVal*ez[2];

      LatLng result = _ecefToLatLng(fX, fY, fZ);

      // Nới lỏng giới hạn an toàn lên 2000km để tránh bay ra đại dương quá xa khi nhập sai
      double distCheck = Geolocator.distanceBetween(points[0]!.latitude, points[0]!.longitude, result.latitude, result.longitude);
      if (distCheck > 2000000) throw "Kết quả vượt quá 2000km, vui lòng kiểm tra lại số liệu!";

      setState(() {
        targetPoint = result;
        resultDisplay = "${result.latitude.toStringAsFixed(6)}, ${result.longitude.toStringAsFixed(6)}";
        isCalculated = true;
      });
      _mapController.move(targetPoint!, 14);
    } catch (e) { _showMsg(e.toString()); }
  }

  // --- GIAO DIỆN ---

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
    LatLng current = LatLng(p.latitude, p.longitude);
    setState(() => myRealLocation = current);
    _mapController.move(current, 15);
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
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['ft', 'm', 'km'].map((unit) => Padding(
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
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: selectedIndex == i ? Colors.red : (points[i] != null ? Colors.green : Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text("P${i+1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: dists[i],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(hintText: selectedUnit, contentPadding: EdgeInsets.zero, border: const OutlineInputBorder()),
                            ),
                          ],
                        ),
                      ),
                    )),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), onPressed: () {
                        setState(() { points = [null,null,null]; targetPoint = null; resultDisplay = "0.000000, 0.000000"; isCalculated = false; });
                        _stopMock();
                      }),
                      Expanded(child: Center(child: Text(resultDisplay, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)))),
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
                          setState(() { points[selectedIndex!] = latlng; isCalculated = false; });
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
                          
                          // ICON MỤC TIÊU CŨ NHƯNG THU NHỎ (Size 30)
                          if (targetPoint != null) 
                            Marker(
                              point: targetPoint!, 
                              width: 30, height: 30, 
                              child: const Icon(Icons.location_searching, color: Colors.orange, size: 30)
                            ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    right: 15, bottom: 15,
                    child: FloatingActionButton(
                      mini: true, backgroundColor: Colors.white,
                      onPressed: _getCurrentLocation,
                      child: const Icon(Icons.my_location, color: Colors.blue),
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
}