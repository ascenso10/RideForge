#!/usr/bin/env python3
"""
Ride Forge FIT file simulator / rewriter.

Two modes:
  1. Rewrite a broken .fit file with the corrected structure
     (fixes timestamps, message ordering, adds distance from speed)
       python fit_rewrite.py --input broken.fit --output fixed.fit

  2. Generate a synthetic test .fit file (no input file needed)
       python fit_rewrite.py --output test.fit --duration 1800

Uses only the stdlib + fitparse (for reading). Writes binary FIT directly.
"""

import struct
import sys
import os
import argparse
import time
from datetime import datetime, timezone

# ---------------------------------------------------------------------------
# FIT constants
# ---------------------------------------------------------------------------
FIT_EPOCH_UNIX = 631065600          # Unix seconds for Dec 31, 1989 00:00:00 UTC
FIT_EPOCH_UNIX_MS = 631065600000    # same, in milliseconds

# Timestamps above this are likely from the Dart double-encoding bug (year > ~2053).
# Valid activity timestamps for the next ~25 years are well under 1.5 billion.
FIT_TIMESTAMP_MAX_SANE = 2_000_000_000


def unix_ms_to_fit_s(unix_ms: int) -> int:
    """Convert Unix milliseconds to FIT timestamp (seconds since Dec 31 1989)."""
    return int(unix_ms) // 1000 - FIT_EPOCH_UNIX


def fit_s_to_unix_ms(fit_s: int) -> int:
    return (fit_s + FIT_EPOCH_UNIX) * 1000


def datetime_to_fit_s(dt: datetime) -> int:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp()) - FIT_EPOCH_UNIX


def repair_fit_ts(raw_ts):
    """
    Recover a timestamp broken by the Dart fit_tool double-encoding bug.

    The bug: the app called _toFitTimestamp() which produced FIT seconds
    (~1.1 billion), then passed that value to fields that expect Unix
    milliseconds (~1.74 trillion).  The library applied:

        stored = round((unix_ms - 631_065_600_000) * 0.001)

    With a FIT-seconds value as input, the result is a large negative number
    that wraps to ~3.65 billion as a UINT32 (appearing as year ~2106).

    Reverse formula:
        signed     = broken_uint32 - 2^32        # re-interpret as int32
        correct_fit_s = signed * 1000 + FIT_EPOCH_UNIX_MS

    For already-correct timestamps (< FIT_TIMESTAMP_MAX_SANE) the value is
    returned unchanged.
    """
    if raw_ts is None:
        return None
    raw_ts = int(raw_ts)
    if raw_ts > FIT_TIMESTAMP_MAX_SANE:
        signed = raw_ts - 0x1_0000_0000          # interpret as signed int32
        recovered = signed * 1000 + FIT_EPOCH_UNIX_MS
        if 0 < recovered < FIT_TIMESTAMP_MAX_SANE:
            return recovered
    return raw_ts


# ---------------------------------------------------------------------------
# CRC
# ---------------------------------------------------------------------------
_CRC_TABLE = [
    0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
    0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
]


def _crc_byte(crc: int, byte: int) -> int:
    # Low nibble first, then high nibble (FIT spec order)
    tmp = _CRC_TABLE[crc & 0xF]
    crc = (crc >> 4) & 0x0FFF
    crc ^= tmp
    crc ^= _CRC_TABLE[byte & 0xF]
    tmp = _CRC_TABLE[crc & 0xF]
    crc = (crc >> 4) & 0x0FFF
    crc ^= tmp
    crc ^= _CRC_TABLE[(byte >> 4) & 0xF]
    return crc


def calc_crc(data: bytes) -> int:
    crc = 0
    for b in data:
        crc = _crc_byte(crc, b)
    return crc


# ---------------------------------------------------------------------------
# Base types
# ---------------------------------------------------------------------------
ENUM   = 0x00  # 1 byte
UINT8  = 0x02  # 1 byte
UINT16 = 0x84  # 2 bytes
UINT32 = 0x86  # 4 bytes
UINT32Z= 0x8C  # 4 bytes (zero = invalid)

