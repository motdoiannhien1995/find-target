package com.khoa.trilaterat

import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.PowerManager
import android.os.SystemClock
import android.widget.Toast
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.mock/gps"
    private lateinit var locationManager: LocationManager
    
    @Volatile private var currentLat = 0.0
    @Volatile private var currentLng = 0.0
    @Volatile private var isMocking = false
    
    // Nâng cấp lên HandlerThread chuẩn của Android
    private var mockHandlerThread: HandlerThread? = null
    private var mockHandler: Handler? = null
    
    // Vũ khí bí mật: WakeLock giúp CPU không giết app dưới nền
    private var wakeLock: PowerManager.WakeLock? = null

    // Bắt buộc có "fused" để qua mặt Google Play Services
    private val providers = arrayOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, "fused")

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        
        // Khởi tạo hệ thống giữ CPU thức tỉnh
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "MockGPS::WakeLock")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setMockLocation" -> {
                    currentLat = call.argument<Double>("lat") ?: 0.0
                    currentLng = call.argument<Double>("lng") ?: 0.0
                    if (!isMocking) {
                        startMock()
                    }
                    result.success(null)
                }
                "stopMockLocation" -> {
                    stopMock()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private val mockRunnable = object : Runnable {
        override fun run() {
            if (!isMocking) return
            
            for (provider in providers) {
                try {
                    val mockLocation = Location(provider)
                    mockLocation.latitude = currentLat
                    mockLocation.longitude = currentLng
                    mockLocation.altitude = 10.0
                    mockLocation.speed = 0.5f
                    mockLocation.bearing = 90.0f
                    mockLocation.accuracy = 1.0f
                    mockLocation.time = System.currentTimeMillis()
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
                        mockLocation.elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        mockLocation.bearingAccuracyDegrees = 0.1f
                        mockLocation.verticalAccuracyMeters = 0.1f
                        mockLocation.speedAccuracyMetersPerSecond = 0.1f
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        mockLocation.isMock = true
                    } else {
                        try {
                            val method = Location::class.java.getMethod("setIsFromMockProvider", Boolean::class.javaPrimitiveType)
                            method.invoke(mockLocation, true)
                        } catch (e: Throwable) {}
                    }

                    try {
                        val makeCompleteMethod = Location::class.java.getMethod("makeComplete")
                        makeCompleteMethod.invoke(mockLocation)
                    } catch (e: Throwable) {}

                    locationManager.setTestProviderLocation(provider, mockLocation)
                } catch (e: Throwable) {
                    // Dùng Throwable thay cho Exception để hấp thụ tuyệt đối mọi lỗi văng app
                }
            }
            // Lặp lại sau mỗi 0.5 giây
            mockHandler?.postDelayed(this, 500)
        }
    }

    private fun startMock() {
        try {
            for (provider in providers) {
                try { locationManager.removeTestProvider(provider) } catch (e: Throwable) {}
                locationManager.addTestProvider(provider, false, false, false, false, true, true, true, 1, 1)
                locationManager.setTestProviderEnabled(provider, true)
            }
        } catch (e: SecurityException) {
            runOnUiThread { Toast.makeText(this, "Chưa cấp quyền Mock App trong tùy chọn nhà phát triển!", Toast.LENGTH_LONG).show() }
            return
        } catch (e: Throwable) {}

        isMocking = true
        
        // Bật WakeLock để chặn hệ thống giết app (Giữ tối đa 60 phút mỗi lần bật)
        try {
            if (wakeLock?.isHeld == false) {
                wakeLock?.acquire(60 * 60 * 1000L) 
            }
        } catch (e: Throwable) {}

        if (mockHandlerThread == null) {
            mockHandlerThread = HandlerThread("MockLocationThread")
            mockHandlerThread?.start()
            mockHandler = Handler(mockHandlerThread!!.looper)
        }
        mockHandler?.post(mockRunnable)
    }

    private fun stopMock() {
        isMocking = false
        mockHandler?.removeCallbacks(mockRunnable)
        
        mockHandlerThread?.quitSafely()
        mockHandlerThread = null
        mockHandler = null
        
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (e: Throwable) {}

        for (provider in providers) {
            try { locationManager.removeTestProvider(provider) } catch (e: Throwable) {}
        }
    }

    override fun onDestroy() {
        stopMock()
        super.onDestroy()
    }
}