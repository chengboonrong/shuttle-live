package com.chengboonrong.shuttle_live

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/** A frame under this long after the last one returned is skipped, so a 60 fps clip yields every other frame. */
private const val MIN_GAP_US = 32333L
/** Seek step below API 28, where frames are fetched by time (1/30 s). */
private const val STEP_US = 33333L
private const val LONGEST_SIDE = 1280
/** Consecutive undecodable frames after which next() gives up on the clip. */
private const val MAX_MISSES = 30

/**
 * Channel `shuttle_live/video_frames` (open / next / close): reads one video's frames in
 * presentation order, the same contract as the iOS VideoFrameReader. Decoding runs on one
 * worker thread (all reader state is touched only there); replies go out on the main thread.
 */
class VideoFrames(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var retriever: MediaMetadataRetriever? = null
    private var durationUs = 0L
    /** Size after the clip's rotation is applied. */
    private var width = 0
    private var height = 0
    private var rotation = 0
    /** > 0 on API 28+, where frames are fetched by index; 0 means fetch by time. */
    private var frameCount = 0
    private var cursor = 0
    private var lastUs: Long? = null

    init {
        MethodChannel(messenger, "shuttle_live/video_frames").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            var reply: Any? = null
            var error: Throwable? = null
            var known = true
            try {
                when (call.method) {
                    "open" -> reply = open(call.argument<String>("path") ?: "")
                    "next" -> reply = next()
                    "close" -> close()
                    else -> known = false
                }
            } catch (t: Throwable) {
                // Like iOS, only open can fail; a failed next ends the clip and close always replies null.
                if (call.method == "open") error = t else close()
            }
            main.post {
                when {
                    !known -> result.notImplemented()
                    error != null -> result.error("unreadable", error?.message, null)
                    else -> result.success(reply)
                }
            }
        }
    }

    private fun open(path: String): Map<String, Any> {
        close()
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            fun meta(key: Int) = r.extractMetadata(key)?.toLongOrNull() ?: 0L
            val w = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt()
            val h = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt()
            val us = meta(MediaMetadataRetriever.METADATA_KEY_DURATION) * 1000
            require(r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) != null && w > 0 && h > 0 && us > 0) {
                "not a readable video"
            }
            rotation = ((meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION).toInt() % 360) + 360) % 360
            val turned = rotation == 90 || rotation == 270
            width = if (turned) h else w
            height = if (turned) w else h
            durationUs = us
            frameCount = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT).toInt()
            } else {
                0
            }
            // A file that parses but won't decode fails here rather than stalling in next().
            require(decode(r, 0, 0L) != null) { "no decodable frame" }
        } catch (t: Throwable) {
            runCatching { r.release() }
            throw t
        }
        retriever = r
        cursor = 0
        lastUs = null
        return mapOf("durationUs" to durationUs, "width" to width, "height" to height)
    }

    /** Never throws, so a failing release can't cost a reply. */
    private fun close() {
        val r = retriever
        retriever = null
        runCatching { r?.release() }
    }

    /** Frame [i] (shown at [timeUs]) by index on API 28+, else by time. Null if it won't decode. */
    private fun decode(r: MediaMetadataRetriever, i: Int, timeUs: Long): Bitmap? =
        if (frameCount > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            r.getFrameAtIndex(i)
        } else {
            r.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
        }

    /** The next kept frame, or null at the end of the clip (or when no clip is open). */
    private fun next(): Map<String, Any>? {
        val r = retriever ?: return null
        var misses = 0
        while (true) {
            val i = cursor++
            // ponytail: even spacing; variable-frame-rate clips drift a little
            val timeUs = if (frameCount > 0) i * durationUs / frameCount else i * STEP_US
            if (timeUs >= durationUs) return null
            val last = lastUs
            if (last != null && timeUs - last < MIN_GAP_US) continue // skipped without decoding
            val raw = decode(r, i, timeUs)
            if (raw == null) {
                // A run of undecodable frames means the clip is broken; end it rather than walk the whole file.
                if (++misses >= MAX_MISSES) {
                    close()
                    return null
                }
                continue
            }
            lastUs = timeUs
            // Some devices hand back frames already rotated; turn only if the size says it is needed.
            val upright = if (rotation != 0 && (raw.width != width || raw.height != height)) {
                Bitmap.createBitmap(
                    raw, 0, 0, raw.width, raw.height, Matrix().apply { postRotate(rotation.toFloat()) }, true,
                )
            } else {
                raw
            }
            return mapOf("jpeg" to jpeg(upright), "timeUs" to timeUs, "thumb" to thumb(upright))
        }
    }

    private fun jpeg(frame: Bitmap): ByteArray {
        val k = minOf(1f, LONGEST_SIDE.toFloat() / maxOf(frame.width, frame.height))
        val sized = if (k < 1f) {
            Bitmap.createScaledBitmap(frame, (frame.width * k).roundToInt(), (frame.height * k).roundToInt(), true)
        } else {
            frame
        }
        return ByteArrayOutputStream().also { sized.compress(Bitmap.CompressFormat.JPEG, 80, it) }.toByteArray()
    }

    /**
     * 32x18 gray, row-major: the frame is scaled to 128x72, each 4x4 block averaged per channel, then
     * gray = (77R + 150G + 29B) >> 8, the same formula as the iOS reader so one cut threshold fits both.
     * The block average stands in for iOS's Lanczos (a single 40x bilinear scale would alias).
     */
    private fun thumb(frame: Bitmap): ByteArray {
        val px = IntArray(128 * 72)
        Bitmap.createScaledBitmap(frame, 128, 72, true).getPixels(px, 0, 128, 0, 0, 128, 72)
        val gray = ByteArray(32 * 18)
        for (y in 0 until 18) {
            for (x in 0 until 32) {
                var r = 0
                var g = 0
                var b = 0
                for (dy in 0 until 4) {
                    for (dx in 0 until 4) {
                        val p = px[(4 * y + dy) * 128 + 4 * x + dx]
                        r += Color.red(p)
                        g += Color.green(p)
                        b += Color.blue(p)
                    }
                }
                // Sums of 16 samples: (sum + 8) >> 4 is the rounded channel average.
                gray[y * 32 + x] = ((77 * ((r + 8) shr 4) + 150 * ((g + 8) shr 4) + 29 * ((b + 8) shr 4)) shr 8).toByte()
            }
        }
        return gray
    }
}
