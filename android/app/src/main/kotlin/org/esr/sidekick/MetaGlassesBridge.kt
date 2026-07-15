package org.esr.sidekick

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.core.app.ActivityCompat
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.mockdevice.MockDeviceKit
import com.meta.wearable.dat.mockdevice.api.GlassesModel
import com.meta.wearable.dat.mockdevice.api.MockGlasses
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/** Native boundary for Meta Wearables DAT registration and Bluetooth HFP audio. */
class MetaGlassesBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "org.esr.sidekick/meta_glasses"
        private const val EVENT_CHANNEL = "org.esr.sidekick/meta_glasses/events"
        private const val REQUEST_PERMISSIONS = 7319
        private val REQUIRED_PERMISSIONS = arrayOf(
            Manifest.permission.BLUETOOTH,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.INTERNET,
        )
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val audioManager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mockKit by lazy { MockDeviceKit.getInstance(activity.applicationContext) }
    private var mockGlasses: MockGlasses? = null
    private var eventSink: EventChannel.EventSink? = null
    private var registrationJob: Job? = null
    private var devicesJob: Job? = null
    private var initialized = false
    private var audioRouted = false

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitStatus()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "register" -> register(result)
            "routeAudio" -> result.success(routeAudio())
            "clearAudioRoute" -> {
                clearAudioRoute()
                result.success(true)
            }
            "status" -> result.success(statusMap())
            "enableMock" -> enableMock(result)
            "disableMock" -> {
                mockKit.disable()
                mockGlasses = null
                emitStatus()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun initialize(result: MethodChannel.Result) {
        val missing = REQUIRED_PERMISSIONS.filter {
            ActivityCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(activity, missing.toTypedArray(), REQUEST_PERMISSIONS)
            result.success(mapOf("initialized" to false, "permissionsRequested" to true))
            return
        }
        if (!initialized) {
            Wearables.initialize(activity.applicationContext)
            initialized = true
            observeDat()
        }
        result.success(statusMap())
        emitStatus()
    }

    private fun observeDat() {
        registrationJob?.cancel()
        devicesJob?.cancel()
        registrationJob = scope.launch {
            Wearables.registrationState.collect { emitStatus(it.toString()) }
        }
        devicesJob = scope.launch {
            Wearables.devices.collect { emitStatus() }
        }
    }

    private fun register(result: MethodChannel.Result) {
        if (!initialized) {
            result.error("NOT_INITIALIZED", "Grant permissions and initialize Meta DAT first", null)
            return
        }
        Wearables.startRegistration(activity)
        result.success(true)
    }

    private fun routeAudio(): Map<String, Any?> {
        val device = audioManager.availableCommunicationDevices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
        }
        if (device == null) {
            audioRouted = false
            emitStatus()
            return mapOf("routed" to false, "error" to "No Bluetooth HFP headset is available")
        }
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioRouted = audioManager.setCommunicationDevice(device)
        emitStatus()
        return mapOf(
            "routed" to audioRouted,
            "device" to (device.productName?.toString() ?: "Bluetooth headset"),
            "sampleRate" to 8000,
        )
    }

    private fun clearAudioRoute() {
        audioManager.clearCommunicationDevice()
        audioManager.mode = AudioManager.MODE_NORMAL
        audioRouted = false
        emitStatus()
    }

    private fun enableMock(result: MethodChannel.Result) {
        try {
            mockKit.enable()
            val glasses = mockKit.pairGlasses(GlassesModel.RAYBAN_META).getOrThrow()
            glasses.powerOn()
            glasses.unfold()
            glasses.don()
            mockGlasses = glasses
            emitStatus("REGISTERED")
            result.success(statusMap() + mapOf("mock" to true))
        } catch (e: Exception) {
            result.error("MOCK_ERROR", e.message, null)
        }
    }

    private fun statusMap(registrationOverride: String? = null): Map<String, Any?> = mapOf(
        "initialized" to initialized,
        "registration" to (registrationOverride ?: if (initialized) Wearables.registrationState.value.toString() else "UNINITIALIZED"),
        "deviceCount" to (if (initialized) Wearables.devices.value.size else 0),
        "audioRouted" to audioRouted,
        "mock" to (mockGlasses != null),
    )

    private fun emitStatus(registrationOverride: String? = null) {
        eventSink?.success(statusMap(registrationOverride))
    }

    fun dispose() {
        clearAudioRoute()
        scope.cancel()
    }
}