_BT_SIZE = {ENUM: 1, UINT8: 1, UINT16: 2, UINT32: 4, UINT32Z: 4}
_BT_INVALID = {ENUM: 0xFF, UINT8: 0xFF, UINT16: 0xFFFF,
               UINT32: 0xFFFFFFFF, UINT32Z: 0x00000000}

# Global message numbers
MSG_FILE_ID  = 0
MSG_EVENT    = 21
MSG_RECORD   = 20
MSG_LAP      = 19
MSG_SESSION  = 18
MSG_ACTIVITY = 34

# Local message type numbers (0-15 each file can have up to 16)
LOCAL_FILE_ID  = 0
LOCAL_EVENT    = 1
LOCAL_RECORD   = 2
LOCAL_LAP      = 3
LOCAL_SESSION  = 4
LOCAL_ACTIVITY = 5

# FIT profile enum values
FILE_TYPE_ACTIVITY       = 4
MANUFACTURER_DEVELOPMENT = 255
EVENT_TIMER              = 0
EVENT_TYPE_START         = 0
EVENT_TYPE_STOP_ALL      = 4
EVENT_LAP                = 9
EVENT_TYPE_STOP          = 1
EVENT_SESSION            = 8
EVENT_ACTIVITY           = 26
SPORT_CYCLING            = 2
SUB_SPORT_INDOOR_CYCLING = 6
SESSION_TRIGGER_ACTIVITY_END = 0
LAP_TRIGGER_SESSION_END  = 7
ACTIVITY_TYPE_MANUAL     = 0   # FIT profile: 0 = single-sport device-recorded


# ---------------------------------------------------------------------------
# Low-level binary helpers
# ---------------------------------------------------------------------------

def _pack_val(val, btype: int) -> bytes:
    if val is None:
        inv = _BT_INVALID[btype]
        return struct.pack('<' + {1: 'B', 2: 'H', 4: 'I'}[_BT_SIZE[btype]], inv)
    v = int(val) & {1: 0xFF, 2: 0xFFFF, 4: 0xFFFFFFFF}[_BT_SIZE[btype]]
    return struct.pack('<' + {1: 'B', 2: 'H', 4: 'I'}[_BT_SIZE[btype]], v)


def definition_msg(local_num: int, global_num: int,
                   fields: list) -> bytes:
    """
    fields: list of (field_def_number, base_type)
    Returns a FIT definition record.
    """
    buf = bytearray()
    buf.append(0x40 | (local_num & 0x0F))  # definition record header
    buf.append(0x00)                        # reserved
    buf.append(0x00)                        # architecture: little-endian
    buf += struct.pack('<H', global_num)
    buf.append(len(fields))
    for fnum, btype in fields:
        buf.append(fnum)
        buf.append(_BT_SIZE[btype])
        buf.append(btype)
    return bytes(buf)


def data_msg(local_num: int, fields: list, values: list) -> bytes:
    """
    fields:  list of (field_def_number, base_type) — same order as values
    values:  actual values (None → invalid sentinel)
    """
    buf = bytearray()
    buf.append(local_num & 0x0F)  # data record header
    for (_, btype), val in zip(fields, values):
        buf += _pack_val(val, btype)
    return bytes(buf)


# ---------------------------------------------------------------------------
# FIT field layouts
# ---------------------------------------------------------------------------

FILE_ID_FIELDS = [
    (0, ENUM),    # type
    (1, UINT16),  # manufacturer
    (2, UINT16),  # product
    (3, UINT32Z), # serial_number
    (4, UINT32),  # time_created  (FIT seconds since 1989)
]

EVENT_FIELDS = [
    (253, UINT32), # timestamp     (FIT seconds)
    (0, ENUM),     # event
    (1, ENUM),     # event_type
    (2, UINT8),    # event_group
]

# Record fields always include HR slot; we write 0xFF (invalid) if no HR data.
RECORD_FIELDS = [
    (253, UINT32), # timestamp     (FIT seconds)
    (6, UINT16),   # speed         stored = m/s * 1000
    (7, UINT16),   # power         watts
    (5, UINT32),   # distance      stored = meters * 100
    (3, UINT8),    # heart_rate    bpm  (0xFF = not present)
]

