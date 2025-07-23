import * as Jls from 'node_jls'
import * as Fs from 'fs'

const jlsfile = new Jls.Writer('output4.jls')

const sdef: Jls.SourceDef = {
    source_id: 1,
    name: 'mysource',
    vendor: 'emf',
    model: 'sim',
    version: '1.0',
    serial_number: '00000001',
}
jlsfile.sourceDef(sdef)

const f32 = new Float32Array(Fs.readFileSync('current.f32.bin').buffer)

const sigdef: Jls.SignalDef = {
    signal_id: 1,
    source_id: 1,
    signal_type: 0,
    data_type: 8196,
    sample_rate: 1_000_000,
    samples_per_data: f32.length,
    sample_decimate_factor: 1,
    entries_per_summary: 1,
    summary_decimate_factor: 1,
    annotation_decimate_factor: 100,
    utc_decimate_factor: 100,
    sample_id_offset: BigInt(0),
    name: 'current',
    units: 'A',
}
jlsfile.signalDef(sigdef)
jlsfile.writeF32(1, f32)
jlsfile.close()
