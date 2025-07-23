declare namespace Jls {
    type SourceDef = {
        source_id: number
        name: string
        vendor: string
        model: string
        version: string
        serial_number: string
    }
    type SignalDef = {
        signal_id: number
        source_id: number
        signal_type: number
        data_type: number
        sample_rate: number
        samples_per_data: number
        sample_decimate_factor: number
        entries_per_summary: number
        summary_decimate_factor: number
        annotation_decimate_factor: number
        utc_decimate_factor: number
        sample_id_offset: bigint
        name: string
        units: string
    }
    class Writer {
        constructor(path: string)
        sourceDef(def: SourceDef): number
        signalDef(def: SignalDef): number
        writeF32(signal_id: number, data: Float32Array): number
        close(): number
    }
}

export = Jls
