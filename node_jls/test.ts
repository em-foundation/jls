import { Writer } from './node_jls'

const w = new Writer("output.jls")
w.sourceDef({
    source_id: 1,
    name: 'probe',
    vendor: 'em',
    model: 'tbd',
    version: '1.0',
    serial_number: '1234'
})

w.close()
