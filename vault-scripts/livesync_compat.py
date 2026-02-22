#!/usr/bin/env python3
"""
LiveSync Compatible Chunking Module

Implements the same chunking and hashing algorithms as Obsidian LiveSync
to ensure document compatibility.

Algorithm (from livesync-commonlib):
- Hash: xxhash64 with format `{content}-{length}`, base36 encoded
- Chunking: Rabin-Karp rolling hash with content-defined boundaries

Reference: https://github.com/vrtmrz/livesync-commonlib
"""

import xxhash

# Rabin-Karp constants (from livesync-commonlib)
PRIME = 31
WINDOW_SIZE = 48
MIN_PIECE_SIZE_TEXT = 128
SPLIT_PIECE_COUNT_TEXT = 20  # ~20 pieces for text
BOUNDARY_PATTERN = 1

# Config-based defaults
DEFAULT_MIN_CHUNK_SIZE = 20
DEFAULT_MAX_PIECE_SIZE = 250  # customChunkSize * 1024 bytes, but for text we use smaller


def int_to_base36(n: int) -> str:
    """Convert unsigned integer to base36 string (matches JS .toString(36))"""
    if n == 0:
        return "0"

    chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    result = ""

    # Handle as unsigned 64-bit
    n = n & 0xFFFFFFFFFFFFFFFF

    while n > 0:
        result = chars[n % 36] + result
        n //= 36

    return result


def generate_chunk_id(data: str) -> str:
    """
    Generate LiveSync compatible chunk ID using xxhash64.

    Algorithm from XXHash64HashManager.computeHashWithoutEncryption:
        xxhash.h64(`${piece}-${piece.length}`).toString(36)

    Returns: h:{hash_base36}
    """
    hash_input = f"{data}-{len(data)}"
    hash_value = xxhash.xxh64(hash_input.encode('utf-8')).intdigest()
    return f"h:{int_to_base36(hash_value)}"


def to_signed32(n: int) -> int:
    """Convert to signed 32-bit integer (matches JS bitwise | 0)"""
    n = n & 0xFFFFFFFF
    if n >= 0x80000000:
        return n - 0x100000000
    return n


def imul(a: int, b: int) -> int:
    """Emulate JavaScript Math.imul() - 32-bit integer multiplication"""
    a = a & 0xFFFFFFFF
    b = b & 0xFFFFFFFF
    result = (a * b) & 0xFFFFFFFF
    if result >= 0x80000000:
        return result - 0x100000000
    return result


def split_into_chunks(
    content: str,
    absolute_max_piece_size: int = DEFAULT_MAX_PIECE_SIZE * 1024,
    minimum_chunk_size: int = DEFAULT_MIN_CHUNK_SIZE
) -> list[str]:
    """
    Split content into chunks using Rabin-Karp rolling hash.

    Python port of splitPiecesRabinKarp from livesync-commonlib.

    Algorithm:
    - Rolling hash over a sliding window of 48 bytes
    - When hash % avgChunkSize == 1, mark as potential boundary
    - Respect min/max chunk sizes
    - Don't split in middle of UTF-8 sequences
    """
    if not content:
        return []

    data = content.encode('utf-8')
    length = len(data)

    if length == 0:
        return []

    # Calculate chunk size parameters (matches LiveSync)
    min_piece_size = MIN_PIECE_SIZE_TEXT
    avg_chunk_size = max(min_piece_size, length // SPLIT_PIECE_COUNT_TEXT)
    max_chunk_size = min(absolute_max_piece_size, avg_chunk_size * 5)
    min_chunk_size = min(max(avg_chunk_size // 4, minimum_chunk_size), max_chunk_size)

    hash_modulus = avg_chunk_size

    # Calculate PRIME^(windowSize-1) for rolling hash
    p_pow_w = 1
    for _ in range(WINDOW_SIZE - 1):
        p_pow_w = imul(p_pow_w, PRIME)

    chunks = []
    pos = 0
    start = 0
    hash_val = 0

    while pos < length:
        byte_val = data[pos]

        # Update rolling hash
        if pos >= start + WINDOW_SIZE:
            old_byte = data[pos - WINDOW_SIZE]
            old_byte_term = imul(old_byte, p_pow_w)
            hash_val = to_signed32(hash_val - old_byte_term)
            hash_val = imul(hash_val, PRIME)
            hash_val = to_signed32(hash_val + byte_val)
        else:
            hash_val = imul(hash_val, PRIME)
            hash_val = to_signed32(hash_val + byte_val)

        current_chunk_size = pos - start + 1
        is_boundary_candidate = False

        # Boundary judgment
        if current_chunk_size >= min_chunk_size:
            # Convert to unsigned for modulus (>>> 0 in JS)
            unsigned_hash = hash_val & 0xFFFFFFFF
            if unsigned_hash % hash_modulus == BOUNDARY_PATTERN:
                is_boundary_candidate = True

        if current_chunk_size >= max_chunk_size:
            is_boundary_candidate = True

        # Extract chunk if boundary found
        if is_boundary_candidate:
            is_safe_boundary = True

            # Don't split in middle of UTF-8 multi-byte character
            if pos + 1 < length and (data[pos + 1] & 0xc0) == 0x80:
                is_safe_boundary = False

            if is_safe_boundary:
                chunk_bytes = data[start:pos + 1]
                chunks.append(chunk_bytes.decode('utf-8', errors='replace'))
                start = pos + 1

        pos += 1

    # Yield remaining data
    if start < length:
        chunk_bytes = data[start:length]
        chunks.append(chunk_bytes.decode('utf-8', errors='replace'))

    return chunks


def process_document(content: str) -> tuple[list[str], list[str]]:
    """
    Process document into chunks and generate chunk IDs.

    Returns:
        (chunk_ids, chunks) - List of chunk IDs and their content
    """
    chunks = split_into_chunks(content)

    chunk_ids = []
    for chunk in chunks:
        chunk_id = generate_chunk_id(chunk)
        chunk_ids.append(chunk_id)

    return chunk_ids, chunks
