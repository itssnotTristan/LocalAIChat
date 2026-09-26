package com.localai.local_ai_chat

import android.app.Activity
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Device TTS keeps voice replies usable before the optional Kokoro pack is installed. */
class SystemSpeechBridge(private val activity: Activity) {
    private var engine: TextToSpeech? = null
    private var ready = false
    private var pending: MethodChannel.Result? = null
    private var pendingText: String? = null
    private var pendingVoice = 5
    private var pendingRate = 1.0f
    private var utterance = 0

    init {
        engine = TextToSpeech(activity) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit
                    override fun onDone(utteranceId: String?) = finish(utteranceId, null)
                    override fun onError(utteranceId: String?) = finish(utteranceId, "Android speech playback failed.")
                })
                if (pendingText != null) begin()
            } else {
                val result = pending
                pending = null
                pendingText = null
                result?.error("tts_unavailable", "Android speech is unavailable on this device.", null)
            }
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speak" -> {
                stopCurrent()
                val text = call.argument<String>("text")?.trim().orEmpty()
                if (text.isEmpty()) {
                    result.success(null)
                    return
                }
                pending = result
                pendingText = text
                pendingVoice = call.argument<Int>("voice") ?: 5
                pendingRate = (call.argument<Number>("rate")?.toFloat() ?: 1.0f).coerceIn(0.5f, 2.0f)
                if (ready) begin()
            }
            "stop" -> {
                stopCurrent()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun begin() {
        val text = pendingText ?: return
        val tts = engine ?: return
        pendingText = null
        tts.setLanguage(Locale.US)
        val localEnglishVoices = tts.voices.orEmpty()
            .filter { !it.isNetworkConnectionRequired && it.locale.language == Locale.ENGLISH.language }
            .sortedBy { it.name }
        if (localEnglishVoices.isNotEmpty()) {
            val index = when (pendingVoice) { 5 -> 0; 6 -> 1; 9 -> 2; 2 -> 3; 4 -> 4; else -> 0 }
            tts.voice = localEnglishVoices[index % localEnglishVoices.size]
        }
        tts.setSpeechRate(pendingRate)
        val id = (++utterance).toString()
        if (tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, id) != TextToSpeech.SUCCESS) {
            val result = pending
            pending = null
            result?.error("tts_failed", "Android could not start speech playback.", null)
        }
    }

    private fun finish(id: String?, error: String?) {
        activity.runOnUiThread {
            if (id != utterance.toString()) return@runOnUiThread
            val result = pending
            pending = null
            if (error == null) result?.success(null)
            else result?.error("tts_failed", error, null)
        }
    }

    private fun stopCurrent() {
        utterance++
        engine?.stop()
        val result = pending
        pending = null
        pendingText = null
        result?.success(null)
    }

    fun close() {
        stopCurrent()
        engine?.shutdown()
        engine = null
    }
}
