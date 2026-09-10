#!/usr/bin/env python3
"""Generate the binary PTB configuration from a text configuration file."""

import argparse
import re
import struct
from pathlib import Path


CONFIG_FIELDS = ("tune", "swd_spi_sclkdiv")
FIELD_PATTERN = re.compile(
    r'^\s*(?:"(?P<quoted_name>[A-Za-z_][A-Za-z0-9_]*)"|'
    r'(?P<plain_name>[A-Za-z_][A-Za-z0-9_]*))\s*(?::|=)\s*'
    r'(?P<value>0[xX][0-9A-Fa-f]+|[0-9]+)\s*,?\s*$'
)


def parse_value(text: str, line_number: int) -> int:
    try:
        value = int(text, 16) if text.lower().startswith("0x") else int(text, 10)
    except ValueError as error:
        raise ValueError(
            f"line {line_number}: invalid value {text!r}"
        ) from error

    if not 0 <= value <= 0xFF:
        raise ValueError(
            f"line {line_number}: value {value} is outside uint8 range"
        )
    return value


def read_config(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}

    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(), start=1
    ):
        line = raw_line.split("#", 1)[0].split("//", 1)[0].strip()
        if not line:
            continue

        match = FIELD_PATTERN.match(line)
        if match is None:
            raise ValueError(f"line {line_number}: invalid configuration syntax")

        name = match.group("quoted_name") or match.group("plain_name")
        if name not in CONFIG_FIELDS:
            expected = ", ".join(CONFIG_FIELDS)
            raise ValueError(
                f"line {line_number}: unknown field {name!r}; "
                f"expected one of: {expected}"
            )
        if name in values:
            raise ValueError(f"line {line_number}: duplicate field {name!r}")

        values[name] = parse_value(match.group("value"), line_number)

    missing = [name for name in CONFIG_FIELDS if name not in values]
    if missing:
        raise ValueError(f"missing required field(s): {', '.join(missing)}")

    return values


def crc16(data: bytes) -> int:
    """Match the PTB crc16.c lookup-table result.

    The reflected bitwise calculation below produces the internal CRC
    bytes in reverse order. PTB returns (CRCHi << 8) | CRCLo, so swap
    the two bytes before returning the result.
    """
    crc = 0xFFFF
    for value in data:
        crc ^= value
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return ((crc & 0xFF) << 8) | (crc >> 8)


def generate(input_path: Path, output_path: Path) -> None:
    values = read_config(input_path)
    payload = bytes((values["tune"], values["swd_spi_sclkdiv"]))
    crc = crc16(payload)
    output_path.write_bytes(struct.pack("<BBH", *payload, crc))

    print(f"tune=0x{values['tune']:02x}")
    print(f"swd_spi_sclkdiv=0x{values['swd_spi_sclkdiv']:02x}")
    print(f"crc=0x{crc:04x}")
    print(f"generated: {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate PTB_config.bin from PTB_config.txt"
    )
    parser.add_argument(
        "input",
        nargs="?",
        type=Path,
        help="input text file; defaults to PTB_config.txt beside this script",
    )
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        help="output binary file; defaults to PTB_config.bin beside this script",
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    input_path = (args.input or script_dir / "PTB_config.txt").resolve()
    output_path = (args.output or script_dir / "PTB_config.bin").resolve()
    generate(input_path, output_path)


if __name__ == "__main__":
    main()
