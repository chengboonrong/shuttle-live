package com.chengboonrong.shuttle_live

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sin

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
        val clip = mutableMapOf<String, Any>("durationUs" to durationUs, "width" to width, "height" to height)
        sound(path)?.let { clip["sound"] = it }
        return clip
    }

    /**
     * The clip's 2–8 kHz sound energy in dB, one value per 5 ms from 0 (see [SoundEnvelope]): the first
     * audio track decoded to PCM, its channels averaged, at the source rate. Never throws: no audio
     * track, or audio that won't decode, is null.
     */
    private fun sound(path: String): FloatArray? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val c = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = c
            c.configure(format, null, null, 0)
            c.start()
            val info = MediaCodec.BufferInfo()
            var envelope: SoundEnvelope? = null
            var rate = 0
            var channels = 1
            var float = false
            var inputDone = false
            var idle = 0
            var pcm = FloatArray(0)
            while (true) {
                if (!inputDone) {
                    val i = c.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        idle = 0
                        val n = extractor.readSampleData(c.getInputBuffer(i)!!, 0)
                        if (n < 0) {
                            c.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            c.queueInputBuffer(i, 0, n, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = c.dequeueOutputBuffer(info, 10_000)
                // The layout before the first samples, and again if it changes mid-stream (an HE-AAC switch,
                // 5.1 to stereo). A new rate once the windows have started would move them off clip time.
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED || (o >= 0 && envelope == null)) {
                    val out = c.outputFormat
                    val r = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    require(envelope == null || r == rate) { "the sample rate changed mid-stream" }
                    val encoding = if (out.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        out.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    } else {
                        AudioFormat.ENCODING_PCM_16BIT
                    }
                    rate = r
                    channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    float = encoding == AudioFormat.ENCODING_PCM_FLOAT
                    require(rate > 16000) { "the 8 kHz low-pass needs a rate over 16 kHz" }
                    require(channels > 0 && (float || encoding == AudioFormat.ENCODING_PCM_16BIT)) {
                        "only 16-bit or float PCM is read"
                    }
                }
                if (o < 0) {
                    // A decoder that takes no input and gives no output for ~1 s would hang open: give up.
                    if (o == MediaCodec.INFO_TRY_AGAIN_LATER && ++idle > 100) return null
                    continue
                }
                idle = 0
                if (envelope == null) {
                    envelope = SoundEnvelope(rate.toDouble())
                    // Sound that starts after 0 (an edit list) is silence until then, so the windows stay on clip time.
                    repeat(maxOf(0L, (info.presentationTimeUs * rate / 1e6).roundToLong()).toInt()) { envelope.add(0f) }
                }
                val buf = c.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                buf.position(info.offset).limit(info.offset + info.size)
                val count = if (float) info.size / 4 else info.size / 2
                if (pcm.size < count) pcm = FloatArray(count)
                if (float) {
                    buf.asFloatBuffer().get(pcm, 0, count)
                } else {
                    val shorts = buf.asShortBuffer()
                    for (k in 0 until count) pcm[k] = shorts.get(k) / 32768f
                }
                for (k in 0 until count / channels * channels step channels) {
                    var x = 0f
                    for (ch in 0 until channels) x += pcm[k + ch]
                    envelope.add(x / channels)
                }
                c.releaseOutputBuffer(o, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
            return envelope.db.takeIf { it.isNotEmpty() }?.toFloatArray()
        } catch (t: Throwable) {
            return null
        } finally {
            runCatching { codec?.stop() }
            runCatching { codec?.release() }
            runCatching { extractor.release() }
        }
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
            // ponytail: even spacing; variable-frame-rate clips drift a little. Sound timing relies on it: racket
            // sounds are stamped by real sample time, so this assumes a constant frame rate and audio and video
            // tracks of equal length. Upgrade: in open, read the video track's sample times with a MediaExtractor
            // (no decoding), sort them, and use times[i].
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

/** A 2nd-order RBJ cookbook filter, Q = 0.7071, at [f0] Hz. */
private class Biquad(highPass: Boolean, f0: Double, rate: Double) {
    private val b0: Float
    private val b1: Float
    private val b2: Float
    private val a1: Float
    private val a2: Float
    private var x1 = 0f
    private var x2 = 0f
    private var y1 = 0f
    private var y2 = 0f

    init {
        val w = 2 * PI * f0 / rate
        val a = sin(w) / (2 * 0.7071)
        val c = cos(w)
        val a0 = 1 + a
        val k = if (highPass) (1 + c) / 2 else (1 - c) / 2
        b0 = (k / a0).toFloat()
        b1 = ((if (highPass) -2 * k else 2 * k) / a0).toFloat()
        b2 = b0
        a1 = (-2 * c / a0).toFloat()
        a2 = ((1 - a) / a0).toFloat()
    }

    fun run(x: Float): Float {
        val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

/**
 * Sound energy in dB after a 2 kHz high-pass and an 8 kHz low-pass, one value per 5 ms window, as on
 * iOS: window k is samples [round(k·rate/200), round((k+1)·rate/200)), so windows average exactly
 * 5 ms at any rate. A last, partial window is left out.
 */
private class SoundEnvelope(private val rate: Double) {
    private val hp = Biquad(true, 2000.0, rate)
    private val lp = Biquad(false, 8000.0, rate)
    private var sum = 0f
    private var n = 0
    private var seen = 0L
    private var end = (rate / 200).roundToLong()
    val db = ArrayList<Float>()

    /** Feeds the next mono sample. */
    fun add(x: Float) {
        val y = lp.run(hp.run(x))
        sum += y * y
        n++
        if (++seen != end) return
        db.add(10 * log10(sum / n + 1e-10f))
        sum = 0f
        n = 0
        end = ((db.size + 1) * rate / 200).roundToLong()
    }
}
