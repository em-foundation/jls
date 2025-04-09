# Copyright 2021-2025 Jetperch LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Python binding for the native JLS implementation.
"""

# See https://cython.readthedocs.io/en/latest/index.html

# cython: boundscheck=True, wraparound=True, nonecheck=True, overflowcheck=True, cdivision=True

from libc.stdint cimport uint8_t, uint16_t, uint32_t, uint64_t, int32_t, int64_t
from libc.float cimport DBL_MAX
from libc.math cimport isfinite, NAN

from collections.abc import Iterable, Mapping
import json
import logging
import numpy as np
import time
cimport numpy as np
from . cimport c_jls
from .structs import SourceDef, SignalDef


__all__ = ['DataType', 'AnnotationType', 'SignalType', 'Writer', 'Reader',
           'TimeMap',
           'SourceDef', 'SignalDef', 'SummaryFSR', 'jls_inject_log',
           'copy',
           'data_type_as_enum', 'data_type_as_str']


_log_c_name = 'pyjls.c'
_log_c = logging.getLogger(_log_c_name)
# _UTC_OFFSET = dateutil.parser.parse('2018-01-01T00:00:00Z').timestamp()
_UTC_OFFSET = 1514764800  # seconds
SECOND = 1 << 30
DEF _JLS_SIGNAL_COUNT = 256  # From jls/format.h


def _data_type_def(basetype, size, q):
    return (basetype & 0x0f) | ((size & 0xff) << 8) | ((q & 0xff) << 16)


class _DataTypeBase:
    INT       = 0x01
    UNSIGNED  = 0x02
    UINT      = 0x03
    FLOAT     = 0x04


class DataType:
    """The signal data type enumeration.

    unsigned integers: U1, U4, U8, U16, U32, U64
    signed integer: I4, I8, I16, I32, I64
    floating point: F32, F64
    """
    U1 = _data_type_def(_DataTypeBase.UINT, 1, 0)
    U4 = _data_type_def(_DataTypeBase.UINT, 4, 0)
    U8 = _data_type_def(_DataTypeBase.UINT, 8, 0)
    U16 = _data_type_def(_DataTypeBase.UINT, 16, 0)
    U32 = _data_type_def(_DataTypeBase.UINT, 32, 0)
    U64 = _data_type_def(_DataTypeBase.UINT, 64, 0)

    I4 = _data_type_def(_DataTypeBase.INT, 4, 0)
    I8 = _data_type_def(_DataTypeBase.INT, 8, 0)
    I16 = _data_type_def(_DataTypeBase.INT, 16, 0)
    I32 = _data_type_def(_DataTypeBase.INT, 32, 0)
    I64 = _data_type_def(_DataTypeBase.INT, 64, 0)

    F32 = _data_type_def(_DataTypeBase.FLOAT, 32, 0)
    F64 = _data_type_def(_DataTypeBase.FLOAT, 64, 0)


_data_type_map = {
    DataType.U1: np.uint8,      # packed
    DataType.U4: np.uint8,      # packed
    DataType.U8: np.uint8,
    DataType.U16: np.uint16,
    DataType.U32: np.uint32,
    DataType.U64: np.uint64,

    DataType.I4: np.uint8,      # packed
    DataType.I8: np.int8,
    DataType.I16: np.int16,
    DataType.I32: np.int32,
    DataType.I64: np.int64,

    DataType.F32: np.float32,
    DataType.F64: np.float64,
}


_data_type_as_enum = {
    'u1': DataType.U1,
    'u4': DataType.U4,
    'u8': DataType.U8,
    'u16': DataType.U16,
    'u32': DataType.U32,
    'u64': DataType.U64,

    'i4': DataType.I4,
    'i8': DataType.I8,
    'i16': DataType.I16,
    'i32': DataType.I32,
    'i64': DataType.I64,

    'f32': DataType.F32,
    'f64': DataType.F64,
}


_data_type_as_str = {}


def _populate_data_type():
    for key, value in list(_data_type_as_enum.items()):
        _data_type_as_enum[value] = value
        _data_type_as_str[value] = key
        _data_type_as_str[key] = key


_populate_data_type()


def data_type_as_enum(data_type):
    return _data_type_as_enum[data_type]


def data_type_as_str(data_type):
    return _data_type_as_str[data_type]


class AnnotationType:
    """The annotation type enumeration."""
    USER = c_jls.JLS_ANNOTATION_TYPE_USER
    TEXT = c_jls.JLS_ANNOTATION_TYPE_TEXT
    VMARKER = c_jls.JLS_ANNOTATION_TYPE_VERTICAL_MARKER
    HMARKER = c_jls.JLS_ANNOTATION_TYPE_HORIZONTAL_MARKER


_annotation_map = {
    'user': AnnotationType.USER,
    'usr': AnnotationType.USER,
    'text': AnnotationType.TEXT,
    'txt': AnnotationType.TEXT,
    'str': AnnotationType.TEXT,
    'string': AnnotationType.TEXT,
    'marker': AnnotationType.VMARKER,
    'vertical_marker': AnnotationType.VMARKER,
    'vmarker': AnnotationType.VMARKER,
    'horizontal_marker': AnnotationType.HMARKER,
    'hmarker': AnnotationType.HMARKER,
}

_log_level_map = {
    '!': logging.CRITICAL,
    'A': logging.CRITICAL,
    'C': logging.CRITICAL,
    'E': logging.ERROR,
    'W': logging.WARNING,
    'N': logging.INFO,
    'I': logging.INFO,
    'D': logging.DEBUG,
    'D': logging.DEBUG,
    'D': logging.DEBUG,
}


class SignalType:
    """The signal type enumeration."""
    FSR = c_jls.JLS_SIGNAL_TYPE_FSR
    VSR = c_jls.JLS_SIGNAL_TYPE_VSR


class SummaryFSR:
    """The FSR column enumeration."""
    MEAN = c_jls.JLS_SUMMARY_FSR_MEAN
    STD = c_jls.JLS_SUMMARY_FSR_STD
    MIN = c_jls.JLS_SUMMARY_FSR_MIN
    MAX = c_jls.JLS_SUMMARY_FSR_MAX
    COUNT = c_jls.JLS_SUMMARY_FSR_COUNT


cdef void _log_cbk(const char * msg) noexcept nogil:
    with gil:
        m = msg.decode('utf-8').strip()
        level, location, s = m.split(' ', 2)
        lvl = _log_level_map.get(level, logging.DEBUG)
        filename, line, _ = location.split(':')
        record = logging.LogRecord(_log_c_name, lvl, filename, int(line), s, None, None)
        _log_c.handle(record)


c_jls.jls_log_register(_log_cbk)


def jls_inject_log(level, filename, line, msg):
    cdef char * c_msg
    location = ':'.join([filename, str(line), ''])
    msg = ' '.join([level, location, msg]).encode('utf-8')
    c_msg = msg
    c_jls.jls_log_printf('%s\n'.encode('utf-8'), c_msg)


def _encode_str(s):
    if s is None:
        s = ''
    return s.encode('utf-8') + b'\x00'


def _storage_pack(data):
    if data is None:
        return c_jls.JLS_STORAGE_TYPE_BINARY, b'', 0
    elif isinstance(data, str):
        s = _encode_str(data)
        return c_jls.JLS_STORAGE_TYPE_STRING, s, len(s)
    elif isinstance(data, bytes):
        return c_jls.JLS_STORAGE_TYPE_BINARY, data, len(data)
    else:
        s = _encode_str(json.dumps(data))
        return c_jls.JLS_STORAGE_TYPE_JSON, s, len(s)


cdef _storage_unpack(uint8_t storage_type, const uint8_t * data, uint32_t data_size):
    cdef const char * str = <const char *> data
    if storage_type == c_jls.JLS_STORAGE_TYPE_STRING:
        return str[:data_size - 1].decode('utf-8')
    elif storage_type == c_jls.JLS_STORAGE_TYPE_BINARY:
        return data[:data_size]
    else:
        return json.loads(str[:data_size - 1].decode('utf-8'))


def utc_to_jls(utc):
    """Convert from python UTC timestamp to jls timestamp."""
    return int((utc - _UTC_OFFSET) * SECOND)


def jls_to_utc(timestamp):
    """Convert from jls timestamp to python UTC timestamp.

    :param timestamp: The JLS timestamp.
    :return: The python UTC timestamp.

    Note that python timestamps usually have lower resolution than
    the JLS timestamps.  When full resolution is required,
    use relative JLS timestamp offsets to maintain precision.
    """
    return (timestamp / SECOND) + _UTC_OFFSET


def _handle_rc(name, rc):
    if rc == 0:
        return
    rc_name = c_jls.jls_error_code_name(rc).decode('utf-8')
    rc_descr = c_jls.jls_error_code_description(rc).decode('utf-8')
    raise RuntimeError(f'{name} {rc_name}[{rc}]: {rc_descr}')


cdef class Writer:
    """Create a new JLS writer.

    :param path: The output JLS file path.
    """
    cdef c_jls.jls_twr_s * _wr
    cdef c_jls.jls_signal_def_s _signals[_JLS_SIGNAL_COUNT]

    FLAG_DROP_ON_OVERFLOW = c_jls.JLS_TWR_FLAG_DROP_ON_OVERFLOW

    def __init__(self, path: str):
        cdef c_jls.jls_twr_s ** wr_ptr = &self._wr
        cdef int32_t rc
        cdef const uint8_t[:] path_u8
        path_bytes = path.encode('utf-8')
        path_u8 = path_bytes
        self._signals[0].signal_type = c_jls.JLS_SIGNAL_TYPE_VSR
        with nogil:
            rc = c_jls.jls_twr_open(wr_ptr, <char *> &path_u8[0])
        _handle_rc('open', rc)

    def __enter__(self):
        return self

    def __exit__(self, type, value, traceback):
        self.close()

    @property
    def flags(self):
        cdef c_jls.jls_twr_s * wr = self._wr
        return c_jls.jls_twr_flags_get(wr)

    @flags.setter
    def flags(self, value):
        cdef c_jls.jls_twr_s * wr = self._wr
        c_jls.jls_twr_flags_set(wr, value)

    def close(self):
        """Close the JLS file and release all resources."""
        cdef c_jls.jls_twr_s * wr = self._wr
        with nogil:
            c_jls.jls_twr_close(wr)

    def flush(self):
        """Flush any pending data to the JLS file."""
        cdef c_jls.jls_twr_s * wr = self._wr
        with nogil:
            c_jls.jls_twr_flush(wr)

    def source_def(self, source_id, name=None, vendor=None, model=None, version=None, serial_number=None):
        """Define a source."""
        cdef int32_t rc
        cdef c_jls.jls_source_def_s s
        name_b = _encode_str(name)
        vendor_b = _encode_str(vendor)
        model_b = _encode_str(model)
        version_b = _encode_str(version)
        serial_number_b = _encode_str(serial_number)
        s.source_id = source_id
        s.name = name_b
        s.vendor = vendor_b
        s.model = model_b
        s.version = version_b
        s.serial_number = serial_number_b
        rc = c_jls.jls_twr_source_def(self._wr, &s)
        _handle_rc('source_def', rc)

    def source_def_from_struct(self, s: SourceDef):
        """Define a source."""
        return self.source_def(s.source_id,
                               name=s.name,
                               vendor=s.vendor,
                               model=s.model,
                               version=s.version,
                               serial_number=s.serial_number)

    def signal_def(self, signal_id, source_id, signal_type=None, data_type=None, sample_rate=None,
                   samples_per_data=None, sample_decimate_factor=None, entries_per_summary=None,
                   summary_decimate_factor=None, annotation_decimate_factor=None, utc_decimate_factor=None,
                   name=None, units=None):
        """Define a signal."""
        cdef int32_t rc
        cdef c_jls.jls_signal_def_s * s
        s = &self._signals[signal_id]
        if data_type is None:
            data_type = DataType.F32
        elif isinstance(data_type, str):
            data_type = _data_type_as_enum[data_type]
        s.signal_id = signal_id
        s.source_id = source_id
        s.signal_type = 0 if signal_type is None else int(signal_type)
        s.data_type = data_type
        s.sample_rate = 0 if sample_rate is None else int(sample_rate)
        s.samples_per_data = 0 if samples_per_data is None else int(samples_per_data)
        s.sample_decimate_factor = 0 if sample_decimate_factor is None else int(sample_decimate_factor)
        s.entries_per_summary = 0 if entries_per_summary is None else int(entries_per_summary)
        s.summary_decimate_factor = 0 if summary_decimate_factor is None else int(summary_decimate_factor)
        s.annotation_decimate_factor = 0 if annotation_decimate_factor is None else int(annotation_decimate_factor)
        s.utc_decimate_factor = 0 if utc_decimate_factor is None else int(utc_decimate_factor)
        name_b = _encode_str(name)
        units_b = _encode_str(units)
        s.name = name_b
        s.units = units_b
        rc = c_jls.jls_twr_signal_def(self._wr, s)
        _handle_rc('signal_def', rc)

    def signal_def_from_struct(self, s: SignalDef):
        """Define a signal."""
        return self.signal_def(s.signal_id,
                               s.source_id,
                               signal_type=s.signal_type,
                               data_type=s.data_type,
                               sample_rate=s.sample_rate,
                               samples_per_data=s.samples_per_data,
                               sample_decimate_factor=s.sample_decimate_factor,
                               entries_per_summary=s.entries_per_summary,
                               summary_decimate_factor=s.summary_decimate_factor,
                               annotation_decimate_factor=s.annotation_decimate_factor,
                               utc_decimate_factor=s.utc_decimate_factor,
                               name=s.name,
                               units=s.units)

    def user_data(self, chunk_meta, data):
        """Add user data to the file.

        :param chunk_meta: The arbitrary u16 metadata value.
        :param data: The bytes to store.
        :raise: On error.
        """
        cdef int32_t rc
        cdef uint16_t chunk_meta_u16 = chunk_meta
        cdef c_jls.jls_storage_type_e storage_type
        cdef const uint8_t[:] payload_u8
        cdef const uint8_t * payload_u8_ptr = NULL
        cdef uint32_t payload_length
        cdef c_jls.jls_twr_s * wr = self._wr
        storage_type, payload_bytes, payload_length = _storage_pack(data)
        payload_u8 = payload_bytes
        if 0 != payload_length:
            payload_u8_ptr = &payload_u8[0]
        with nogil:
            rc = c_jls.jls_twr_user_data(wr, chunk_meta_u16, storage_type, payload_u8_ptr, payload_length)

        _handle_rc('user_data', rc)

    def fsr_f32(self, signal_id, sample_id, data):
        """Add 32-bit floating-point FSR data to a signal.

        :param signal_id: The signal id for the data.
        :param sample_id: The sample id for the first sample in data.
        :param data: The 32-bit floating point data to add.
        """
        return self.fsr(signal_id, sample_id, data)

    def fsr(self, signal_id, sample_id, data):
        """Add FSR data to a signal.

        :param signal_id: The signal id for the data.
        :param sample_id: The sample id for the first sample in data.
        :param data: The data to add.
        :raise: On error.
        """
        cdef c_jls.jls_twr_s * wr = self._wr
        cdef uint16_t signal_id_u16 = signal_id
        cdef int64_t sample_id_i64 = sample_id
        cdef int32_t rc
        cdef np.uint8_t [::1] u8
        cdef uint32_t data_type
        cdef uint32_t entry_size_bits
        cdef uint32_t length

        data_type = self._signals[signal_id].data_type
        entry_size_bits = (data_type >> 8) & 0xff
        np_type = _data_type_map[data_type & 0xffff]
        if np_type != data.dtype:
            raise ValueError(f'Data type mismatch {data.dtype} != {np_type}')
        data_u8 = data.view(dtype=np.uint8)
        u8 = data_u8
        length = len(data)
        if entry_size_bits == 4:
            length *= 2
        elif entry_size_bits == 1:
            length *= 8
        with nogil:
            rc = c_jls.jls_twr_fsr(wr, signal_id_u16, sample_id_i64, &u8[0], length)
        _handle_rc('fsr', rc)

    def fsr_omit_data(self, signal_id, enable):
        cdef c_jls.jls_twr_s * wr = self._wr
        cdef uint16_t signal_id_u16 = signal_id
        cdef uint32_t enable_u32 = 0 if bool(enable) else 1
        cdef int32_t rc
        rc = c_jls.jls_twr_fsr_omit_data(wr, signal_id_u16, enable_u32)
        _handle_rc('fsr_omit_data', rc)

    def annotation(self, signal_id, timestamp, y, annotation_type, group_id, data):
        """Add an annotation to a signal.

        :param signal_id: The signal id.
        :param timestamp: The x-axis timestamp in sample_id for FSR and UTC for VSR.
        :param y: The y-axis value or NAN to automatically position.
        :param annotation_type: The annotation type.
        :param group_id: The optional group identifier.  If unused, set to 0.
        :param data: The data for the annotation.
        :raise: On error.
        """
        cdef c_jls.jls_twr_s * wr = self._wr
        cdef uint16_t signal_id_u16 = signal_id
        cdef int64_t timestamp_i64 = timestamp
        cdef uint8_t group_id_u8 = group_id
        cdef float y_f32
        cdef c_jls.jls_annotation_type_e annotation_type_e
        cdef c_jls.jls_storage_type_e storage_type
        cdef const uint8_t[:] payload_u8
        cdef uint32_t payload_length
        cdef int32_t rc

        if y is None:
            y_f32 = NAN
        else:
            y_f32 = y
        if isinstance(annotation_type, str):
            annotation_type = _annotation_map[annotation_type.lower()]
        annotation_type_e = annotation_type
        storage_type, payload, payload_length = _storage_pack(data)
        payload_u8 = payload
        if y is None or not np.isfinite(y):
            y = NAN
        with nogil:
            rc = c_jls.jls_twr_annotation(wr, signal_id_u16, timestamp_i64, y_f32,
                annotation_type_e,
                group_id_u8, storage_type, &payload_u8[0], payload_length)
        _handle_rc('annotation', rc)

    def utc(self, signal_id, sample_id, utc_i64):
        """Add a mapping from sample_id to UTC timestamp for an FSR signal.
        :param signal_id: The signal id.
        :param sample_id: The sample_id for FSR.
        :param utc: The UTC timestamp.
        :raise: On error.
        """
        cdef c_jls.jls_twr_s * wr = self._wr
        cdef uint16_t signal_id_u16 = signal_id
        cdef int64_t sample_id_i64 = sample_id
        cdef int64_t utc_i64c = utc_i64
        cdef int32_t rc
        with nogil:
            rc = c_jls.jls_twr_utc(wr, signal_id_u16, sample_id_i64, utc_i64c)
        _handle_rc('utc', rc)


cdef class AnnotationCallback:
    cdef uint8_t is_fsr
    cdef object cbk_fn

    def __init__(self, is_fsr, cbk_fn):
        self.is_fsr = is_fsr
        self.cbk_fn = cbk_fn


_TIME_MAP_GET_DTYPE = np.dtype({
    'names': ['sample_id', 'timestamp'],
    'formats': ['u8', 'i8']
})


cdef class Reader:
    """Open a JLS v2 file for reading.

    :param path: The path to the JLS file.
    """
    cdef c_jls.jls_rd_s * _rd
    cdef object _sources
    cdef object _signals

    def __init__(self, path: str):
        cdef int32_t rc
        cdef c_jls.jls_source_def_s * sources
        cdef c_jls.jls_signal_def_s * signals
        cdef uint16_t count
        cdef int64_t samples
        self._sources: Mapping[int, SourceDef] = {}
        self._signals: Mapping[int, SignalDef] = {}
        rc = c_jls.jls_rd_open(&self._rd, path.encode('utf-8'))
        _handle_rc('open', rc)

        rc = c_jls.jls_rd_sources(self._rd, &sources, &count)
        _handle_rc('rd_sources', rc)
        for i in range(count):
            source_def = SourceDef(
                source_id=sources[i].source_id,
                name=sources[i].name.decode('utf-8'),
                vendor=sources[i].vendor.decode('utf-8'),
                model=sources[i].model.decode('utf-8'),
                version=sources[i].version.decode('utf-8'),
                serial_number=sources[i].serial_number.decode('utf-8'))
            self._sources[sources[i].source_id] = source_def

        rc = c_jls.jls_rd_signals(self._rd, &signals, &count)
        _handle_rc('rd_signals', rc)
        for i in range(count):
            signal_id = signals[i].signal_id
            signal_def = SignalDef(
                signal_id=signal_id,
                source_id=signals[i].source_id,
                signal_type=signals[i].signal_type,
                data_type=signals[i].data_type,
                sample_rate=signals[i].sample_rate,
                samples_per_data=signals[i].samples_per_data,
                sample_decimate_factor=signals[i].sample_decimate_factor,
                entries_per_summary=signals[i].entries_per_summary,
                summary_decimate_factor=signals[i].summary_decimate_factor,
                annotation_decimate_factor=signals[i].annotation_decimate_factor,
                utc_decimate_factor=signals[i].utc_decimate_factor,
                sample_id_offset=signals[i].sample_id_offset,
                name=signals[i].name.decode('utf-8'),
                units=signals[i].units.decode('utf-8'))
            if signal_def.signal_type == c_jls.JLS_SIGNAL_TYPE_FSR:
                rc = c_jls.jls_rd_fsr_length(self._rd, signal_id, &samples)
                _handle_rc('rd_fsr_length', rc)
                signal_def.length = samples
            self._signals[signal_id] = signal_def

    def __enter__(self):
        return self

    def __exit__(self, type, value, traceback):
        self.close()

    def close(self):
        """Close the JLS file and free all resources."""
        c_jls.jls_rd_close(self._rd)

    @property
    def sources(self) -> Mapping[int, SourceDef]:
        """Return the dict mapping source_id to SourceDef."""
        return self._sources

    @property
    def signals(self) -> Mapping[int, SignalDef]:
        """Return the dict mapping signal_id to SignalDef."""
        return self._signals

    def source_lookup(self, spec) -> SourceDef:
        """Look up a source.

        :param spec: The source specification as one of:
            * source name (str).
            * source id (numeric or str convertable using int())
        :return: The source definition:
        :raise ValueError: If not found.
        """
        try:
            for s in self._sources.values():
                if s.name == spec:
                    return s
        except Exception:
            pass
        try:
            return self._sources[int(spec)]
        except Exception:
            pass
        raise ValueError(f'signal_lookup failed for {spec}')

    def _signal_lookup_parts(self, source_spec, signal_spec) -> SignalDef:
        try:
            signal_id = int(signal_spec)
        except Exception:
            signal_id = None
        source = self.source_lookup(source_spec)
        for s in self._signals.values():
            if s.source_id == source.source_id and (s.name == signal_spec or s.signal_id == signal_id):
                return s
        raise ValueError(f'_signal_lookup_parts({source_spec}, {signal_spec}) failed')

    def _signal_lookup_str(self, spec: str) -> SignalDef:
        for s in self._signals.values():
            if s.name == spec:
                return s
        parts = spec.split('.')
        if len(parts) != 2:
            raise ValueError('_signal_lookup_str({spec}) could not split')
        return self._signal_lookup_parts(*parts)

    def signal_lookup(self, spec) -> SignalDef:
        """Look up a signal.

        :param spec: The signal specification as one of:
            * signal name (str)
            * signal id (numeric or str convertable using int())
            * '<source_name>.<signal_name>'
            * [<source_spec>, '<signal_name>']
        :return: The signal definition.
        :raise ValueError: If not found.
        """
        try:
            return self._signal_lookup_str(spec)
        except Exception:
            pass
        try:
            return self._signals[int(spec)]
        except Exception:
            pass
        try:
            return self._signal_lookup_parts(*spec)
        except Exception:
            pass
        raise ValueError(f'signal_lookup failed for {spec}')

    def fsr(self, signal_id, start_sample_id, length):
        """Read the FSR data.

        :param signal_id: The signal id.
        :param start_sample_id: The starting sample id to read.
        :param length: The number of samples to read.
        :return: The data, which varies depending upon the FSR data type.

            u1 and u4 data will be packed in little endian order.

            For u1, unpack with:
                np.unpackbits(y, bitorder='little')[:len(x)]

            For u4, unpack with
                d = np.empty(len(y) * 2, dtype=np.uint8)
                d[0::2] = np.bitwise_and(y, 0x0f)
                d[1::2] = np.bitwise_and(np.right_shift(y, 4), 0x0f)
        """

        cdef int32_t rc
        cdef np.uint8_t [::1] u8
        cdef uint32_t data_type
        cdef uint32_t entry_size_bits
        cdef uint32_t u8_length
        cdef uint16_t signal_id_u16 = signal_id
        cdef int64_t start_sample_id_i64 = start_sample_id
        cdef int64_t length_i64 = length

        data_type = self._signals[signal_id].data_type
        entry_size_bits = (data_type >> 8) & 0xff
        np_type = _data_type_map[data_type & 0xffff]
        u8_length = length
        if entry_size_bits == 4:
            u8_length = (length + 1) // 2
        elif entry_size_bits == 1:
            u8_length = (length + 7) // 8
        else:
            u8_length *= entry_size_bits // 8

        data_u8 = np.empty(u8_length, dtype=np.uint8)
        data = data_u8.view(dtype=np_type)
        u8 = data_u8
        with nogil:
            rc = c_jls.jls_rd_fsr(self._rd, signal_id_u16, start_sample_id_i64, &u8[0], length_i64)
        _handle_rc('rd_fsr', rc)
        return data

    def fsr_statistics(self, signal_id, start_sample_id, increment, length):
        """Read FSR statistics (mean, stdev, min, max).

        :param signal_id: The signal id for a fixed sampling rate (FSR) signal.
        :param start_sample_id: The starting sample id to read.
            The sample_id of the first recorded sample in a signal is 0.
        :param increment: The number of samples represented per return value.
        :param length: The number of return values to generate.
        :return: The 2-D array[summary][stat] of np.float32.
            * Each summary entry represents the statistics computed
              approximately over increment samples starting
              from start_sample_id + <index> * increment.
              It has length given by the length argument.
            * stat is length 4 with columns defined by SummaryFSR
              which are mean (average), standard deviation,
              minimum, and maximum.

        For length 1, the return statistics are sample-accurate.
        For larger lengths, the external boundaries for index 0 (first)
        and index -1 (last) are computed exactly.  The internal boundaries
        are approximated, perfect for waveform display, but perhaps not
        suitable for other use cases.  If you need sample accurate statistics
        over multiple increments, call this function repeatedly with length 1.
        """

        cdef int32_t rc
        cdef np.float64_t [:, :] c_data
        cdef uint16_t signal_id_u16 = signal_id
        cdef int64_t start_sample_id_i64 = start_sample_id
        cdef int64_t increment_i64 = increment
        cdef int64_t length_i64 = length

        data = np.empty((length, c_jls.JLS_SUMMARY_FSR_COUNT), dtype=np.float64)
        c_data = data
        with nogil:
            rc = c_jls.jls_rd_fsr_statistics(self._rd, signal_id_u16, start_sample_id_i64,
                                             increment_i64, &c_data[0, 0], length_i64)
        _handle_rc('rd_fsr_statistics', rc)
        return data

    def annotations(self, signal_id, timestamp, cbk_fn):
        """Read annotations from a signal.

        :param signal_id: The signal id.
        :param timestamp: The starting timestamp.  FSR uses sample_id.  VSR uses utc.
        :param cbk: The function(timestamp, y, annotation_type, group_id, data)
            to call for each annotation.  Return True to stop iteration over
            the annotations or False to continue iterating.
        """
        cdef int32_t rc
        is_fsr = self._signals[signal_id].signal_type == c_jls.JLS_SIGNAL_TYPE_FSR
        user_data = AnnotationCallback(is_fsr, cbk_fn)
        rc = c_jls.jls_rd_annotations(self._rd, signal_id, timestamp, _annotation_cbk_fn, <void *> user_data)
        _handle_rc('rd_annotations', rc)

    def user_data(self, cbk_fn):
        """Get the user data.

        :param cbk_fn: The callable(chunk_meta_u16, data) called for each
            user_data entry.  Return True to stop iterating over subsequent
            user data entries or False to continue iterating.
        """
        cdef int32_t rc
        rc = c_jls.jls_rd_user_data(self._rd, _user_data_cbk_fn, <void *> cbk_fn)
        _handle_rc('rd_user_data', rc)

    def utc(self, signal_id, sample_id, cbk_fn):
        """Read the sample_id / utc pairs from a FSR signal.

        :param signal_id: The signal id.
        :param sample_id: The starting sample_id.
        :param cbk: The function(entries)
            to call for each annotation.  Entries is an Nx2 numpy array of
            [sample_id, utc_timestamp].
            Return True to stop iteration over the annotations
            or False to continue iterating.
        """
        cdef int32_t rc
        rc = c_jls.jls_rd_utc(self._rd, signal_id, sample_id, _utc_cbk_fn, <void *> cbk_fn)
        _handle_rc(f'rd_utc({signal_id}, {sample_id})', rc)

    def time_map_length(self, signal_id):
        return c_jls.jls_rd_tmap_length(self._rd, signal_id)

    def sample_id_to_timestamp(self, signal_id, sample_id):
        """Convert sample_id to UTC timestamp for FSR signals.

        :param signal_id: The signal id.
        :param sample_id: The sample_id or iterable of sample_ids to convert.
        :return: The JLS timestamp corresponding to sample_id.
        :raise RuntimeError: on error.
        """
        cdef int64_t utc_timestamp
        if isinstance(sample_id, Iterable):
            sz = len(sample_id)
            result = np.empty(sz, dtype=np.int64)
            for idx, s in enumerate(sample_id):
                rc = c_jls.jls_rd_sample_id_to_timestamp(self._rd, signal_id, s, &utc_timestamp)
                _handle_rc('sample_id_to_timestamp', rc)
                result[idx] = utc_timestamp
            return result
        else:
            rc = c_jls.jls_rd_sample_id_to_timestamp(self._rd, signal_id, sample_id, &utc_timestamp)
            _handle_rc('sample_id_to_timestamp', rc)
            return utc_timestamp

    def timestamp_to_sample_id(self, signal_id, utc_timestamp):
        """Convert UTC timestamp to sample_id for FSR signals.

        :param signal_id: The signal id.
        :param utc_timestamp: The UTC timestamp to convert.
        :return: The sample_id corresponding to utc_timestamp.
        :raise RuntimeError: on error.
        """
        cdef int64_t sample_id
        if isinstance(utc_timestamp, Iterable):
            sz = len(utc_timestamp)
            result = np.empty(sz, dtype=np.uint64)
            for idx, t in enumerate(utc_timestamp):
                rc = c_jls.jls_rd_timestamp_to_sample_id(self._rd, signal_id, t, &sample_id)
                _handle_rc('jls_rd_timestamp_to_sample_id', rc)
                result[idx] = sample_id
            return result
        else:
            rc = c_jls.jls_rd_timestamp_to_sample_id(self._rd, signal_id, utc_timestamp, &sample_id)
            _handle_rc('timestamp_to_sample_id', rc)
            return sample_id

    def time_map_get(self, signal_id, index=None):
        """Get the time map data.

        :param signal_id: The signal id.
        :param index: The index for the time map which is one of:
            - None: return all time maps in the instance.
            - int index: Return only this index.
            - (int start_index, int end_index): Return this range.
              start_index is inclusive, end_index is exclusive.

        :return: Return an np.ndarray with the the named columns
            ['sample_id', 'timestamp'].
            Access as either a[0]['timestamp'] or a[0][1].
        """
        cdef c_jls.jls_utc_summary_entry_s time_map
        n = self.time_map_length(signal_id)
        if index is None:
            index = 0, n
        elif isinstance(index, Iterable):
            index = int(index[0]), int(index[1])
        else:
            index = int(index)
            if index < 0:
                index = n + index
            index = index, index + 1
        i0, i1 = index
        if i0 < 0:
            i0 = n + i0
        if i1 < 0:
            i1 = n + i1
        if i0 > i1:
            i0, i1 = 0, 0
        elif i1 > n:
            raise ValueError(f'index out of range: {index}')
        k = i1 - i0
        out = np.empty(k, dtype=_TIME_MAP_GET_DTYPE)
        for i in range(k):
            c_jls.jls_rd_tmap_get(self._rd, signal_id, i + i0, &time_map)
            out[i][0] = time_map.sample_id
            out[i][1] = time_map.timestamp
        return out


class TimeMap:
    """A time map class compatible with pyjoulescope_driver.TimeMap."""

    def __init__(self, reader, signal_id):
        self._reader = reader
        self._signal_id = signal_id

    def __len__(self):
        return self._reader.time_map_length(self._signal_id)

    def __enter__(self):
        return self

    def __exit__(self, type, value, traceback):
        pass

    def sample_id_to_timestamp(self, sample_id):
        return self._reader.sample_id_to_timestamp(self._signal_id, sample_id)

    def timestamp_to_sample_id(self, timestamp):
        return self._reader.timestamp_to_sample_id(self._signal_id, timestamp)

    def time_map_get(self, index=None):
        return self._reader.time_map_get(self._signal_id, index)


cdef int32_t _annotation_cbk_fn(void * user_data, const c_jls.jls_annotation_s * annotation) noexcept:
    obj: AnnotationCallback = <object> user_data
    data = _storage_unpack(annotation[0].storage_type, annotation[0].data, annotation[0].data_size)
    y = annotation[0].y
    timestamp = annotation[0].timestamp
    if not obj.is_fsr:
        timestamp = annotation[0].timestamp
    if not isfinite(y):
        y = None
    try:
        rc = obj.cbk_fn(timestamp, y, annotation[0].annotation_type, annotation[0].group_id, data)
    except Exception:
        logging.getLogger(__name__).exception('in annotation callback')
        return 1
    return 1 if bool(rc) else 0


cdef int32_t _user_data_cbk_fn(void * user_data, uint16_t chunk_meta, c_jls.jls_storage_type_e storage_type,
        uint8_t * data, uint32_t data_size) noexcept:
    cbk_fn = <object> user_data
    d = _storage_unpack(storage_type, data, data_size)
    rc = cbk_fn(chunk_meta, d)
    return 1 if bool(rc) else 0


cdef int32_t _utc_cbk_fn(void * user_data, const c_jls.jls_utc_summary_entry_s * utc, uint32_t size) noexcept:
    cdef uint32_t idx
    cbk_fn = <object> user_data
    entries = np.empty((size, 2), dtype=np.int64)
    for idx in range(size):
        entries[idx, 0] = utc[idx].sample_id
        entries[idx, 1] = utc[idx].timestamp
    rc = cbk_fn(entries)
    return 1 if bool(rc) else 0


cdef int32_t _copy_msg_fn(void * user_data, const char * msg) noexcept:
    cdef uint32_t idx
    try:
        cbk_fn = <object> user_data
        if callable(cbk_fn):
            return cbk_fn(msg)
        return 0
    except:
        return 1


cdef int32_t _copy_progress_fn(void * user_data, double progress) noexcept:
    cdef uint32_t idx
    try:
        cbk_fn = <object> user_data
        if callable(cbk_fn):
            return cbk_fn(progress)
        return 0
    except:
        return 1


def copy(src, dst, msg_fn=None, progress_fn=None):
    """Copy a JLS file.

    :param src: The source path.
    :param dst: The destination path.
    :param msg_fn: The optional function to call with status messages.
    :param progress_fn: The optional function to call with progress from 0.0 to 1.0.
    """
    cdef const char * c_src
    cdef const char * c_dst
    src_encode = src.encode('utf-8')
    dst_encode = dst.encode('utf-8')
    c_src = src_encode
    c_dst = dst_encode
    rc = c_jls.jls_copy(c_src, c_dst, _copy_msg_fn, <void *> msg_fn, _copy_progress_fn, <void *> progress_fn)
    if rc:
        raise RuntimeError(f'Could not copy: {rc}')
