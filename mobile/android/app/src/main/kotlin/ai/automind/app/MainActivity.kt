package ai.automind.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var btClassic: BtClassicPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        btClassic = BtClassicPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        btClassic?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        btClassic?.dispose()
        btClassic = null
        super.onDestroy()
    }
}
