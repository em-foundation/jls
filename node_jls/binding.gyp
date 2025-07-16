{
    "targets": [
        {
            "target_name": "node_jls",
            "sources": [
                "binding.cc",
                "../src/backend_win.c",
                "../src/buffer.c",
                "../src/core.c",
                "../src/crc32c_sw.c",
                "../src/datatype.c",
                "../src/ec.c",
                "../src/log.c",
                "../src/raw.c",
                "../src/msg_ring_buffer.c",
                "../src/track.c",
                "../src/threaded_writer.c",
                "../src/wr_fsr.c",
                "../src/wr_ts.c",
                "../src/writer.c"
            ],
            "include_dirs": [
                "<!@(node -p \"require('node-addon-api').include\")",
                "../include",
                "../include_prv"
            ],
            "dependencies": [
                "<!(node -p \"require('node-addon-api').gyp\")"
            ],
            "defines": [
                "NODE_ADDON_API_CPP_EXCEPTIONS"
            ],
            "cflags_cc": [
                "-std=c++17"
            ]
        }
    ]
}