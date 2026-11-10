"""Regression tests for the chunked decoder's own limits.

The payload cap alone is not a limit: a hostile stream can spend unbounded time
and framing bytes without ever growing the payload. These tests attack the
decoder directly, because the tuple they describe (zero-size chunks, non-hex
size fields) is cheaper to write here than over a socket, and because they must
keep failing closed even if the HTTP layer changes.
"""

import io
import time

import pytest

from triggers.webhook_server import (
    MAX_BODY_BYTES,
    MAX_CHUNKED_WIRE_BYTES,
    ChunkedBodyError,
    read_chunked_body,
)


class EndlessTrailerFlood:
    """A zero-size chunk followed by an endless stream of valid trailers."""

    def __init__(self, limit: int = 5_000_000) -> None:
        self.calls = 0
        self.limit = limit

    def readline(self, size: int = -1) -> bytes:
        self.calls += 1
        if self.calls > self.limit:
            raise AssertionError("decoder read past its own budget")
        if self.calls == 1:
            return b"0\r\n"
        return b"X-Flood: yes\r\n"

    def read(self, size: int = -1) -> bytes:
        return b"\r\n"


class SliceReader:
    """Replays a fixed byte string through the reader interface."""

    def __init__(self, data: bytes) -> None:
        self.stream = io.BytesIO(data)

    def readline(self, size: int = -1) -> bytes:
        return self.stream.readline(size)

    def read(self, size: int = -1) -> bytes:
        return self.stream.read(size)


def test_endless_trailer_flood_is_bounded():
    """Endless valid trailers against a 1 MB cap must not be accepted."""
    started = time.monotonic()

    with pytest.raises(ChunkedBodyError) as excinfo:
        read_chunked_body(EndlessTrailerFlood(), MAX_BODY_BYTES)

    assert excinfo.value.too_large is True
    assert time.monotonic() - started < 10, "decoder did not terminate promptly"


@pytest.mark.parametrize("size_field", [b"1_0", b"0x10", b"+a", b"-5", b"1aGARBAGE"])
def test_non_hex_chunk_size_is_rejected(size_field):
    """RFC 7230 chunk-size is 1*HEXDIG; int(x, 16) is more permissive than that."""
    payload = b"A" * 16
    stream = SliceReader(size_field + b"\r\n" + payload + b"\r\n0\r\n\r\n")

    with pytest.raises(ChunkedBodyError) as excinfo:
        read_chunked_body(stream, MAX_BODY_BYTES)

    assert excinfo.value.too_large is False


@pytest.mark.parametrize("size_line", [b" 1\r\n", b"1 \r\n", b"\t1\r\n", b"1\n"])
def test_size_line_must_be_strict_hex_crlf(size_line):
    """RFC 7230 chunk-size is 1*HEXDIG followed by CRLF; no whitespace, no bare LF."""
    payload = b"A"
    stream = SliceReader(size_line + payload + b"\r\n0\r\n\r\n")

    with pytest.raises(ChunkedBodyError) as excinfo:
        read_chunked_body(stream, MAX_BODY_BYTES)

    assert excinfo.value.too_large is False


def test_malformed_trailer_is_rejected():
    """A trailer line that is not a header field must not be accepted."""
    payload = b"A"
    stream = SliceReader(b"1\r\n" + payload + b"\r\n0\r\nnot-a-header\r\n\r\n")

    with pytest.raises(ChunkedBodyError) as excinfo:
        read_chunked_body(stream, MAX_BODY_BYTES)

    assert excinfo.value.too_large is False


def test_trailer_terminator_must_be_crlf():
    """A bare LF cannot terminate the trailer section."""
    payload = b"A"
    stream = SliceReader(b"1\r\n" + payload + b"\r\n0\r\n\n")

    with pytest.raises(ChunkedBodyError) as excinfo:
        read_chunked_body(stream, MAX_BODY_BYTES)

    assert excinfo.value.too_large is False


def test_chunk_extension_is_accepted():
    """A chunk extension after the size is legal and must not be parsed as data."""
    payload = b"A" * 16
    stream = SliceReader(b"10;name=value\r\n" + payload + b"\r\n0\r\n\r\n")

    assert read_chunked_body(stream, MAX_BODY_BYTES) == payload


def test_trailers_are_accepted():
    payload = b'{"ref":"main"}'
    size = f"{len(payload):x}".encode("ascii")
    stream = SliceReader(size + b"\r\n" + payload + b"\r\n0\r\nX-Trace: abc\r\n\r\n")

    assert read_chunked_body(stream, MAX_BODY_BYTES) == payload


def test_wire_budget_is_larger_than_the_payload_cap():
    """Framing is allowed its own headroom, or every real 1 MB body would fail."""
    assert MAX_CHUNKED_WIRE_BYTES > MAX_BODY_BYTES
