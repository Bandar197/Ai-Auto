package ai.automind.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Bluetooth Classic SPP (RFCOMM) link to a paired ELM327 adapter.
 *
 * MethodChannel "automind/bt_classic": isSupported, isEnabled, requestPermission,
 * bondedDevices -> [{name, address}], connect(address), write(data), disconnect.
 * EventChannel "automind/bt_classic/rx": received bytes (ByteArray) and
 * {"event": "disconnected"} when the link drops.
 *
 * Socket IO runs on background threads; results are posted to the main thread.
 * No discovery of unpaired devices: the user pairs in Android settings first.
 */
class BtClassicPlugin(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val PERMISSION_REQUEST = 4711
    }

    private val methods = MethodChannel(messenger, "automind/bt_classic")
    private val events = EventChannel(messenger, "automind/bt_classic/rx")
    private val main = Handler(Looper.getMainLooper())
    private val connectExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val writeExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var output: OutputStream? = null
    private var readerThread: Thread? = null
    private var sink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    private val adapter: BluetoothAdapter?
        get() = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun hasConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    // ------------------------------------------------------------------ methods

    @SuppressLint("MissingPermission")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(adapter != null)
            "isEnabled" -> result.success(adapter?.isEnabled == true)
            "requestPermission" -> {
                if (hasConnectPermission()) {
                    result.success(true)
                } else {
                    pendingPermission?.success(false)
                    pendingPermission = result
                    activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), PERMISSION_REQUEST)
                }
            }
            "bondedDevices" -> {
                val a = adapter
                when {
                    a == null -> result.success(emptyList<Map<String, String>>())
                    !hasConnectPermission() -> result.error("permission", "BLUETOOTH_CONNECT not granted", null)
                    else -> try {
                        val list = a.bondedDevices.orEmpty().map { d ->
                            mapOf("name" to (d.name ?: ""), "address" to d.address)
                        }
                        result.success(list)
                    } catch (e: SecurityException) {
                        result.error("permission", e.message, null)
                    }
                }
            }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("bad_args", "address missing", null)
                    return
                }
                connectExecutor.execute {
                    try {
                        connectBlocking(address)
                        main.post { result.success(true) }
                    } catch (e: SecurityException) {
                        main.post { result.error("permission", e.message, null) }
                    } catch (e: Exception) {
                        main.post { result.error("connect_failed", e.message, null) }
                    }
                }
            }
            "write" -> {
                val data = call.argument<ByteArray>("data")
                val out = output
                if (data == null || out == null) {
                    result.error("not_connected", "socket not connected", null)
                    return
                }
                writeExecutor.execute {
                    try {
                        out.write(data)
                        out.flush()
                        main.post { result.success(null) }
                    } catch (e: IOException) {
                        main.post { result.error("write_failed", e.message, null) }
                        closeSocket(true)
                    }
                }
            }
            "disconnect" -> {
                closeSocket(false)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    @Throws(IOException::class)
    private fun connectBlocking(address: String) {
        closeSocket(false)
        val a = adapter ?: throw IOException("Bluetooth not available")
        if (!hasConnectPermission()) throw SecurityException("BLUETOOTH_CONNECT not granted")
        if (!a.isEnabled) throw IOException("Bluetooth is off")
        val device = a.getRemoteDevice(address)
        try {
            a.cancelDiscovery() // discovery slows RFCOMM connects; needs BLUETOOTH_SCAN on 12+
        } catch (ignored: SecurityException) {
        }
        var s: BluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
        try {
            s.connect()
        } catch (first: IOException) {
            try {
                s.close()
            } catch (ignored: IOException) {
            }
            // Some ELM327 clones only accept an insecure (unauthenticated) RFCOMM link.
            s = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
            s.connect()
        }
        socket = s
        output = s.outputStream
        startReader(s, s.inputStream)
    }

    private fun startReader(s: BluetoothSocket, input: InputStream) {
        val t = Thread {
            val buf = ByteArray(1024)
            try {
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n > 0) {
                        val chunk = buf.copyOf(n)
                        main.post { sink?.success(chunk) }
                    }
                }
            } catch (ignored: IOException) {
            }
            // Link dropped (not an explicit disconnect): tell Dart.
            if (socket === s) closeSocket(true)
        }
        t.isDaemon = true
        t.name = "automind-bt-rx"
        readerThread = t
        t.start()
    }

    @Synchronized
    private fun closeSocket(notify: Boolean) {
        val s = socket
        socket = null
        output = null
        readerThread = null
        if (s != null) {
            try {
                s.close()
            } catch (ignored: IOException) {
            }
            if (notify) main.post { sink?.success(mapOf("event" to "disconnected")) }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    // ------------------------------------------------------------------ events

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun dispose() {
        closeSocket(false)
        connectExecutor.shutdownNow()
        writeExecutor.shutdownNow()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
