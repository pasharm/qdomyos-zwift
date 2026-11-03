#!/usr/bin/env python3
# Test only (T-182): synthetic .fit workouts for the emulator, no data of a real person.
# make_fit.py <out dir> <count> [minutes]: <count> different one-second runs, workout-<i>.fit.
# file_id, one record a second (heart rate, cadence, distance, speed, power, altitude) and a
# session with the sport: what qfit::open reads.
import os
import struct
import sys

FIT_EPOCH = 631065600


def crc16(data, crc=0):
    table = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
             0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]
    for byte in data:
        tmp = table[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ table[byte & 0xF]
        tmp = table[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ table[(byte >> 4) & 0xF]
    return crc


def definition(local, global_num, fields):
    out = struct.pack("<BBBHB", 0x40 | local, 0, 0, global_num, len(fields))
    for num, size, base in fields:
        out += struct.pack("<BBB", num, size, base)
    return out


def workout(index, minutes):
    start_unix = 1767225600 + index * 86400 + 18 * 3600  # 2026-01-01 18:00 UTC + index days
    start = start_unix - FIT_EPOCH
    seconds = minutes * 60
    data = b""
    # file_id: type, manufacturer, product, serial_number, time_created
    data += definition(0, 0, [(0, 1, 0x00), (1, 2, 0x84), (2, 2, 0x84), (3, 4, 0x8C), (4, 4, 0x86)])
    data += struct.pack("<BBHHII", 0, 4, 255, 182, 1000 + index, start)
    # record: timestamp, heart_rate, cadence, distance, speed, power, altitude
    data += definition(1, 20, [(253, 4, 0x86), (3, 1, 0x02), (4, 1, 0x02), (5, 4, 0x86),
                               (6, 2, 0x84), (7, 2, 0x84), (2, 2, 0x84)])
    speed = 2.5 + (index % 7) * 0.1  # m/s
    for t in range(seconds + 1):
        heart = 110 + (index * 3 + t // 30) % 60
        cadence = 80 + (t + index) % 10
        distance = int(speed * t * 100)
        power = 150 + (t * 7 + index) % 40
        altitude = int((100 + (t % 50) * 0.2 + 500) * 5)
        data += struct.pack("<BIBBIHHH", 1, start + t, heart, cadence, distance,
                            int(speed * 1000), power, altitude)
    # session: timestamp, start_time, sport, sub_sport, total_elapsed_time, total_timer_time,
    # total_distance
    data += definition(2, 18, [(253, 4, 0x86), (2, 4, 0x86), (5, 1, 0x00), (6, 1, 0x00),
                               (7, 4, 0x86), (8, 4, 0x86), (9, 4, 0x86)])
    data += struct.pack("<BIIBBIII", 2, start + seconds, start, 1, 0, seconds * 1000,
                        seconds * 1000, int(speed * seconds * 100))
    header = struct.pack("<BBHI4s", 14, 0x10, 2132, len(data), b".FIT")
    header += struct.pack("<H", crc16(header))
    body = header + data
    return body + struct.pack("<H", crc16(body))


def main():
    out_dir = sys.argv[1]
    count = int(sys.argv[2])
    minutes = int(sys.argv[3]) if len(sys.argv) > 3 else 60
    os.makedirs(out_dir, exist_ok=True)
    for i in range(count):
        with open(os.path.join(out_dir, "workout-%02d.fit" % i), "wb") as f:
            f.write(workout(i, minutes))


if __name__ == "__main__":
    main()
