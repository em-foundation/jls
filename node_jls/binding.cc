#include <napi.h>
extern "C" {
    #include "jls/writer.h"
}

class Writer : public Napi::ObjectWrap<Writer> {
public:
    static Napi::Object Init(Napi::Env env, Napi::Object exports) {
        Napi::Function func = DefineClass(env, "Writer", {
            InstanceMethod("close", &Writer::Close),
            InstanceMethod("signalDef", &Writer::SignalDef),
            InstanceMethod("sourceDef", &Writer::SourceDef),
            InstanceMethod("writeF32", &Writer::WriteF32),
        });

        exports.Set("Writer", func);
        return exports;
    }

    Writer(const Napi::CallbackInfo& info) : Napi::ObjectWrap<Writer>(info) {
        std::string path = info[0].As<Napi::String>();
        jls_wr_open(&this->writer_, path.c_str());
    }

    ~Writer() {
        if (writer_)
            jls_wr_close(writer_);
    }

private:

    Napi::Value Close(const Napi::CallbackInfo& info) {
        if (this->writer_) {
            jls_wr_close(this->writer_);
            this->writer_ = nullptr;
        }
        return info.Env().Undefined();
    }

    Napi::Value SignalDef(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        if (info.Length() < 1 || !info[0].IsObject())
            Napi::TypeError::New(env, "Expected signal definition object").ThrowAsJavaScriptException();

        Napi::Object obj = info[0].As<Napi::Object>();

        jls_signal_def_s sig = {};
        sig.signal_id = obj.Get("signal_id").As<Napi::Number>().Uint32Value();
        sig.source_id = obj.Get("source_id").As<Napi::Number>().Uint32Value();
        sig.signal_type = obj.Get("signal_type").As<Napi::Number>().Uint32Value();
        sig.data_type = obj.Get("data_type").As<Napi::Number>().Uint32Value();
        sig.sample_rate = obj.Get("sample_rate").As<Napi::Number>().Uint32Value();
        sig.samples_per_data = obj.Get("samples_per_data").As<Napi::Number>().Uint32Value();
        sig.sample_decimate_factor = obj.Get("sample_decimate_factor").As<Napi::Number>().Uint32Value();
        sig.entries_per_summary = obj.Get("entries_per_summary").As<Napi::Number>().Uint32Value();
        sig.summary_decimate_factor = obj.Get("summary_decimate_factor").As<Napi::Number>().Uint32Value();
        sig.annotation_decimate_factor = obj.Get("annotation_decimate_factor").As<Napi::Number>().Uint32Value();
        sig.utc_decimate_factor = obj.Get("utc_decimate_factor").As<Napi::Number>().Uint32Value();
        bool lossless;
        sig.sample_id_offset = obj.Get("sample_id_offset").As<Napi::BigInt>().Int64Value(&lossless);        
        std::string name = obj.Get("name").As<Napi::String>().Utf8Value();
        std::string units = obj.Get("units").As<Napi::String>().Utf8Value();
        sig.name = name.c_str();
        sig.units = units.c_str();

        int32_t result = jls_wr_signal_def(this->writer_, &sig);
        return Napi::Number::New(env, result);
    }

    Napi::Value SourceDef(const Napi::CallbackInfo& info) {

        Napi::Env env = info.Env();
        if (info.Length() < 1 || !info[0].IsObject())
            Napi::TypeError::New(env, "Expected (sourceDef)").ThrowAsJavaScriptException();

        Napi::Object obj = info[0].As<Napi::Object>();
        std::string name = obj.Get("name").As<Napi::String>().Utf8Value();
        std::string vendor = obj.Get("vendor").As<Napi::String>().Utf8Value();
        std::string model = obj.Get("model").As<Napi::String>().Utf8Value();
        std::string version = obj.Get("version").As<Napi::String>().Utf8Value();
        std::string serial_number = obj.Get("serial_number").As<Napi::String>().Utf8Value();

        jls_source_def_s src = {};
        src.source_id = obj.Get("source_id").As<Napi::Number>().Uint32Value();
        src.name = name.c_str();
        src.vendor = vendor.c_str();
        src.model = model.c_str();
        src.version = version.c_str();
        src.serial_number = serial_number.c_str();

        int32_t result = jls_wr_source_def(this->writer_, &src);
        return Napi::Number::New(env, result);
    }

    Napi::Value WriteF32(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();

        if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsTypedArray())
            Napi::TypeError::New(env, "Expected (signal_id, Float32Array)").ThrowAsJavaScriptException();

        uint16_t signal_id = info[0].As<Napi::Number>().Uint32Value();
        Napi::Float32Array arr = info[1].As<Napi::Float32Array>();

        int32_t result = jls_wr_fsr_f32(this->writer_,
                                        signal_id,
                                        0,
                                        arr.Data(),
                                        arr.ElementLength());

        return Napi::Number::New(env, result);
    }

    jls_wr_s* writer_ = nullptr;
};

Napi::Object InitAll(Napi::Env env, Napi::Object exports) {
    return Writer::Init(env, exports);
}

NODE_API_MODULE(node_jls, InitAll)
