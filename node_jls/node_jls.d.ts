export interface SourceDef {
    source_id: number
    name: string
    vendor: string
    model: string
    version: string
    serial_number: string
}

export declare class Writer {
    constructor(filename: string)
    sourceDef(def: SourceDef): number
    close(): number
}
