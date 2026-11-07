// ⚠️ 寶寶記得把第一行的 package 換成你專案實際的名稱唷！（例如 com.example.gunbook）
package com.example.flutter_application_1manga

import android.view.KeyEvent
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.gunbook.volume"
    private var methodChannel: MethodChannel? = null
    private var storage: SafImportBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 建立與 Flutter 溝通的橋樑
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        storage = SafImportBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (storage?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        storage?.dispose()
        storage = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // 完美攔截音量減（下一頁）
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            methodChannel?.invokeMethod("volumeDown", null)
            return true // 回傳 true 代表攔截，就不會跳出系統音量條囉！
        } 
        // 完美攔截音量加（上一頁）
        else if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            methodChannel?.invokeMethod("volumeUp", null)
            return true 
        }
        return super.onKeyDown(keyCode, event)
    }
}
