package io.github.docscanner.doc_scanner

import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val ocrExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "doc_scanner/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val imagePath = call.argument<String>("imagePath")!!
                val dataPath = call.argument<String>("dataPath")!!
                val language = call.argument<String>("language")!!
                ocrExecutor.execute {
                    val outcome = runCatching { recognize(imagePath, dataPath, language) }
                    mainHandler.post {
                        outcome.fold(
                            { result.success(it) },
                            { result.error("OCR_FAILED", it.message, null) },
                        )
                    }
                }
            }
    }

    /** Runs Tesseract on an image. [dataPath] must contain a `tessdata` folder. */
    private fun recognize(imagePath: String, dataPath: String, language: String): String {
        val api = TessBaseAPI()
        try {
            check(api.init(dataPath, language)) { "Cannot load Tesseract data for '$language'" }
            api.setImage(File(imagePath))
            return api.utF8Text ?: ""
        } finally {
            api.recycle()
        }
    }

    override fun onDestroy() {
        ocrExecutor.shutdown()
        super.onDestroy()
    }
}
