package io.github.docscanner.doc_scanner

import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import com.googlecode.tesseract.android.TessBaseAPI.PageIteratorLevel.RIL_WORD
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

    /**
     * Runs Tesseract on an image. [dataPath] must contain a `tessdata` folder.
     * Returns the full text plus every word with its bounding box in image
     * pixels, so the PDF export can place an invisible, searchable text layer.
     */
    private fun recognize(imagePath: String, dataPath: String, language: String): Map<String, Any> {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(imagePath, bounds)
        val api = TessBaseAPI()
        try {
            check(api.init(dataPath, language)) { "Cannot load Tesseract data for '$language'" }
            api.setImage(File(imagePath))
            val text = api.utF8Text ?: ""
            val words = ArrayList<List<Any>>()
            api.resultIterator?.let { iterator ->
                try {
                    iterator.begin()
                    do {
                        val word = iterator.getUTF8Text(RIL_WORD)
                        if (word.isNullOrBlank()) continue
                        val r = iterator.getBoundingRect(RIL_WORD)
                        words.add(listOf(word, r.left, r.top, r.width(), r.height()))
                    } while (iterator.next(RIL_WORD))
                } finally {
                    iterator.delete()
                }
            }
            return mapOf(
                "text" to text,
                "width" to bounds.outWidth,
                "height" to bounds.outHeight,
                "words" to words,
            )
        } finally {
            api.recycle()
        }
    }

    override fun onDestroy() {
        ocrExecutor.shutdown()
        super.onDestroy()
    }
}
