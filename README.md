# Z7 Arch — a cube archiver with search and partial extraction

Pion (Ion Paraschiv), Jahbalon Research · with Claude (Anthropic) · 18 November 2026

Z7 Arch is an archiver for Android written entirely in **Oberon-07**. It is compiled with OLL (an Oberon-07 to LLVM compiler) inside Byz7 on the phone. This record contains **Z7 Arch 6**, the English edition.

Its archive format, `.z7c`, stores data as a **cube of 64 KB cells**. You can:

- take out a single file by decoding only the cells it occupies;
- search the archive while decoding only the cells that can contain the searched word;
- lose a damaged cell without losing the files that do not touch it.

## How it works

**Engine.** The compressor is a context-mixing model in the PAQ family:

- six context orders (0, 1, 2, 3, 4 and 6 bytes);
- a match model;
- a neural mixer selected by the partial byte;
- an SSE stage;
- a binary rANS coder.

A cell is stored raw if compression does not pay.

**Cells.** All files are concatenated and cut into 64 KB cells. Every cell is compressed starting from the same saved model state, never from the previous cell. This is what makes each cell decodable on its own.

**The Egg** (Salamandra). Up to 16 KB of compressible data is sampled evenly across the stream. The model learns it first, and the state after the Egg is saved; every cell starts from that state. The Egg is stored twice. If the first copy is damaged, the second one is used.

**The map** (Cubicum FS addressing). The Egg sits at the centre (3,3,3) of a 7×7×7 cube. Cells fill the shells around it: 26 + 98 + 218 = 342 cells per cube, up to 7 cubes (about 150 MB). A cell's address looks like `C1(2,4,2)`. For each cell the map stores:

- its raw and compressed size;
- an Adler-32 checksum;
- for text cells only, a 4096-bit fingerprint of the words it contains (first 6 letters, two hashes).

The map has its own checksum.

**Search.** Each query word that is either complete or at least 6 letters long is checked against the cell fingerprints. Only the candidate cells are decoded, then the text is confirmed with a case-insensitive match at the start of a word.

**The Ash** (Salamandra). VERIFY decodes every cell and checks its checksum. A damaged cell "burns" and is listed with its cube address, together with the files it touches. All other files still extract intact.

**Modular.** ADD appends files to an existing archive. The old cells are copied byte for byte, and only the new cells are compressed, using the same Egg.

## Benchmark

ZIP is `zip -9`. Z7 Arch 3 is the same engine used as a solid archive, with no random access. xz is `tar | xz -9e`. Each value is the compressed size as a percentage of the original. The last column is the cube's size relative to ZIP; negative means the cube is smaller.

| data set | bytes | ZIP | **cube .z7c** | Z7 Arch 3 solid | xz | cube vs ZIP |
|---|---:|---:|---:|---:|---:|---:|
| random noise | 1,000,000 | 100.0% | **100.1%** | 100.0% | 100.1% | +0.0% |
| raw images (BMP) | 1,899,948 | 51.4% | **39.0%** | 37.1% | 41.2% | -24.1% |
| Java .class | 156,152 | 52.7% | **44.8%** | 38.8% | 35.1% | -15.1% |
| C source | 2,098,545 | 24.7% | **19.5%** | 15.9% | 18.1% | -21.1% |
| Oberon source | 1,174,731 | 29.3% | **23.6%** | 19.2% | 21.5% | -19.3% |
| Python source | 1,137,704 | 25.0% | **21.9%** | 18.6% | 20.5% | -12.7% |
| CSV | 477,169 | 54.3% | **48.9%** | 45.5% | 49.7% | -10.0% |
| executables (ELF) | 1,131,024 | 49.4% | **45.5%** | 42.3% | 41.6% | -7.9% |
| HTML | 357,578 | 27.8% | **24.6%** | 20.4% | 23.5% | -11.5% |
| JPEG | 931,488 | 98.4% | **100.1%** | 97.8% | 98.6% | +1.8% |
| JSON | 837,983 | 8.0% | **6.8%** | 4.3% | 5.1% | -15.0% |
| logs | 1,331,327 | 11.2% | **9.1%** | 5.5% | 6.8% | -18.7% |
| PDF | 2,724,297 | 93.3% | **93.8%** | 92.5% | 92.3% | +0.6% |
| mixed Oberon dump (author) | 1,538,148 | 18.7% | **16.5%** | 9.7% | 10.7% | -11.5% |
| PNG | 4,832,790 | 92.4% | **91.4%** | 90.8% | 91.7% | -1.2% |
| SQLite db | 73,728 | 21.0% | **21.9%** | 16.5% | 16.6% | +4.7% |
| English text | 1,193,606 | 30.3% | **22.9%** | 16.5% | 18.3% | -24.3% |
| **total** | 22,896,218 | 56.5% | **53.3%** | 50.6% | 51.9% | -5.6% |

On the author's own Oberon sources (18 files, 351,532 bytes), the results were:

- ZIP: 28.4%
- cube: **20.0%**
- solid: 14.0%

A search for "salamandra" found 6 lines while decoding 2 of 6 cells.

All data sets were packed and extracted again, and every file came back byte-identical.

### Robustness tests

- 40 corrupted bytes in one cell: only the files touching that cell were lost (14 of 15 files survived).
- A corrupted first Egg: all files were recovered from the second copy.
- ADD: three files appended to an 11-cell archive without recompressing the old cells.

## Honest notes

- **The compression is not new.** Context mixing and rANS are known techniques. Archives made of independently compressed blocks also exist, for example zstd seekable and SquashFS.
- **What this project adds** is the combination, written in Oberon and running on a phone:
  - search inside the archive without decoding it;
  - the Egg-primed independent cells;
  - the duplicated Egg;
  - the Ash report;
  - cube addressing.
- **Price of random access.** The cube is 10–40% larger than the solid archive. On data that is already compressed (JPEG, PDF, very small files) it is 1–5% larger than ZIP, because every cell starts cold on such data.
- **Search limits.** It finds text at the start of words, and it skips cells that are not text.

## Files

- `Z7Arch6.apk`: the Android app (package `ro.jahbalon.z7arch6`, arm64).
- `Z7Arch6.Mod`: the complete Oberon-07 source: engine, format and user interface. Romanian identifiers are explained in its header.
- `EcranNativ.java` and `ecran-z7c.dex`: the Android window. It handles the file picker, the `Download/Z7Arch` folder, "Open with" and "Share". Its comments are in Romanian.
- `FaZ7.java`: builds and signs the APK with the Byz7 tools.
- `BENCHMARK.txt`: the raw benchmark numbers.
- `screens.png`: screenshots of the cube, a search, the Ash and the ADD screen.

Motto: *E pur si torque.*