LAP_FIELDS = [
    (253, UINT32), # timestamp
    (0, ENUM),     # event
    (1, ENUM),     # event_type
    (2, UINT32),   # start_time
    (7, UINT32),   # total_elapsed_time   stored = seconds * 1000
    (8, UINT32),   # total_timer_time     stored = seconds * 1000
    (9, UINT32),   # total_distance       stored = meters * 100
    (17, UINT16),  # avg_speed            stored = m/s * 1000
    (23, UINT16),  # avg_power
    (24, UINT16),  # max_power
    (28, ENUM),    # lap_trigger
    (29, ENUM),    # sport
    (35, ENUM),    # sub_sport
    (42, UINT32),  # total_work  joules
    (19, UINT8),   # avg_heart_rate
    (20, UINT8),   # max_heart_rate
]

SESSION_FIELDS = [
    (253, UINT32), # timestamp
    (0, ENUM),     # event
    (1, ENUM),     # event_type
    (2, UINT32),   # start_time
    (5, ENUM),     # sport
    (6, ENUM),     # sub_sport
    (7, UINT32),   # total_elapsed_time
    (8, UINT32),   # total_timer_time
    (9, UINT32),   # total_distance
    (11, UINT16),  # total_calories
    (14, UINT16),  # avg_speed
    (15, UINT16),  # max_speed  (we'll store same as avg if not tracked)
    (20, UINT16),  # avg_power
    (21, UINT16),  # max_power
    (25, UINT16),  # first_lap_index
    (26, UINT16),  # num_laps
    (28, ENUM),    # trigger
    (48, UINT32),  # total_work
    (16, UINT8),   # avg_heart_rate
    (17, UINT8),   # max_heart_rate
]

ACTIVITY_FIELDS = [
    (253, UINT32), # timestamp
    (0, UINT32),   # total_timer_time   stored = seconds * 1000
    (1, UINT16),   # num_sessions
    (2, ENUM),     # type
    (3, ENUM),     # event
    (4, ENUM),     # event_type
    (5, UINT32),   # local_timestamp   (FIT seconds, local time)
]


# ---------------------------------------------------------------------------
# High-level writer
# ---------------------------------------------------------------------------

