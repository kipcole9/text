# `lid.176.bin` Binary Format

This document specifies the on-disk layout of fastText's `lid.176.bin` language identification model so that an Elixir parser can be written without reference to the C++ implementation.

The specification was derived from fastText source at https://github.com/facebookresearch/fastText `main` branch, files `src/fasttext.{h,cc}`, `src/args.{h,cc}`, `src/dictionary.{h,cc}`, `src/densematrix.{h,cc}`, `src/real.h`. Line references below point to that source.

## Scalar primitives

| C++ type        | Width   | Notes                                                |
|-----------------|---------|------------------------------------------------------|
| `int` / `int32_t` | 4 bytes | Signed, little-endian. fastText assumes `sizeof(int) == 4`. |
| `int64_t`       | 8 bytes | Signed, little-endian.                               |
| `int8_t`        | 1 byte  | Signed.                                              |
| `bool`          | 1 byte  | `0x00` = false, `0x01` = true. Implementation-defined in C++ but 1 byte on every platform fastText is shipped for. |
| `real`          | 4 bytes | IEEE 754 single-precision (`typedef float real`, `src/real.h`). Little-endian. |
| `double`        | 8 bytes | IEEE 754 double-precision, little-endian.            |
| Enum            | 4 bytes | Backed by `int` unless explicitly typed.             |

All multibyte integers and floats are stored little-endian. The model files distributed by fastText are produced on x86_64 Linux/macOS and have been deployed for years on those platforms; the parser makes the same assumption.

## Top-level layout

```
+--------------------------------------+
|  Magic + Version  (signModel)        |
+--------------------------------------+
|  Args             (Args::save)       |
+--------------------------------------+
|  Dictionary       (Dictionary::save) |
+--------------------------------------+
|  quant_input      (1 byte bool)      |
+--------------------------------------+
|  Input matrix     (DenseMatrix::save)|
+--------------------------------------+
|  qout             (1 byte bool)      |
+--------------------------------------+
|  Output matrix    (DenseMatrix::save)|
+--------------------------------------+
|  EOF                                 |
+--------------------------------------+
```

Reference: `FastText::saveModel` (`fasttext.cc:192-211`) and `FastText::loadModel` (`fasttext.cc:239-272`).

## Section 1: Magic + version

`signModel` / `checkModel` (`fasttext.cc:172-190`).

| Offset | Field    | Type    | Expected value                |
|-------:|----------|---------|-------------------------------|
| 0      | `magic`  | int32   | `793712314` (`0x2F09BC2A`)    |
| 4      | `version`| int32   | `12` (current). Reader must reject `version > 12`. |

`lid.176.bin` released by fastText is version 12.

## Section 2: Args

`Args::save` (`args.cc:326-340`). Fixed 13 fields, total 56 bytes.

| Field          | Type   | Width | Meaning |
|----------------|--------|------:|---------|
| `dim`          | int32  | 4 | Embedding dimensionality. `lid.176`: 16. |
| `ws`           | int32  | 4 | Context window size (training param; not used at inference). |
| `epoch`        | int32  | 4 | Training epochs. |
| `minCount`     | int32  | 4 | Minimum word count threshold used during training. |
| `neg`          | int32  | 4 | Negative-sampling count. |
| `wordNgrams`   | int32  | 4 | Maximum word n-gram length (lid.176: 1, i.e. unigrams only). |
| `loss`         | int32  | 4 | `loss_name` enum: 1=hs, 2=ns, 3=softmax, 4=ova. `lid.176`: 1 (hs — hierarchical softmax). |
| `model`        | int32  | 4 | `model_name` enum: 1=cbow, 2=sg, 3=sup. `lid.176`: 3 (sup). |
| `bucket`       | int32  | 4 | Number of subword hash buckets. `lid.176`: 2,000,000. |
| `minn`         | int32  | 4 | Minimum char n-gram length. `lid.176`: 2. |
| `maxn`         | int32  | 4 | Maximum char n-gram length. `lid.176`: 4. |
| `lrUpdateRate` | int32  | 4 | Training param. |
| `t`            | double | 8 | Subsampling threshold (training param). |

Enum definitions: `args.h:19-20`, `dictionary.h:26`.

```cpp
enum class model_name : int { cbow = 1, sg, sup };
enum class loss_name  : int { hs = 1, ns, softmax, ova };
```

