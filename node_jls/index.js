const native = require('node-gyp-build')(__dirname)

module.exports = {
    Writer: native.JlsWriter
}
