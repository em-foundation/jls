const { JlsWriter } = require('./build/Release/node_jls')

const w = new JlsWriter("output2.jls")

w.sourceDef({
    source_id: 1,
    name: 'probe',
    vendor: 'em',
    model: 'xyz',
    version: '2.3',
    serial_number: '1234'
})

w.close()