For `lid.176` the values are `model = sup (3)` and `loss = hs (1)`. The parser does not require any other model/loss combination to work, but downstream inference must implement hierarchical softmax decoding to consume `lid.176` correctly. (See Phase 5 of the implementation plan.)

## Section 3: Dictionary

`Dictionary::save` (`dictionary.cc:481-498`).

### Header (28 bytes)

| Field            | Type   | Width |
|------------------|--------|------:|
| `size`           | int32  | 4 |
| `nwords`         | int32  | 4 |
| `nlabels`        | int32  | 4 |
| `ntokens`        | int64  | 8 |
| `pruneidx_size`  | int64  | 8 |

Invariant: `size == nwords + nlabels` for non-pruned models. `lid.176` has `nlabels == 176` and `nwords` in the high hundreds of thousands.

### Entries

`size` consecutive entries, each:

```
+-----------------------------------+
| word: null-terminated UTF-8 bytes |
| count: int64                      |
| type:  int8 (0=word, 1=label)     |
+-----------------------------------+
```

Words are stored as raw byte sequences terminated by `0x00`. The terminator is **not** part of the word. Label entries use the same encoding; in `lid.176` label words look like `__label__en`, `__label__zh-Hans`, etc.

`entry_type` enum (`dictionary.h:26`): `enum class entry_type : int8_t { word = 0, label = 1 }`.

### Prune index (optional)

If `pruneidx_size > 0`, `pruneidx_size` pairs of `(int32, int32)` follow. `lid.176` is not pruned (`pruneidx_size == 0`); the parser must still read this field to advance the file cursor.

## Section 4: `quant_input` flag

One byte. `0x00` for the unquantized `lid.176.bin`; `0x01` indicates a `QuantMatrix` follows instead of a `DenseMatrix` and the parser should reject such models in v1 (quantized format requires product-quantization decoding which is out of scope for the initial implementation).

Reference: `fasttext.cc:250-256`.

## Section 5: Input matrix (DenseMatrix)

`DenseMatrix::save` (`densematrix.cc:239-243`).

| Field | Type  | Width |
|-------|-------|------:|
| `m`   | int64 | 8 |
| `n`   | int64 | 8 |
| data  | float | 4 × m × n |

Expected shape:

* `m == nwords + bucket` (entries 0..nwords-1 are word vectors; entries nwords..nwords+bucket-1 are subword n-gram vectors keyed by `hash(ngram) mod bucket`).
* `n == dim`.

Row-major storage: row `i` occupies bytes `[i × n × 4, (i+1) × n × 4)` of the data block.

For `lid.176` with `bucket = 2_000_000` and `dim = 16`, the data block is approximately `(nwords + 2_000_000) × 16 × 4` ≈ 128 MB and dominates the file size.

## Section 6: `qout` flag

One byte. Indicates whether the **output** matrix is product-quantized. `lid.176.bin` (unquantized) has `0x00`. The parser rejects `0x01`.

Reference: `fasttext.cc:265-269`.

## Section 7: Output matrix (DenseMatrix)

Same layout as Section 5. Expected shape:

* `m == nlabels` (one row per language label).
* `n == dim`.

For `lid.176` this is `176 × 16 × 4` = 11,264 bytes.

## End-of-file

After Section 7 the file ends. No padding, no checksum.

## Cross-checks the parser must perform

A correct parser should reject obviously malformed inputs early:

* Magic byte mismatch.
* Version > `FASTTEXT_VERSION` (12).
* `quant_input == true` or `qout == true` (out of scope for v1).
* Input matrix `m != nwords + bucket` or `n != dim`.
* Output matrix `m != nlabels` or `n != dim`.
* `dim`, `nwords`, `nlabels`, `bucket` all positive.
* `pruneidx_size >= 0`.

Validation should happen before allocating large buffers so a malformed file does not trigger a multi-hundred-megabyte allocation.

## Field offsets in `lid.176.bin`

Concrete offsets are computed at runtime; the dictionary section has variable length (depends on word string lengths). The parser uses sequential reads with `:file.pread/3` and tracks the current offset itself rather than precomputing.

## Hashing and inference math

Out of scope for this document (covered in subsequent phases). For reference:

* Subword hash and n-gram generation: `Dictionary::hash`, `Dictionary::computeSubwords` (`dictionary.cc`). Phase 3 of the implementation plan.
* Forward pass: average input rows for the active feature indices, dot with output matrix, softmax. Phase 5 of the plan.
