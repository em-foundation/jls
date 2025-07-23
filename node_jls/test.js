const { JlsWriter } = require('./build/Release/node_jls')
const fs = require('fs')

const w = new JlsWriter("output3.jls")

w.sourceDef({
    source_id: 1,
    name: 'probe',
    vendor: 'em',
    model: 'xyz',
    version: '2.3',
    serial_number: '5678'
})

const rc = w.signalDef({
    signal_id: 1,           // not 0
    source_id: 1,           // match defined source
    signal_type: 0,
    data_type: 8196,        // JLS_DATATYPE_F32
    sample_rate: 1_000_000,
    samples_per_data: 8192,
    sample_decimate_factor: 128,
    entries_per_summary: 640,
    summary_decimate_factor: 20,
    annotation_decimate_factor: 100,
    utc_decimate_factor: 100,
    sample_id_offset: BigInt(0),
    name: 'current',
    units: 'A'
})

const fbuf = fs.readFileSync('current.f32.bin')
const floats = new Float32Array(fbuf.buffer, fbuf.byteOffset, fbuf.length / 4)

w.writeF32(1, floats)

w.close()