class FitWriter:
    def __init__(self):
        self._buf = bytearray()
        self._defined = set()

    def _define_if_needed(self, local_num, global_num, fields):
        key = (local_num, global_num)
        if key not in self._defined:
            self._buf += definition_msg(local_num, global_num, fields)
            self._defined.add(key)

    # ---- Individual message writers ----------------------------------------

    def write_file_id(self, start_fit_s: int):
        self._define_if_needed(LOCAL_FILE_ID, MSG_FILE_ID, FILE_ID_FIELDS)
        vals = [FILE_TYPE_ACTIVITY, MANUFACTURER_DEVELOPMENT, 1, 12345, start_fit_s]
        self._buf += data_msg(LOCAL_FILE_ID, FILE_ID_FIELDS, vals)

    def write_event_start(self, ts_fit: int):
        self._define_if_needed(LOCAL_EVENT, MSG_EVENT, EVENT_FIELDS)
        self._buf += data_msg(LOCAL_EVENT, EVENT_FIELDS,
                              [ts_fit, EVENT_TIMER, EVENT_TYPE_START, 0])

    def write_event_stop(self, ts_fit: int):
        self._define_if_needed(LOCAL_EVENT, MSG_EVENT, EVENT_FIELDS)
        self._buf += data_msg(LOCAL_EVENT, EVENT_FIELDS,
                              [ts_fit, EVENT_TIMER, EVENT_TYPE_STOP_ALL, 0])

    def write_record(self, ts_fit: int, speed_ms: float, power_w: int,
                     distance_m: float, heart_rate: int = 0):
        """
        ts_fit      : FIT timestamp (seconds since Dec 31, 1989)
        speed_ms    : speed in m/s
        power_w     : power in watts
        distance_m  : cumulative distance in meters
        heart_rate  : bpm (0 = not present → stored as 0xFF invalid)
        """
        self._define_if_needed(LOCAL_RECORD, MSG_RECORD, RECORD_FIELDS)
        hr_val = heart_rate if heart_rate > 0 else None
        dist_val = int(distance_m * 100) if distance_m > 0 else 0
        vals = [
            ts_fit,
            int(speed_ms * 1000),   # m/s → stored in mm/s
            int(power_w),
            dist_val,               # m → stored in cm
            hr_val,
        ]
        self._buf += data_msg(LOCAL_RECORD, RECORD_FIELDS, vals)

    def write_lap(self, ts_fit: int, start_fit: int,
                  elapsed_s: float, timer_s: float, distance_m: float,
                  avg_speed_ms: float, avg_power: int, max_power: int,
                  avg_hr: int = 0, max_hr: int = 0, total_work_j: int = 0):
        self._define_if_needed(LOCAL_LAP, MSG_LAP, LAP_FIELDS)
        vals = [
            ts_fit, EVENT_LAP, EVENT_TYPE_STOP, start_fit,
            int(elapsed_s * 1000),   # seconds → stored in ms
            int(timer_s * 1000),
            int(distance_m * 100),   # m → cm
            int(avg_speed_ms * 1000),
            int(avg_power), int(max_power),
            LAP_TRIGGER_SESSION_END, SPORT_CYCLING, SUB_SPORT_INDOOR_CYCLING,
            int(total_work_j),
            avg_hr if avg_hr > 0 else None,
            max_hr if max_hr > 0 else None,
        ]
        self._buf += data_msg(LOCAL_LAP, LAP_FIELDS, vals)

    def write_session(self, ts_fit: int, start_fit: int,
                      elapsed_s: float, timer_s: float, distance_m: float,
                      avg_speed_ms: float, max_speed_ms: float,
                      avg_power: int, max_power: int,
                      avg_hr: int = 0, max_hr: int = 0,
                      total_calories: int = 0, total_work_j: int = 0):
        self._define_if_needed(LOCAL_SESSION, MSG_SESSION, SESSION_FIELDS)
        vals = [
            ts_fit, EVENT_SESSION, EVENT_TYPE_STOP, start_fit,
            SPORT_CYCLING, SUB_SPORT_INDOOR_CYCLING,
            int(elapsed_s * 1000), int(timer_s * 1000),
            int(distance_m * 100),
            int(total_calories),
            int(avg_speed_ms * 1000), int(max_speed_ms * 1000),
            int(avg_power), int(max_power),
            0, 1,  # first_lap_index, num_laps
            SESSION_TRIGGER_ACTIVITY_END,
            int(total_work_j),
            avg_hr if avg_hr > 0 else None,
            max_hr if max_hr > 0 else None,
        ]
        self._buf += data_msg(LOCAL_SESSION, SESSION_FIELDS, vals)

    def write_activity(self, ts_fit: int, timer_s: float):
        self._define_if_needed(LOCAL_ACTIVITY, MSG_ACTIVITY, ACTIVITY_FIELDS)
        vals = [
            ts_fit,
            int(timer_s * 1000),   # seconds → ms
            1,                     # num_sessions
            ACTIVITY_TYPE_MANUAL,  # 0 = single-sport device recording
            EVENT_ACTIVITY,
            EVENT_TYPE_STOP,
            ts_fit,                # local_timestamp (same as UTC for simplicity)
        ]
        self._buf += data_msg(LOCAL_ACTIVITY, ACTIVITY_FIELDS, vals)

    # ---- File builder -------------------------------------------------------

    def build(self, output_path: str):
        data = bytes(self._buf)
        data_size = len(data)

        header = bytearray(14)
        header[0] = 14      # header size
        header[1] = 0x20    # protocol version 2.0
        struct.pack_into('<H', header, 2, 2243)       # profile version
        struct.pack_into('<I', header, 4, data_size)  # data size
        header[8:12] = b'.FIT'
        struct.pack_into('<H', header, 12, calc_crc(header[:12]))

        file_crc = calc_crc(data)

        with open(output_path, 'wb') as f:
            f.write(bytes(header))
            f.write(data)
            f.write(struct.pack('<H', file_crc))

        total = 14 + data_size + 2
        print(f'OK  Written: {output_path}  ({total} bytes, {data_size} data bytes)')
        return output_path


