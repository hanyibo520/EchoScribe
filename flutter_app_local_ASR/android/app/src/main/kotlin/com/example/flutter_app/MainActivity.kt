package com.example.flutter_app

import android.app.Activity
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val channelName = "local_meeting_asr/native_bridge"
    private val audioPickerRequestCode = 9401
    private var pendingAudioPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "applicationSupportDirectory" -> {
                            result.success(mapOf("path" to applicationSupportDirectory().absolutePath))
                        }
                        "resolveBundledAssetPath" -> {
                            // Android APK assets are not addressable as normal filesystem paths.
                            // The Dart layer will fall back to the installed copy path.
                            result.success(resolveBundledAssetPath(call))
                        }
                        "installBundledDirectory" -> {
                            result.success(installBundledDirectory(call))
                        }
                        "inspectBridges" -> {
                            result.success(inspectBridges(call))
                        }
                        "pickAudioFile" -> {
                            pickAudioFile(result)
                        }
                        "transcribeWithWhisperCpp" -> {
                            runOnWorker(result) {
                                transcribeWithWhisperCpp(call)
                            }
                        }
                        "transcribeAudioFileWithWhisperCpp" -> {
                            runOnWorker(result) {
                                transcribeAudioFileWithWhisperCpp(call)
                            }
                        }
                        "decodeAudioFileToPcm16" -> {
                            runOnWorker(result) {
                                decodeAudioFileToPcm16(call)
                            }
                        }
                        "deleteImportedAudioIfNeeded" -> {
                            removeImportedAudioIfNeeded(call.requiredString("audioFilePath"))
                            result.success(null)
                        }
                        "summarizeWithLlamaCpp" -> {
                            result.error(
                                "LLAMA_CPP_UNAVAILABLE",
                                "llama.cpp runtime is not linked into the Android target",
                                null
                            )
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: IllegalArgumentException) {
                    result.error("INVALID_ARGUMENTS", error.message, null)
                } catch (error: Exception) {
                    result.error("NATIVE_BRIDGE_FAILED", error.message, null)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != audioPickerRequestCode) {
            return
        }

        val result = pendingAudioPickerResult ?: return
        pendingAudioPickerResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        try {
            val uri = data.data ?: throw IllegalArgumentException("Missing selected audio URI")
            val picked = copyPickedAudio(uri)
            result.success(mapOf("path" to picked.file.absolutePath, "name" to picked.name))
        } catch (error: Exception) {
            result.error("AUDIO_IMPORT_FAILED", error.message, null)
        }
    }

    private fun applicationSupportDirectory(): File {
        return File(filesDir, "local_meeting_asr_support").also { directory ->
            directory.mkdirs()
        }
    }

    private external fun transcribePcm16WithWhisper(
        modelPath: String,
        pcm16Audio: ByteArray,
        sampleRate: Int,
        languageCode: String
    ): String

    private fun runOnWorker(
        result: MethodChannel.Result,
        block: () -> Map<String, Any?>
    ) {
        Thread {
            try {
                val response = block()
                runOnUiThread { result.success(response) }
            } catch (error: IllegalArgumentException) {
                runOnUiThread { result.error("INVALID_ARGUMENTS", error.message, null) }
            } catch (error: Exception) {
                runOnUiThread { result.error("NATIVE_BRIDGE_FAILED", error.message, null) }
            }
        }.start()
    }

    private fun pickAudioFile(result: MethodChannel.Result) {
        if (pendingAudioPickerResult != null) {
            result.error("PICKER_BUSY", "An audio picker is already open", null)
            return
        }

        pendingAudioPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "audio/mpeg",
                    "audio/mp4",
                    "audio/aac",
                    "audio/wav",
                    "audio/x-wav",
                    "audio/flac",
                    "audio/ogg"
                )
            )
        }

        try {
            startActivityForResult(intent, audioPickerRequestCode)
        } catch (error: Exception) {
            pendingAudioPickerResult = null
            result.error("PICKER_UNAVAILABLE", error.message, null)
        }
    }

    private fun copyPickedAudio(uri: Uri): ImportedAudioFile {
        val displayName = displayNameFor(uri)
        val directory = File(cacheDir, "ImportedAudio").also { imported ->
            if (imported.exists()) {
                imported.deleteRecursively()
            }
            imported.mkdirs()
        }
        val destination = File(directory, "${System.currentTimeMillis()}-$displayName")

        contentResolver.openInputStream(uri)?.use { input ->
            destination.outputStream().use { output ->
                input.copyTo(output)
            }
        } ?: throw IllegalArgumentException("Unable to open selected audio")

        return ImportedAudioFile(file = destination, name = displayName)
    }

    private fun displayNameFor(uri: Uri): String {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                val name = cursor.getString(nameIndex)
                if (!name.isNullOrBlank()) {
                    return sanitizeFileName(name)
                }
            }
        }
        return "audio"
    }

    private fun resolveBundledAssetPath(call: MethodCall): Map<String, Any?>? {
        val assetDirectory = call.requiredString("assetDirectory")
        val fileName = call.requiredString("fileName")
        val assetKey = flutterAssetKey(assetDirectory, fileName)

        return if (assetExists(assetKey)) {
            mapOf("path" to "")
        } else {
            null
        }
    }

    private fun installBundledDirectory(call: MethodCall): Map<String, Any?> {
        val assetDirectory = call.requiredString("assetDirectory")
        val destinationDirectory = call.requiredString("destinationDirectory")
        val fileNames = call.requiredStringList("fileNames")
        val destinationRoot = File(destinationDirectory)

        if (!destinationRoot.exists() && !destinationRoot.mkdirs()) {
            throw IllegalStateException("Unable to create $destinationDirectory")
        }

        for (fileName in fileNames) {
            val assetKey = flutterAssetKey(assetDirectory, fileName)
            val destination = File(destinationRoot, fileName)

            if (destination.exists() && destination.length() > 0L) {
                continue
            }

            copyAsset(assetKey, destination)
        }

        return mapOf(
            "installed" to true,
            "sourcePath" to assetDirectory,
            "destinationPath" to destinationRoot.absolutePath
        )
    }

    private fun inspectBridges(call: MethodCall): Map<String, Any?> {
        val whisperModelPath = call.argument<String>("whisperModelPath").orEmpty()
        val whisperStatus =
            if (whisperModelPath.isNotEmpty() && !File(whisperModelPath).exists()) {
                mapOf(
                    "available" to false,
                    "reason" to "whisper.cpp model is missing at $whisperModelPath"
                )
            } else if (nativeLibraryLoadError != null) {
                mapOf(
                    "available" to false,
                    "reason" to "whisper.cpp runtime failed to load: $nativeLibraryLoadError"
                )
            } else {
                mapOf(
                    "available" to true,
                    "detail" to "whisper.cpp Android runtime is linked"
                )
            }
        val llamaModelPath = call.argument<String>("llamaModelPath").orEmpty()
        val llamaStatus =
            if (llamaModelPath.isNotEmpty() && !File(llamaModelPath).exists()) {
                mapOf(
                    "available" to false,
                    "reason" to "llama.cpp model is missing at $llamaModelPath"
                )
            } else if (llamaLibraryLoadError != null) {
                mapOf(
                    "available" to false,
                    "reason" to "llama.cpp runtime failed to load: $llamaLibraryLoadError"
                )
            } else {
                mapOf(
                    "available" to true,
                    "detail" to "llama.cpp Android runtime is linked"
                )
            }

        return mapOf(
            "whisperCpp" to whisperStatus,
            "llamaCpp" to llamaStatus
        )
    }

    private fun transcribeWithWhisperCpp(call: MethodCall): Map<String, Any?> {
        if (nativeLibraryLoadError != null) {
            throw IllegalStateException("whisper.cpp runtime failed to load: $nativeLibraryLoadError")
        }

        val modelPath = call.requiredString("modelPath")
        if (!File(modelPath).exists()) {
            throw IllegalArgumentException("Missing whisper.cpp model at $modelPath")
        }

        val pcm16Audio = call.argument<ByteArray>("pcm16Audio")
            ?: throw IllegalArgumentException("Missing PCM16 audio data")
        val sampleRate = call.argument<Int>("sampleRate") ?: 16000
        val languageCode = call.argument<String>("languageCode") ?: "zh"
        val text = transcribePcm16WithWhisper(
            modelPath,
            pcm16Audio,
            sampleRate,
            languageCode
        )
        return mapOf("text" to text)
    }

    private fun transcribeAudioFileWithWhisperCpp(call: MethodCall): Map<String, Any?> {
        if (nativeLibraryLoadError != null) {
            throw IllegalStateException("whisper.cpp runtime failed to load: $nativeLibraryLoadError")
        }

        val modelPath = call.requiredString("modelPath")
        if (!File(modelPath).exists()) {
            throw IllegalArgumentException("Missing whisper.cpp model at $modelPath")
        }

        val audioFilePath = call.requiredString("audioFilePath")
        if (!File(audioFilePath).exists()) {
            throw IllegalArgumentException("Missing audio file at $audioFilePath")
        }

        try {
            val languageCode = call.argument<String>("languageCode") ?: "zh"
            val pcm16Audio = decodeAudioFileToPcm16(audioFilePath)
            val text = transcribePcm16WithWhisper(
                modelPath,
                pcm16Audio,
                16000,
                languageCode
            )
            return mapOf("text" to text)
        } finally {
            removeImportedAudioIfNeeded(audioFilePath)
        }
    }

    private fun decodeAudioFileToPcm16(call: MethodCall): Map<String, Any?> {
        val audioFilePath = call.requiredString("audioFilePath")
        if (!File(audioFilePath).exists()) {
            throw IllegalArgumentException("Missing audio file at $audioFilePath")
        }

        return mapOf(
            "pcm16Audio" to decodeAudioFileToPcm16(audioFilePath),
            "sampleRate" to 16000
        )
    }

    private fun decodeAudioFileToPcm16(audioFilePath: String): ByteArray {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(audioFilePath)
            val trackIndex = (0 until extractor.trackCount).firstOrNull { index ->
                val mime = extractor.getTrackFormat(index).getString(MediaFormat.KEY_MIME)
                mime?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("No audio track found in selected file")

            extractor.selectTrack(trackIndex)
            val inputFormat = extractor.getTrackFormat(trackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)
                ?: throw IllegalArgumentException("Selected audio track has no MIME type")
            val decoder = MediaCodec.createDecoderByType(mime)
            return try {
                decoder.configure(inputFormat, null, null, 0)
                decoder.start()
                decodeSelectedTrack(extractor, decoder)
            } finally {
                runCatching { decoder.stop() }
                decoder.release()
            }
        } finally {
            extractor.release()
        }
    }

    private fun decodeSelectedTrack(
        extractor: MediaExtractor,
        decoder: MediaCodec
    ): ByteArray {
        val bufferInfo = MediaCodec.BufferInfo()
        val samples = FloatSamples()
        var inputDone = false
        var outputDone = false
        var outputSampleRate = 0
        var outputChannelCount = 0

        while (!outputDone) {
            if (!inputDone) {
                val inputBufferIndex = decoder.dequeueInputBuffer(10_000)
                if (inputBufferIndex >= 0) {
                    val inputBuffer = decoder.getInputBuffer(inputBufferIndex)
                        ?: throw IllegalStateException("Decoder returned no input buffer")
                    inputBuffer.clear()
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(
                            inputBufferIndex,
                            0,
                            0,
                            0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        )
                        inputDone = true
                    } else {
                        decoder.queueInputBuffer(
                            inputBufferIndex,
                            0,
                            sampleSize,
                            extractor.sampleTime,
                            0
                        )
                        extractor.advance()
                    }
                }
            }

            when (val outputBufferIndex = decoder.dequeueOutputBuffer(bufferInfo, 10_000)) {
                MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val outputFormat = decoder.outputFormat
                    outputSampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    outputChannelCount = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    val encoding = if (outputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        outputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                    } else {
                        android.media.AudioFormat.ENCODING_PCM_16BIT
                    }
                    if (encoding != android.media.AudioFormat.ENCODING_PCM_16BIT) {
                        throw IllegalArgumentException("Unsupported decoded PCM encoding: $encoding")
                    }
                }
                else -> {
                    if (outputBufferIndex >= 0) {
                        val outputBuffer = decoder.getOutputBuffer(outputBufferIndex)
                            ?: throw IllegalStateException("Decoder returned no output buffer")
                        if (bufferInfo.size > 0) {
                            if (outputSampleRate == 0 || outputChannelCount == 0) {
                                val outputFormat = decoder.outputFormat
                                outputSampleRate = outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                                outputChannelCount = outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            }
                            appendPcm16Samples(
                                outputBuffer,
                                bufferInfo.offset,
                                bufferInfo.size,
                                outputChannelCount,
                                samples
                            )
                        }
                        outputDone =
                            (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        decoder.releaseOutputBuffer(outputBufferIndex, false)
                    }
                }
            }
        }

        if (outputSampleRate <= 0 || samples.size == 0) {
            throw IllegalArgumentException("Selected audio did not decode to PCM samples")
        }
        return resampleToPcm16(samples.toArray(), outputSampleRate, 16000)
    }

    private fun appendPcm16Samples(
        source: ByteBuffer,
        offset: Int,
        size: Int,
        channelCount: Int,
        destination: FloatSamples
    ) {
        require(channelCount > 0) { "Invalid audio channel count: $channelCount" }

        val buffer = source.duplicate().order(ByteOrder.LITTLE_ENDIAN)
        buffer.position(offset)
        buffer.limit(offset + size)
        val bytesPerFrame = channelCount * 2
        val frameCount = buffer.remaining() / bytesPerFrame
        for (frame in 0 until frameCount) {
            var sum = 0
            for (channel in 0 until channelCount) {
                val sampleOffset = offset + frame * bytesPerFrame + channel * 2
                sum += buffer.getShort(sampleOffset).toInt()
            }
            destination.add((sum / channelCount).toFloat() / 32768.0f)
        }
    }

    private fun resampleToPcm16(
        samples: FloatArray,
        sourceSampleRate: Int,
        targetSampleRate: Int
    ): ByteArray {
        if (samples.isEmpty()) {
            return ByteArray(0)
        }

        val outputFrameCount =
            (samples.size * targetSampleRate.toDouble() / sourceSampleRate).roundToInt()
                .coerceAtLeast(1)
        val output = ByteArrayOutputStream(outputFrameCount * 2)
        val step = sourceSampleRate.toDouble() / targetSampleRate.toDouble()

        for (index in 0 until outputFrameCount) {
            val sourcePosition = index * step
            val low = sourcePosition.toInt().coerceIn(0, samples.lastIndex)
            val high = (low + 1).coerceAtMost(samples.lastIndex)
            val fraction = (sourcePosition - low).toFloat()
            val value = samples[low] + (samples[high] - samples[low]) * fraction
            val intSample = (value.coerceIn(-1.0f, 1.0f) * 32767.0f)
                .roundToInt()
                .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            output.write(intSample and 0xff)
            output.write((intSample shr 8) and 0xff)
        }

        return output.toByteArray()
    }

    private fun removeImportedAudioIfNeeded(audioFilePath: String) {
        val file = File(audioFilePath)
        if (file.parentFile?.name == "ImportedAudio") {
            file.delete()
        }
    }

    private fun flutterAssetKey(assetDirectory: String, fileName: String): String {
        val normalizedDirectory = assetDirectory.trim('/')
        val normalizedFileName = fileName.trim('/')
        val assetPath = "$normalizedDirectory/$normalizedFileName"
        return FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(assetPath)
    }

    private fun assetExists(assetKey: String): Boolean {
        return try {
            assets.open(assetKey).use { true }
        } catch (_: Exception) {
            false
        }
    }

    private fun copyAsset(assetKey: String, destination: File) {
        destination.parentFile?.mkdirs()
        val temp = File(destination.parentFile, "${destination.name}.installing")

        if (temp.exists()) {
            temp.delete()
        }

        try {
            assets.open(assetKey).use { input ->
                temp.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            if (destination.exists()) {
                destination.delete()
            }
            if (!temp.renameTo(destination)) {
                throw IllegalStateException("Unable to move ${temp.absolutePath} to ${destination.absolutePath}")
            }
        } catch (error: Exception) {
            temp.delete()
            throw IllegalStateException("Missing bundled asset $assetKey", error)
        }
    }

    private fun MethodCall.requiredString(key: String): String {
        val value = argument<String>(key)?.trim()
        require(!value.isNullOrEmpty()) { "Missing $key" }
        return value
    }

    private fun MethodCall.requiredStringList(key: String): List<String> {
        val value = argument<List<String>>(key)
        require(!value.isNullOrEmpty()) { "Missing $key" }
        return value
    }

    private fun sanitizeFileName(name: String): String {
        return name.replace(Regex("""[^\w.\-()\u4e00-\u9fff ]"""), "_")
            .ifBlank { "audio" }
    }

    companion object {
        private val nativeLibraryLoadError: String? = runCatching {
            System.loadLibrary("local_meeting_asr")
        }.exceptionOrNull()?.message
        private val llamaLibraryLoadError: String? = runCatching {
            System.loadLibrary("llama")
        }.exceptionOrNull()?.message
    }
}

private class FloatSamples(initialCapacity: Int = 16384) {
    private var values = FloatArray(initialCapacity)
    var size = 0
        private set

    fun add(value: Float) {
        if (size == values.size) {
            values = values.copyOf(values.size * 2)
        }
        values[size] = value
        size += 1
    }

    fun toArray(): FloatArray = values.copyOf(size)
}

private data class ImportedAudioFile(
    val file: File,
    val name: String
)
