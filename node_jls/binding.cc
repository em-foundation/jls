extern "C" {
    #include "../include/jls/writer.h"
}
#include <napi.h>

Napi::Value Hello(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    return Napi::String::New(env, "hello");
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("hello", Napi::Function::New(env, Hello));
    return exports;
}

NODE_API_MODULE(NODE_GYP_MODULE_NAME, Init)