# ---------------------------------------------------------------------------
# Mode 1: Rewrite an existing broken FIT file
# ---------------------------------------------------------------------------

def rewrite_fit(input_path: str, output_path: str):
    try:
        from fitparse import FitFile
    except ImportError:
        print("ERROR: fitparse not installed. Run: pip install fitparse")
        sys.exit(1)

    print(f'Reading: {input_path}')
    fitfile = FitFile(input_path)

    records = []
    session = {}
    start_fit_s = None
    end_fit_s = None

    for msg in fitfile.get_messages():
        if msg.name == 'record':
            r = {f.name: f.raw_value for f in msg.fields}
            records.append(r)
        elif msg.name == 'session':
            session = {f.name: f.raw_value for f in msg.fields}
        elif msg.name == 'event':
            vals = {f.name: f.raw_value for f in msg.fields}
            if vals.get('event') == 0:   # timer event
                if vals.get('event_type') == 0 and start_fit_s is None:  # start
                    start_fit_s = vals.get('timestamp')
                elif vals.get('event_type') in (1, 4):  # stop / stop_all
                    end_fit_s = vals.get('timestamp')

    if not records:
        print('ERROR: No record messages found in input file.')
        sys.exit(1)

    # Fall back to session timestamps if events weren't found
    if start_fit_s is None:
        start_fit_s = session.get('start_time') or records[0].get('timestamp', 0)
    if end_fit_s is None:
        end_fit_s = session.get('timestamp') or records[-1].get('timestamp', 0)

    # --- Repair broken timestamps (Dart double-encoding bug) -----------------
    # The old Dart app passed FIT-seconds to fields expecting Unix-milliseconds.
    # This makes all record timestamps collapse to approximately the same UINT32
    # value (~3.65 billion = year ~2106), which is why validators report
    # "FIT is missing usable timestamps".
    start_fit_s = repair_fit_ts(start_fit_s)
    end_fit_s   = repair_fit_ts(end_fit_s)

    # Check whether record timestamps are usable: if all repaired values are
    # the same (or nearly so) the records need sequential timestamps rebuilt.
    raw_rec_tss = [r.get('timestamp') for r in records if r.get('timestamp') is not None]
    repaired_tss = [repair_fit_ts(t) for t in raw_rec_tss]
    unique_count = len(set(repaired_tss))
    timestamps_broken = unique_count <= max(1, len(records) // 10)

    print(f'  Records: {len(records)}')
    if timestamps_broken:
        print(f'  Timestamps: broken ({unique_count} unique value(s) in {len(records)} records)')
        print(f'  Regenerating sequential timestamps from repaired session start.')
        for i, r in enumerate(records):
            r['_ts'] = start_fit_s + i
        # Extend end_fit_s if it ended up too close to start
        end_fit_s = max(end_fit_s, start_fit_s + len(records))
    else:
        print(f'  Timestamps: valid — repairing if needed')
        for r in records:
            r['_ts'] = repair_fit_ts(r.get('timestamp') or start_fit_s)

    print(f'  Start (FIT s): {start_fit_s}  ->  {datetime.utcfromtimestamp(start_fit_s + FIT_EPOCH_UNIX)} UTC')
    print(f'  End   (FIT s): {end_fit_s}    ->  {datetime.utcfromtimestamp(end_fit_s + FIT_EPOCH_UNIX)} UTC')

    # Recompute distance from speed if all distances are zero.
    # When timestamps were broken the per-record dt was 0, so cumulative
    # distance was also 0; always recompute from speed in that case too.
    all_dist_zero = timestamps_broken or all((r.get('distance') or 0) == 0 for r in records)
    if all_dist_zero:
        print('  Distance: computing from speed (1 second per record).')
        cumulative = 0.0
        for r in records:
            raw_speed = r.get('speed') or 0    # stored in mm/s per FIT spec
            speed_ms = raw_speed / 1000.0
            cumulative += speed_ms              # 1 second per tick
            r['_computed_distance_m'] = cumulative
    else:
        print('  Distance: using values from input file.')
        for r in records:
            raw_d = r.get('distance') or 0
            r['_computed_distance_m'] = raw_d / 100.0  # cm -> m

    writer = FitWriter()
    writer.write_file_id(start_fit_s)
    writer.write_event_start(start_fit_s)

    for r in records:
        ts    = r['_ts']
        spd   = (r.get('speed') or 0) / 1000.0          # mm/s -> m/s
        pwr   = int(r.get('power') or 0)
        dist  = r['_computed_distance_m']
        hr    = int(r.get('heart_rate') or 0)
        writer.write_record(ts, spd, pwr, dist, hr)

    writer.write_event_stop(end_fit_s)

    elapsed_s = end_fit_s - start_fit_s

    avg_speed_ms = (session.get('avg_speed') or 0) / 1000.0
    max_speed_ms = (session.get('max_speed') or 0) / 1000.0
    avg_pwr = int(session.get('avg_power') or 0)
    max_pwr = int(session.get('max_power') or 0)
    total_dist_m = records[-1]['_computed_distance_m']
    avg_hr  = int(session.get('avg_heart_rate') or 0)
    max_hr  = int(session.get('max_heart_rate') or 0)
    total_calories = int(session.get('total_calories') or 0)
    total_work_j   = int(session.get('total_work') or 0)

    # Fall back to computing averages from records when session fields are zero
    # (the session avg_speed field may be 0 if the broken Dart app omitted it)
    if avg_speed_ms == 0 and records:
        speeds = [(r.get('speed') or 0) / 1000.0 for r in records]
        avg_speed_ms = sum(speeds) / len(speeds)
        max_speed_ms = max(speeds)
    if avg_pwr == 0 and records:
        powers = [int(r.get('power') or 0) for r in records]
        avg_pwr = int(sum(powers) / len(powers))
        max_pwr = max(powers)

    writer.write_lap(end_fit_s, start_fit_s, elapsed_s, elapsed_s,
                     total_dist_m, avg_speed_ms, avg_pwr, max_pwr,
                     avg_hr, max_hr, total_work_j)
    writer.write_session(end_fit_s, start_fit_s, elapsed_s, elapsed_s,
                         total_dist_m, avg_speed_ms, max_speed_ms,
                         avg_pwr, max_pwr,
                         avg_hr, max_hr, total_calories, total_work_j)
    writer.write_activity(end_fit_s, elapsed_s)
    writer.build(output_path)


# ---------------------------------------------------------------------------
# Mode 2: Generate a synthetic test file
# ---------------------------------------------------------------------------

def generate_synthetic(output_path: str, duration_s: int = 1800):
    import math

    now_fit = int(time.time()) - FIT_EPOCH_UNIX
    start_fit = now_fit - duration_s

    print(f'Generating synthetic {duration_s}s indoor cycling workout...')
    print(f'  Start: {datetime.utcfromtimestamp(start_fit + FIT_EPOCH_UNIX)} UTC')

    writer = FitWriter()
    writer.write_file_id(start_fit)
    writer.write_event_start(start_fit)

    cumulative_dist = 0.0
    total_power = 0.0
    max_power_w = 0
    max_speed_ms = 0.0
    total_hr = 0
    n_hr = 0

    for second in range(duration_s):
        ts = start_fit + second

        # Simulate a realistic ride: power varies, speed follows
        base_power = 180
        power_variation = 40 * math.sin(second * 2 * math.pi / 300)  # 5-min cycle
        power_w = int(base_power + power_variation)

        # Speed ≈ 25–35 km/h → 7–10 m/s based on power
        speed_ms = 7.0 + (power_w - 140) * 0.02
        speed_ms = max(0.0, speed_ms)

        # Simulate HR: starts at 130, climbs to ~160 over the workout
        hr_bpm = int(130 + (second / duration_s) * 30 + 5 * math.sin(second * 0.1))

        cumulative_dist += speed_ms
        total_power += power_w
        max_power_w = max(max_power_w, power_w)
        max_speed_ms = max(max_speed_ms, speed_ms)
        total_hr += hr_bpm
        n_hr += 1

        writer.write_record(ts, speed_ms, power_w, cumulative_dist, hr_bpm)

    end_fit = start_fit + duration_s
    avg_power = int(total_power / duration_s)
    avg_speed = (total_power / duration_s - 140) * 0.02 + 7.0
    avg_speed = max(0.0, avg_speed)
    avg_hr = int(total_hr / n_hr)
    total_work_j = int(avg_power * duration_s)
    total_calories = int(total_work_j / 4184)

    writer.write_event_stop(end_fit)
    writer.write_lap(end_fit, start_fit, duration_s, duration_s,
                     cumulative_dist, avg_speed, avg_power, max_power_w,
                     avg_hr, max_hr=170, total_work_j=total_work_j)
    writer.write_session(end_fit, start_fit, duration_s, duration_s,
                         cumulative_dist, avg_speed, max_speed_ms,
                         avg_power, max_power_w,
                         avg_hr, max_hr=170,
                         total_calories=total_calories,
                         total_work_j=total_work_j)
    writer.write_activity(end_fit, duration_s)
    writer.build(output_path)

    print(f'  Avg power: {avg_power}W   Max: {max_power_w}W')
    print(f'  Distance: {cumulative_dist/1000:.2f} km')
    print(f'  Avg HR: {avg_hr} bpm')


# ---------------------------------------------------------------------------
# Inspect a FIT file (read-only diagnostic)
# ---------------------------------------------------------------------------

def inspect_fit(path: str):
    try:
        from fitparse import FitFile
    except ImportError:
        print("ERROR: fitparse not installed.")
        sys.exit(1)

    print(f'\n=== Inspecting: {path} ===')
    fitfile = FitFile(path)

    record_count = 0
    for msg in fitfile.get_messages():
        if msg.name == 'record':
            record_count += 1
            if record_count <= 2 or record_count % 100 == 0:
                ts = None
                vals = {}
                for f in msg.fields:
                    if f.name == 'timestamp':
                        ts = f.raw_value
                    else:
                        vals[f.name] = f.raw_value
                ts_str = ''
                if ts is not None:
                    try:
                        ts_str = str(datetime.utcfromtimestamp(ts + FIT_EPOCH_UNIX)) + ' UTC'
                    except Exception:
                        ts_str = f'raw={ts}'
                print(f'  record #{record_count}: ts={ts_str}  {vals}')
        elif msg.name in ('session', 'lap', 'activity', 'file_id'):
            print(f'\n--- {msg.name} ---')
            for f in msg.fields:
                if f.raw_value is not None:
                    extra = ''
                    if f.name in ('timestamp', 'start_time', 'time_created', 'local_timestamp'):
                        try:
                            extra = f'  -> {datetime.utcfromtimestamp(f.raw_value + FIT_EPOCH_UNIX)} UTC'
                        except Exception:
                            pass
                    print(f'  {f.name}: {f.raw_value}{extra}')
        elif msg.name == 'event':
            vals = {f.name: f.raw_value for f in msg.fields}
            ts = vals.get('timestamp', 0)
            try:
                ts_str = str(datetime.utcfromtimestamp(ts + FIT_EPOCH_UNIX)) + ' UTC'
            except Exception:
                ts_str = f'raw={ts}'
            print(f'  event: {vals.get("event_type")} @ {ts_str}')

    print(f'\nTotal record messages: {record_count}')


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Ride Forge FIT file fixer / generator')
    parser.add_argument('--input',    help='Broken .fit file to rewrite')
    parser.add_argument('--output',   help='Output .fit file path (required unless --inspect)')
    parser.add_argument('--duration', type=int, default=1800,
                        help='Synthetic workout duration in seconds (default 1800 = 30 min)')
    parser.add_argument('--inspect',  help='Just inspect a .fit file and exit')
    args = parser.parse_args()

    if args.inspect:
        inspect_fit(args.inspect)
        return

    if not args.output:
        parser.error('--output is required when not using --inspect')

    if args.input:
        rewrite_fit(args.input, args.output)
    else:
        generate_synthetic(args.output, args.duration)

    # Always inspect the output so we can confirm it looks right
    print()
    inspect_fit(args.output)


if __name__ == '__main__':
    main()
