package com.khoa.fakegpstracetarget // ĐÃ ĐỔI DÒNG NÀY

import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.mock/gps"
    private var locationManager: LocationManager? = null
    private val handler = Handler(Looper.getMainLooper())
    private var mockRunnable: Runnable? = null
    
    private var currentLat = 0.0
    private var currentLng = 0.0
    private var isMocking = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setMockLocation" -> {
                    currentLat = call.argument<Double>("lat") ?: 0.0
                    currentLng = call.argument<Double>("lng") ?: 0.0
                    startMockLoop()
                    result.success(null)
                }
                "stopMockLocation" -> {
                    stopMockLoop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startMockLoop() {
        stopMockLoop() // Dừng vòng lặp cũ nếu có
        isMocking = true
        
        val provider = LocationManager.GPS_PROVIDER
        
        try {
            if (locationManager?.getProvider(provider) != null) {
                locationManager?.removeTestProvider(provider)
            }
            locationManager?.addTestProvider(provider, false, false, false, false, true, true, true, 1, 1)
            locationManager?.setTestProviderEnabled(provider, true)
        } catch (e: Exception) {}

        // Tạo vòng lặp gửi tọa độ mỗi 1 giây
        mockRunnable = object : Runnable {
            override fun run() {
                if (!isMocking) return
                
                try {
                    val mockLocation = Location(provider)
                    mockLocation.latitude = currentLat
                    mockLocation.longitude = currentLng
                    mockLocation.altitude = 0.0
                    mockLocation.accuracy = 1.0f
                    mockLocation.time = System.currentTimeMillis()
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                        mockLocation.elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                    }

                    locationManager?.setTestProviderLocation(provider, mockLocation)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                
                handler.postDelayed(this, 1000) // Lặp lại sau 1 giây
            }
        }
        handler.post(mockRunnable!!)
    }

    private fun stopMockLoop() {
        isMocking = false
        mockRunnable?.let { handler.removeCallbacks(it) }
        try {
            locationManager?.removeTestProvider(LocationManager.GPS_PROVIDER)
        } catch (e: Exception) {}
    }

    override fun onDestroy() {
        stopMockLoop()
        super.onDestroy()
    }
}