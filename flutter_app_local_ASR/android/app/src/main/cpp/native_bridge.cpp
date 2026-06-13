#include <jni.h>

#include <cstdint>
#include <string>
#include <vector>

#include "whisper.h"

namespace {

std::string jstring_to_string(JNIEnv * env, jstring value) {
    if (value == nullptr) {
        return "";
    }

    const char * chars = env->GetStringUTFChars(value, nullptr);
    if (chars == nullptr) {
        return "";
    }

    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

void throw_runtime(JNIEnv * env, const std::string & message) {
    jclass exception_class = env->FindClass("java/lang/RuntimeException");
    if (exception_class != nullptr) {
        env->ThrowNew(exception_class, message.c_str());
    }
}

std::vector<float> pcm16_to_float32(JNIEnv * env, jbyteArray pcm16_audio) {
    const jsize byte_count = env->GetArrayLength(pcm16_audio);
    std::vector<jbyte> bytes(byte_count);
    env->GetByteArrayRegion(pcm16_audio, 0, byte_count, bytes.data());

    std::vector<float> samples;
    samples.reserve(static_cast<size_t>(byte_count / 2));

    for (jsize i = 0; i + 1 < byte_count; i += 2) {
        const auto lo = static_cast<uint8_t>(bytes[i]);
        const auto hi = static_cast<uint8_t>(bytes[i + 1]);
        const auto raw = static_cast<uint16_t>(lo | (hi << 8));
        const auto sample = static_cast<int16_t>(raw);
        samples.push_back(static_cast<float>(sample) / 32768.0f);
    }

    return samples;
}

std::string normalize_language(const std::string & language_code) {
    if (language_code.rfind("zh", 0) == 0 || language_code.rfind("ZH", 0) == 0) {
        return "zh";
    }
    if (language_code.rfind("en", 0) == 0 || language_code.rfind("EN", 0) == 0) {
        return "en";
    }
    return language_code.empty() ? "zh" : language_code;
}

} // namespace

extern "C" JNIEXPORT jstring JNICALL
Java_com_example_flutter_1app_MainActivity_transcribePcm16WithWhisper(
        JNIEnv * env,
        jobject,
        jstring model_path,
        jbyteArray pcm16_audio,
        jint sample_rate,
        jstring language_code) {
    if (model_path == nullptr) {
        throw_runtime(env, "Missing whisper.cpp model path");
        return nullptr;
    }
    if (pcm16_audio == nullptr) {
        throw_runtime(env, "Missing PCM16 audio data");
        return nullptr;
    }
    if (sample_rate != 16000) {
        throw_runtime(env, "whisper.cpp Android bridge expects 16 kHz PCM16 audio");
        return nullptr;
    }

    const std::string model = jstring_to_string(env, model_path);
    const std::string language = normalize_language(jstring_to_string(env, language_code));
    const std::vector<float> samples = pcm16_to_float32(env, pcm16_audio);
    if (samples.empty()) {
        return env->NewStringUTF("");
    }

    whisper_context_params context_params = whisper_context_default_params();
    context_params.use_gpu = false;
    context_params.flash_attn = false;

    whisper_context * context = whisper_init_from_file_with_params(model.c_str(), context_params);
    if (context == nullptr) {
        throw_runtime(env, "Failed to initialize whisper.cpp model");
        return nullptr;
    }

    whisper_full_params full_params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    full_params.n_threads = 2;
    full_params.print_progress = false;
    full_params.print_realtime = false;
    full_params.print_timestamps = false;
    full_params.no_timestamps = true;
    full_params.translate = false;
    full_params.language = language.c_str();

    const int decode_result = whisper_full(
        context,
        full_params,
        samples.data(),
        static_cast<int>(samples.size())
    );
    if (decode_result != 0) {
        whisper_free(context);
        throw_runtime(env, "whisper_full failed with code " + std::to_string(decode_result));
        return nullptr;
    }

    std::string text;
    const int segment_count = whisper_full_n_segments(context);
    for (int i = 0; i < segment_count; ++i) {
        const char * segment = whisper_full_get_segment_text(context, i);
        if (segment == nullptr || segment[0] == '\0') {
            continue;
        }
        if (!text.empty()) {
            text += "\n";
        }
        text += segment;
    }

    whisper_free(context);
    return env->NewStringUTF(text.c_str());
}
