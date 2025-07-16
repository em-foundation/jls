#include <napi.h>
extern "C" {
    #include "jls/writer.h"
}

class JlsWriter : public Napi::ObjectWrap<JlsWriter> {
public:
    static Napi::Object Init(Napi::Env env, Napi::Object exports) {
        Napi::Function func = DefineClass(env, "JlsWriter", {
            InstanceMethod("close", &JlsWriter::Close),
            InstanceMethod("sourceDef", &JlsWriter::SourceDef)
        });

        exports.Set("JlsWriter", func);
        return exports;
    }

    JlsWriter(const Napi::CallbackInfo& info) : Napi::ObjectWrap<JlsWriter>(info) {
        std::string path = info[0].As<Napi::String>();
        jls_wr_open(&this->writer_, path.c_str());
    }

    ~JlsWriter() {
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

    Napi::Value SourceDef(const Napi::CallbackInfo& info) {
        Napi::Env env = info.Env();
        if (info.Length() < 1 || !info[0].IsObject())
            Napi::TypeError::New(env, "Expected (sourceDef)").ThrowAsJavaScriptException();

        Napi::Object obj = info[0].As<Napi::Object>();
        jls_source_def_s src = {};
        src.source_id = obj.Get("source_id").As<Napi::Number>().Uint32Value();
        src.name = obj.Get("name").As<Napi::String>().Utf8Value().c_str();
        src.vendor = obj.Get("vendor").As<Napi::String>().Utf8Value().c_str();
        src.model = obj.Get("model").As<Napi::String>().Utf8Value().c_str();
        src.version = obj.Get("version").As<Napi::String>().Utf8Value().c_str();
        src.serial_number = obj.Get("serial_number").As<Napi::String>().Utf8Value().c_str();
        int32_t result = jls_wr_source_def(this->writer_, &src);
        return Napi::Number::New(env, result);
    }

    jls_wr_s* writer_ = nullptr;
};

Napi::Object InitAll(Napi::Env env, Napi::Object exports) {
    return JlsWriter::Init(env, exports);
}

NODE_API_MODULE(node_jls, InitAll)
