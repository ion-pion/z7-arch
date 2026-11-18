MODULE Z7Arch6;  (* Z7 ARCH 6 - the cube archiver, English edition (18 Nov 2026). Same engine and format as Z7 Arch 5.
     Idea (Pion): "a way of packing data, but in the cube, with search and partial extraction:
     if I only want one piece, I don't unpack everything. Something modular. 64 KB cells,
     with Salamandra and Cubicum FS."
     A .z7c archive (format 5; format 4 can also be read):
       - All files are joined end to end and cut into CELLS of 64 KB.
       - THE EGG (Salamandra, "Ou" in the code): up to 16 KB sampled evenly from the compressible files.
         The model (context mixing: 6 context orders, a match model, SSE, binary rANS; the same engine as
         Z7 Arch 1-3) reads the Egg first and learns from it. That state is saved, and every cell starts
         from it, never from the previous cell. So each cell can be decoded on its own: for one file you
         read only its cells. The Egg is stored twice; if the first copy is damaged, the second is used.
       - THE MAP (Cubicum FS): every cell has an address in the 7x7x7 cube. The Egg sits in the centre
         (3,3,3); cells fill the shells around it (26 + 98 + 218 = 342 per cube); after 342 comes cube 2,
         up to 7 cubes. The map holds the files (where they start in the stream), the cells (size,
         compressed size, Adler checksum) and, for text cells only, a 4096-bit FINGERPRINT of the words
         they contain: a search decodes only the cells that can contain the word.
       - THE ASH (Salamandra, "Cenusa" in the code): a damaged cell burns alone; files that do not touch
         it come out whole, and VERIFY shows the Ash (which cells and which files burned).
       - MODULAR: ADD puts new files into an archive: old cells are copied as they are, only new cells
         are compressed, with the same Egg.
     Window: ecran-z7c.dex (Android file picker, Download/Z7Arch, "Open with", "Share").
     The search keyboard is drawn here, in Oberon.
     Glossary of Romanian names in the code: Ou = Egg, Cenusa = Ash, Celula = cell, Amprenta = fingerprint,
       Strange = compress, Desface = decode, Scoate = extract, Cauta = search, Adauga = add, cub = cube.
     Pion (Ion Paraschiv) & Claude, 18.11.2026 *)

  IMPORT Ecran, Grafica, Fisier, Ceas;

  CONST
    TB = 2097152;      (* probability table: 2^21 *)
    CS = 65536;        (* one cell: 64 KB *)
    L = 8388608;       (* 2^23: lower bound of the rANS state *)
    NI = 8; NO = 6;    (* mixer inputs; context models *)
    MB = 131072;       (* match history: the Egg + one cell *)
    MH = 262144;       (* match table *)
    LIM = 10;
    MOD32 = 65521;     (* Adler *)
    EGG = 16384;       (* the Egg: at most 16 KB *)
    PC = 342;          (* cells in a cube, without the centre *)
    NC = 2394;         (* 7 cubes *)
    FPB = 512;         (* fingerprint: 512 bytes = 4096 bits *)
    FB = FPB * 8;
    NF = 128;          (* files in an archive *)
    NH = 40;           (* search results *)
    NIMIC = 0; ALEGE = 1; SALVEZ = 2; ARHIVA = 3; DOSAR = 4; ADAUG = 5;   (* what we are waiting for from Android *)
    ACASA = 0; CUB = 1; CAUTA = 2;                                       (* screens *)

  VAR
    (* the model *)
    t: ARRAY TB OF INTEGER;
    w: ARRAY 256 * NI OF INTEGER;
    sq: ARRAY 33 OF INTEGER; st: ARRAY 4096 OF INTEGER;
    ord, hb, idx, s: ARRAY NI OF INTEGER;
    hist: ARRAY 8 OF INTEGER;
    c0, pm, pa, ab: INTEGER;
    buf: ARRAY MB OF CHAR; mt: ARRAY MH OF INTEGER; pos, mptr, mlen, mbit, mi: INTEGER;
    mm: ARRAY 64 OF INTEGER;
    ap: ARRAY 256 * 33 OF INTEGER;
    (* the state after the Egg: every cell starts from here *)
    t2: ARRAY TB OF INTEGER;
    w2: ARRAY 256 * NI OF INTEGER;
    hb2: ARRAY NI OF INTEGER; hist2: ARRAY 8 OF INTEGER;
    buf2: ARRAY MB OF CHAR; mt2: ARRAY MH OF INTEGER; mm2: ARRAY 64 OF INTEGER; ap2: ARRAY 256 * 33 OF INTEGER;
    c02, pos2, mptr2, mlen2, mbit2: INTEGER;
    (* the block *)
    blk: ARRAY CS OF INTEGER;
    pr: ARRAY CS * 8 OF INTEGER;
    ob: ARRAY CS + CS DIV 4 + 64 OF INTEGER;
    hin, hout, written, inByte, ms1, ms2: INTEGER;
    bad: BOOLEAN;
    (* map of the open archive *)
    fNm: ARRAY NF, 64 OF CHAR; fStart, fLen, fS1, fS2: ARRAY NF OF INTEGER; fArs, fScos: ARRAY NF OF BOOLEAN; nfa: INTEGER;
    cRaw, cComp, cS1, cS2, cOff, cBeg: ARRAY NC OF INTEGER; cArs, cMarc, cFp: ARRAY NC OF BOOLEAN; nca, ver, sarite: INTEGER;
    fp: ARRAY NC * FPB OF CHAR;
    eggLen, eggC, eggS1, eggS2, dataStart, oulBun, citite, ultimCel: INTEGER;   (* oulBun: 0 burned, 1 first copy, 2 second copy *)
    deschisa: BOOLEAN;
    ax, ay, az: ARRAY PC OF INTEGER; loc: ARRAY 343 OF INTEGER;   (* addresses in the cube *)
    (* the screen *)
    W, H, bx, bw, bh, by1, by2, by3, ultimTap, astept, ecr, prim, cubAr, rx, ry, rw, rh: INTEGER;
    nume: ARRAY NF, 80 OF CHAR; marime: ARRAY NF OF INTEGER; nf: INTEGER;
    scos: ARRAY NF, 80 OF CHAR; ns: INTEGER;
    stari: ARRAY 6, 40 OF CHAR; stc: ARRAY 6 OF INTEGER;
    fond, aur, alb, gri, violet, verde, rosu, panou, inchis: INTEGER;
    sir: ARRAY 80 OF CHAR; ls: INTEGER;
    arhNume, arhBaza, rasp, gol: ARRAY 80 OF CHAR;
    kr: ARRAY 4, 12 OF CHAR; kx0, kw, kh, ky0: INTEGER;
    q: ARRAY 40 OF CHAR; nq: INTEGER;
    hitF: ARRAY NH OF INTEGER; hitS: ARRAY NH, 40 OF CHAR; nh, candC: INTEGER;
    info: ARRAY 80 OF CHAR;
    qb1, qb2: ARRAY 20 OF INTEGER; nqb: INTEGER;
    h1, h2, hl: INTEGER;


  (* ---------- the model (same as Z7 Arch 1-3) ---------- *)

  PROCEDURE Squash(d: INTEGER): INTEGER;
    VAR r, qq, f: INTEGER;
  BEGIN
    IF d > 2047 THEN r := 4095
    ELSIF d < -2047 THEN r := 0
    ELSE f := d MOD 128; qq := d DIV 128 + 16; r := (sq[qq] * (128 - f) + sq[qq + 1] * f + 64) DIV 128
    END
    RETURN r
  END Squash;

  PROCEDURE Hashes;
    VAR k, j, h: INTEGER;
  BEGIN
    FOR k := 0 TO NO - 1 DO
      h := (k + 1) * 7777;
      FOR j := 1 TO ord[k] DO h := (h * 263 + hist[j] + 1) MOD 1048573 END;
      hb[k] := h
    END
  END Hashes;

  PROCEDURE Match;
    VAR h, k: INTEGER;
  BEGIN
    buf[pos MOD MB] := CHR(hist[1]); INC(pos);
    IF (mlen > 0) & (ORD(buf[mptr MOD MB]) = hist[1]) THEN INC(mlen); INC(mptr)
    ELSE mlen := 0
    END;
    h := hb[NO - 1] MOD MH;
    IF (mlen = 0) & (pos > 6) THEN
      mptr := mt[h];
      IF (mptr > 0) & (pos - mptr < MB - 8) THEN
        k := 0;
        WHILE (k < 32) & (mptr - k > 0) & (ORD(buf[(mptr - k - 1) MOD MB]) = ORD(buf[(pos - k - 1) MOD MB])) DO INC(k) END;
        mlen := k
      END
    END;
    mt[h] := pos;
    IF mlen > 0 THEN mbit := ORD(buf[mptr MOD MB]) + 256 ELSE mbit := 0 END
  END Match;

  PROCEDURE Reset;
    VAR i, x, v, p: INTEGER;
  BEGIN
    sq[0] := 1; sq[1] := 2; sq[2] := 3; sq[3] := 6; sq[4] := 10; sq[5] := 16; sq[6] := 27; sq[7] := 45;
    sq[8] := 73; sq[9] := 120; sq[10] := 194; sq[11] := 310; sq[12] := 488; sq[13] := 747; sq[14] := 1101;
    sq[15] := 1546; sq[16] := 2047; sq[17] := 2549; sq[18] := 2994; sq[19] := 3348; sq[20] := 3607;
    sq[21] := 3785; sq[22] := 3901; sq[23] := 3975; sq[24] := 4022; sq[25] := 4050; sq[26] := 4068;
    sq[27] := 4079; sq[28] := 4085; sq[29] := 4089; sq[30] := 4092; sq[31] := 4093; sq[32] := 4094;
    p := 0;
    FOR x := -2047 TO 2047 DO
      v := Squash(x);
      FOR i := p TO v DO st[i] := x END;
      IF v + 1 > p THEN p := v + 1 END
    END;
    FOR i := p TO 4095 DO st[i] := 2047 END;
    FOR i := 0 TO TB - 1 DO t[i] := 32768 * 64 END;
    FOR i := 0 TO 256 * NI - 1 DO
      IF i MOD NI = NI - 1 THEN w[i] := 0 ELSE w[i] := 5000 END
    END;
    FOR i := 0 TO MH - 1 DO mt[i] := 0 END;
    FOR i := 0 TO 63 DO mm[i] := 32768 END;
    FOR i := 0 TO 256 * 33 - 1 DO ap[i] := Squash((i MOD 33) * 128 - 2048) * 16 END;
    pos := 0; mptr := 0; mlen := 0; mbit := 0;
    ord[0] := 0; ord[1] := 1; ord[2] := 2; ord[3] := 3; ord[4] := 4; ord[5] := 6;
    FOR i := 0 TO 7 DO hist[i] := 0 END;
    c0 := 1; Hashes
  END Reset;

  PROCEDURE Save;   (* remember the state after the Egg *)
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO TB - 1 DO t2[i] := t[i] END;
    FOR i := 0 TO 256 * NI - 1 DO w2[i] := w[i] END;
    FOR i := 0 TO 256 * 33 - 1 DO ap2[i] := ap[i] END;
    FOR i := 0 TO MH - 1 DO mt2[i] := mt[i] END;
    FOR i := 0 TO MB - 1 DO buf2[i] := buf[i] END;
    FOR i := 0 TO 63 DO mm2[i] := mm[i] END;
    FOR i := 0 TO NI - 1 DO hb2[i] := hb[i] END;
    FOR i := 0 TO 7 DO hist2[i] := hist[i] END;
    c02 := c0; pos2 := pos; mptr2 := mptr; mlen2 := mlen; mbit2 := mbit
  END Save;

  PROCEDURE Restore;   (* back to the state after the Egg *)
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO TB - 1 DO t[i] := t2[i] END;
    FOR i := 0 TO 256 * NI - 1 DO w[i] := w2[i] END;
    FOR i := 0 TO 256 * 33 - 1 DO ap[i] := ap2[i] END;
    FOR i := 0 TO MH - 1 DO mt[i] := mt2[i] END;
    FOR i := 0 TO MB - 1 DO buf[i] := buf2[i] END;
    FOR i := 0 TO 63 DO mm[i] := mm2[i] END;
    FOR i := 0 TO NI - 1 DO hb[i] := hb2[i] END;
    FOR i := 0 TO 7 DO hist[i] := hist2[i] END;
    c0 := c02; pos := pos2; mptr := mptr2; mlen := mlen2; mbit := mbit2
  END Restore;

  PROCEDURE Bits(): INTEGER;
    VAR n, c: INTEGER;
  BEGIN n := 0; c := c0; WHILE c > 1 DO c := c DIV 2; INC(n) END
    RETURN n
  END Bits;

  PROCEDURE Min(a, b: INTEGER): INTEGER;
  BEGIN IF b < a THEN a := b END
    RETURN a
  END Min;

  PROCEDURE Max(a, b: INTEGER): INTEGER;
  BEGIN IF b > a THEN a := b END
    RETURN a
  END Max;

  PROCEDURE Predict(): INTEGER;
    VAR i, dot, b, k, f: INTEGER;
  BEGIN
    b := c0 * NI; dot := 0;
    FOR i := 0 TO NO - 1 DO
      idx[i] := (hb[i] * 271 + c0 * 4099) MOD TB;
      s[i] := st[t[idx[i]] DIV 1024];
      dot := dot + w[b + i] * s[i]
    END;
    IF (mbit > 0) & (mbit DIV LSL(1, 8 - Bits()) = c0) THEN
      k := mbit DIV LSL(1, 7 - Bits()) MOD 2; mi := Min(mlen, 31) * 2 + k;
      s[NO] := st[mm[mi] DIV 16]
    ELSE mi := -1; s[NO] := 0
    END;
    dot := dot + w[b + NO] * s[NO];
    s[NI - 1] := 256; dot := dot + w[b + NI - 1] * 256;
    pm := Squash(dot DIV 16384);
    IF pm < 1 THEN pm := 1 ELSIF pm > 4095 THEN pm := 4095 END;
    k := st[pm] + 2048; ab := c0 * 33 + k DIV 128; f := k MOD 128;
    pa := (ap[ab] * (128 - f) + ap[ab + 1] * f) DIV 2048;
    k := (pm + 3 * pa) DIV 4;
    IF k < 1 THEN k := 1 ELSIF k > 4095 THEN k := 4095 END
    RETURN k
  END Predict;

  PROCEDURE Update(y: INTEGER);
    VAR i, err, b, p, k: INTEGER;
  BEGIN
    err := y * 4095 - pm; b := c0 * NI;
    FOR i := 0 TO NI - 1 DO
      k := w[b + i] + s[i] * err DIV 8192;
      IF k > 65535 THEN k := 65535 ELSIF k < -65535 THEN k := -65535 END;
      w[b + i] := k
    END;
    FOR i := 0 TO NO - 1 DO
      p := t[idx[i]]; k := p MOD 64; p := p DIV 64;
      p := p + (y * 65535 - p) * 2 DIV (2 * k + 3);
      IF k < LIM THEN INC(k) END;
      t[idx[i]] := p * 64 + k
    END;
    IF mi >= 0 THEN p := mm[mi]; mm[mi] := p + (y * 65535 - p) DIV 32 END;
    IF (mbit > 0) & (mbit DIV LSL(1, 7 - Bits()) MOD 2 # y) THEN mlen := 0; mbit := 0 END;
    ap[ab] := ap[ab] + (y * 65535 - ap[ab]) DIV 64; ap[ab + 1] := ap[ab + 1] + (y * 65535 - ap[ab + 1]) DIV 64;
    c0 := c0 * 2 + y;
    IF c0 >= 256 THEN
      FOR i := 7 TO 2 BY -1 DO hist[i] := hist[i - 1] END;
      hist[1] := c0 - 256; c0 := 1; Hashes; Match
    END
  END Update;

  (* ---------- bytes and numbers ---------- *)

  PROCEDURE Put(b: INTEGER);
  BEGIN Fisier.Scrie(hout, b); INC(written); ms1 := (ms1 + b) MOD MOD32; ms2 := (ms2 + ms1) MOD MOD32
  END Put;

  PROCEDURE PutInt(x: INTEGER);
  BEGIN Put(x DIV 16777216 MOD 256); Put(x DIV 65536 MOD 256); Put(x DIV 256 MOD 256); Put(x MOD 256)
  END PutInt;

  PROCEDURE Get(): INTEGER;
    VAR b: INTEGER;
  BEGIN b := Fisier.Citeste(hin);
    IF b < 0 THEN bad := TRUE; b := 0 ELSE INC(inByte); ms1 := (ms1 + b) MOD MOD32; ms2 := (ms2 + ms1) MOD MOD32 END
    RETURN b
  END Get;

  PROCEDURE GetInt(): INTEGER;
    VAR x: INTEGER;
  BEGIN x := Get(); x := x * 256 + Get(); x := x * 256 + Get(); x := x * 256 + Get()
    RETURN x
  END GetInt;

  PROCEDURE Cop(VAR de, la: ARRAY OF CHAR);   (* one string into another, whatever their lengths *)
    VAR i: INTEGER;
  BEGIN i := 0; WHILE (i < LEN(la) - 1) & (i < LEN(de)) & (de[i] # 0X) DO la[i] := de[i]; INC(i) END; la[i] := 0X
  END Cop;

  PROCEDURE Copiaza(de, la: ARRAY OF CHAR);   (* a whole file *)
    VAR a, b, c: INTEGER;
  BEGIN
    a := Fisier.Deschide(de); b := Fisier.Creeaza(la);
    IF (a >= 0) & (b >= 0) THEN c := Fisier.Citeste(a); WHILE c >= 0 DO Fisier.Scrie(b, c); c := Fisier.Citeste(a) END END;
    IF a >= 0 THEN Fisier.Gata(a) END; IF b >= 0 THEN Fisier.Gata(b) END
  END Copiaza;

  PROCEDURE CopiazaIn(de: ARRAY OF CHAR);   (* a whole file, appended to hout *)
    VAR a, c: INTEGER;
  BEGIN
    a := Fisier.Deschide(de);
    IF a >= 0 THEN c := Fisier.Citeste(a); WHILE c >= 0 DO Put(c); c := Fisier.Citeste(a) END; Fisier.Gata(a) END
  END CopiazaIn;

  (* ---------- one block: a cell or the Egg ---------- *)

  PROCEDURE PackBlock(n: INTEGER);
    VAR i, k, b, y, p, f, st0, x, no, c: INTEGER;
  BEGIN
    k := 0;
    FOR i := 0 TO n - 1 DO
      c := blk[i];
      FOR b := 7 TO 0 BY -1 DO
        y := c DIV LSL(1, b) MOD 2; pr[k] := Predict(); Update(y); INC(k)
      END
    END;
    x := L; no := 0;
    FOR k := n * 8 - 1 TO 0 BY -1 DO
      y := blk[k DIV 8] DIV LSL(1, 7 - k MOD 8) MOD 2; p := pr[k];
      IF y = 1 THEN f := p; st0 := 0 ELSE f := 4096 - p; st0 := p END;
      WHILE x >= 524288 * f DO ob[no] := x MOD 256; INC(no); x := x DIV 256 END;
      x := x DIV f * 4096 + x MOD f + st0
    END;
    PutInt(n);
    IF no + 8 < n THEN PutInt(no); PutInt(x); FOR i := no - 1 TO 0 BY -1 DO Put(ob[i]) END
    ELSE PutInt(0); PutInt(0); FOR i := 0 TO n - 1 DO Put(blk[i]) END
    END
  END PackBlock;

  PROCEDURE UnpackBlock(n: INTEGER; VAR s1, s2: INTEGER);   (* into blk *)
    VAR i, j, y, p, f, st0, x, no, r, c, start: INTEGER;
  BEGIN
    no := GetInt(); x := GetInt(); start := inByte;
    IF (no = 0) & (x = 0) THEN
      FOR i := 0 TO n - 1 DO
        c := Get();
        FOR j := 7 TO 0 BY -1 DO p := Predict(); Update(c DIV LSL(1, j) MOD 2) END;
        s1 := (s1 + c) MOD MOD32; s2 := (s2 + s1) MOD MOD32; blk[i] := c
      END;
      no := n
    ELSE
      i := 0;
      WHILE (i < n) & ~bad DO
        c := 0;
        FOR j := 0 TO 7 DO
          p := Predict(); r := x MOD 4096;
          IF r < p THEN y := 1; f := p; st0 := 0 ELSE y := 0; f := 4096 - p; st0 := p END;
          x := f * (x DIV 4096) + r - st0;
          WHILE (x < L) & ~bad DO x := x * 256 + Get() END;
          Update(y); c := c * 2 + y
        END;
        s1 := (s1 + c) MOD MOD32; s2 := (s2 + s1) MOD MOD32; blk[i] := c; INC(i)
      END
    END;
    IF inByte - start # no THEN bad := TRUE END
  END UnpackBlock;

  (* ---------- fingerprint: the words of a cell ---------- *)

  PROCEDURE Low(c: INTEGER): INTEGER;
  BEGIN IF (c >= 65) & (c <= 90) THEN c := c + 32 END
    RETURN c
  END Low;

  PROCEDURE Litera(c: INTEGER): BOOLEAN;   (* part of a word *)
  BEGIN RETURN (c >= 97) & (c <= 122) OR (c >= 48) & (c <= 57) OR (c >= 128)
  END Litera;

  PROCEDURE Pune(k, b: INTEGER);
    VAR i, v: INTEGER;
  BEGIN i := k * FPB + b DIV 8; v := ORD(fp[i]);
    IF v DIV LSL(1, b MOD 8) MOD 2 = 0 THEN fp[i] := CHR(v + LSL(1, b MOD 8)) END
  END Pune;

  PROCEDURE Are(k, b: INTEGER): BOOLEAN;
  BEGIN RETURN ORD(fp[k * FPB + b DIV 8]) DIV LSL(1, b MOD 8) MOD 2 = 1
  END Are;

  PROCEDURE Cuvant(c: INTEGER): BOOLEAN;   (* one more character; TRUE when a valid word has ended *)
    VAR gata: BOOLEAN;
  BEGIN
    gata := FALSE; c := Low(c);
    IF Litera(c) THEN
      IF hl < 6 THEN h1 := (h1 * 31 + c) MOD 1000003; h2 := (h2 * 37 + c + 1) MOD 999983 END;   (* the first 6 letters *)
      INC(hl)
    ELSE gata := hl >= 3; IF ~gata THEN h1 := 0; h2 := 0; hl := 0 END
    END
    RETURN gata
  END Cuvant;

  PROCEDURE Amprenta(k, n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO FPB - 1 DO fp[k * FPB + i] := 0X END;
    h1 := 0; h2 := 0; hl := 0;
    FOR i := 0 TO n DO
      IF i < n THEN IF Cuvant(blk[i]) THEN Pune(k, h1 MOD FB); Pune(k, h2 MOD FB); h1 := 0; h2 := 0; hl := 0 END
      ELSIF Cuvant(32) THEN Pune(k, h1 MOD FB); Pune(k, h2 MOD FB); h1 := 0; h2 := 0; hl := 0
      END
    END
  END Amprenta;

  (* ---------- the cube: cell addresses ---------- *)

  PROCEDURE Adrese;   (* the shells around the centre (3,3,3) *)
    VAR d, x, y, z, j, m: INTEGER;
  BEGIN
    j := 0;
    FOR d := 1 TO 3 DO
      FOR z := 0 TO 6 DO FOR y := 0 TO 6 DO FOR x := 0 TO 6 DO
        m := Max(Max(ABS(x - 3), ABS(y - 3)), ABS(z - 3));
        IF m = d THEN ax[j] := x; ay[j] := y; az[j] := z; loc[x + 7 * y + 49 * z] := j; INC(j) END
      END END END
    END;
    loc[3 + 21 + 147] := -1
  END Adrese;

  (* ---------- screen: strings ---------- *)

  PROCEDURE Clr; BEGIN ls := 0; sir[0] := 0X END Clr;

  PROCEDURE Add(tx: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN i := 0;
    WHILE (i < LEN(tx)) & (tx[i] # 0X) & (ls < 78) DO sir[ls] := tx[i]; INC(ls); INC(i) END;
    sir[ls] := 0X
  END Add;

  PROCEDURE AddN(n: INTEGER);
    VAR d: ARRAY 12 OF CHAR; k: INTEGER;
  BEGIN
    IF n < 0 THEN Add("-"); n := -n END;
    k := 0; REPEAT d[k] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(k) UNTIL n = 0;
    WHILE (k > 0) & (ls < 78) DO DEC(k); sir[ls] := d[k]; INC(ls) END;
    sir[ls] := 0X
  END AddN;

  PROCEDURE AddK(n: INTEGER);   (* bytes, readable: 123 KB, 4.5 MB *)
  BEGIN
    IF n < 10240 THEN AddN(n); Add(" B")
    ELSIF n < 10485760 THEN AddN(n DIV 1024); Add(" KB")
    ELSE AddN(n DIV 1048576); Add("."); AddN(n * 10 DIV 1048576 MOD 10); Add(" MB")
    END
  END AddK;

  PROCEDURE AddAdr(k: INTEGER);   (* address of cell k, as in Cubicum FS: C1(2,3,3) *)
    VAR j: INTEGER;
  BEGIN j := k MOD PC;
    Add("C"); AddN(k DIV PC + 1); Add("("); AddN(ax[j]); Add(","); AddN(ay[j]); Add(","); AddN(az[j]); Add(")")
  END AddAdr;

  PROCEDURE Stare(c: INTEGER);
    VAR i, j: INTEGER;
  BEGIN
    FOR i := 0 TO 4 DO stari[i] := stari[i + 1]; stc[i] := stc[i + 1] END;
    j := 0; WHILE (j < 39) & (sir[j] # 0X) DO stari[5, j] := sir[j]; INC(j) END; stari[5, j] := 0X; stc[5] := c
  END Stare;

  PROCEDURE Spune(tx: ARRAY OF CHAR; c: INTEGER);
  BEGIN Clr; Add(tx); Stare(c)
  END Spune;

  PROCEDURE Baza(VAR cale, b: ARRAY OF CHAR);
    VAR i, k, j: INTEGER;
  BEGIN
    i := 0; k := 0; WHILE (i < LEN(cale)) & (cale[i] # 0X) DO IF cale[i] = "/" THEN k := i + 1 END; INC(i) END;
    j := 0; WHILE (k < i) & (j < LEN(b) - 1) DO b[j] := cale[k]; INC(j); INC(k) END; b[j] := 0X
  END Baza;

  PROCEDURE FaraPunct(VAR b: ARRAY OF CHAR);   (* cut the extension *)
    VAR i, k: INTEGER;
  BEGIN i := 0; k := -1;
    WHILE (i < LEN(b)) & (b[i] # 0X) DO IF b[i] = "." THEN k := i END; INC(i) END;
    IF k > 0 THEN b[k] := 0X END
  END FaraPunct;

  PROCEDURE Lungime(VAR n: ARRAY OF CHAR): INTEGER;
    VAR h, b, k: INTEGER;
  BEGIN k := 0; h := Fisier.Deschide(n);
    IF h >= 0 THEN b := Fisier.Citeste(h); WHILE b >= 0 DO INC(k); b := Fisier.Citeste(h) END; Fisier.Gata(h) END
    RETURN k
  END Lungime;

  PROCEDURE CitesteLista;
    VAR h, b, j: INTEGER;
  BEGIN
    nf := 0; h := Fisier.Deschide("alese.txt");
    IF h >= 0 THEN
      b := Fisier.Citeste(h);
      WHILE (b >= 0) & (nf < NF) DO
        j := 0;
        WHILE (b >= 0) & (b # 10) DO IF j < 79 THEN nume[nf, j] := CHR(b); INC(j) END; b := Fisier.Citeste(h) END;
        nume[nf, j] := 0X; IF j > 0 THEN INC(nf) END;
        IF b = 10 THEN b := Fisier.Citeste(h) END
      END;
      Fisier.Gata(h)
    END
  END CitesteLista;

  PROCEDURE Cere(cod, multe: INTEGER);
  BEGIN Fisier.Sterge("raspuns.txt"); Ecran.Nota(cod, multe, 1)
  END Cere;

  PROCEDURE Raspuns(): INTEGER;
    VAR h, b, r, j: INTEGER; tx: ARRAY 80 OF CHAR;
  BEGIN
    r := -1; h := Fisier.Deschide("raspuns.txt");
    IF h >= 0 THEN
      j := 0; b := Fisier.Citeste(h);
      WHILE (b >= 0) & (b # 10) & (j < 79) DO tx[j] := CHR(b); INC(j); b := Fisier.Citeste(h) END;
      tx[j] := 0X; Fisier.Gata(h); Fisier.Sterge("raspuns.txt");
      rasp := tx;
      IF (tx[0] = "O") & (tx[1] = "K") THEN r := 1
      ELSIF tx[0] = "A" THEN r := 0; Spune("CANCELLED", gri)
      ELSE r := 0; tx[38] := 0X; Spune(tx, rosu)
      END
    END
    RETURN r
  END Raspuns;

  PROCEDURE Scrie(h: INTEGER; VAR tx: ARRAY OF CHAR);   (* one line in a text file *)
    VAR i: INTEGER;
  BEGIN i := 0; WHILE (i < LEN(tx)) & (tx[i] # 0X) DO Fisier.Scrie(h, ORD(tx[i])); INC(i) END; Fisier.Scrie(h, 10)
  END Scrie;

  PROCEDURE Progres(tx: ARRAY OF CHAR; i, n: INTEGER);   (* one frame: what I'm doing and how far along *)
  BEGIN
    Grafica.Dreptunghi(20, H DIV 2 - 70, W - 40, 140, panou);
    Grafica.Text(40, H DIV 2 - 44, tx, 4, aur);
    IF n > 0 THEN
      Grafica.Dreptunghi(40, H DIV 2 + 14, W - 80, 24, inchis);
      Grafica.Dreptunghi(40, H DIV 2 + 14, (W - 80) * Min(i, n) DIV n, 24, violet)
    END;
    Ecran.Arata
  END Progres;

  (* ---------- packing into the cube ---------- *)

  PROCEDURE Text(n: INTEGER): BOOLEAN;   (* is blk[0..n) text? at least 3/4 printable characters or whitespace *)
    VAR i, k, c: INTEGER;
  BEGIN k := 0;
    FOR i := 0 TO n - 1 DO c := blk[i]; IF (c >= 32) & (c < 127) OR (c = 9) OR (c = 10) OR (c = 13) THEN INC(k) END END
    RETURN k * 4 >= n * 3
  END Text;

  PROCEDURE Celula(n: INTEGER);   (* blk[0..n) becomes cell nca, written to corp.tmp (hout) *)
    VAR i, a1, a2, w0: INTEGER;
  BEGIN
    a1 := 1; a2 := 0; FOR i := 0 TO n - 1 DO a1 := (a1 + blk[i]) MOD MOD32; a2 := (a2 + a1) MOD MOD32 END;
    cFp[nca] := Text(n); IF cFp[nca] THEN Amprenta(nca, n) END;
    IF nca = 0 THEN cBeg[0] := 0; cOff[0] := 0
    ELSE cBeg[nca] := cBeg[nca - 1] + cRaw[nca - 1]; cOff[nca] := cOff[nca - 1] + cComp[nca - 1]
    END;
    Restore; w0 := written; PackBlock(n);
    cRaw[nca] := n; cComp[nca] := written - w0; cS1[nca] := a1; cS2[nca] := a2;
    cArs[nca] := FALSE; cMarc[nca] := FALSE; INC(nca)
  END Celula;

  PROCEDURE Viu(VAR n: ARRAY OF CHAR): BOOLEAN;   (* compressible? the 16 most frequent byte values in the first 4 KB *)
    VAR h, b, k, i, j, m, sus: INTEGER; cnt: ARRAY 256 OF INTEGER;
  BEGIN
    FOR i := 0 TO 255 DO cnt[i] := 0 END; k := 0; sus := 0;
    h := Fisier.Deschide(n);
    IF h >= 0 THEN
      b := Fisier.Citeste(h); WHILE (b >= 0) & (k < 4096) DO INC(cnt[b]); INC(k); b := Fisier.Citeste(h) END; Fisier.Gata(h)
    END;
    FOR j := 1 TO 16 DO   (* the 16 largest *)
      m := 0; FOR i := 1 TO 255 DO IF cnt[i] > cnt[m] THEN m := i END END;
      sus := sus + cnt[m]; cnt[m] := -1
    END
    RETURN (k > 0) & (sus * 5 > k)   (* over 20%: text or something with patterns; noise (photos, archives) stays out *)
  END Viu;

  PROCEDURE Ou(VAR total: INTEGER);   (* the Egg: samples from the compressible files; written to ou.tmp *)
    VAR i, k, h, b, cat, a1, a2, w0, nv, pas, urm, felie: INTEGER; viu: ARRAY NF OF BOOLEAN;
  BEGIN
    eggLen := 0;
    IF total > CS THEN
      nv := 0; FOR i := 0 TO nf - 1 DO viu[i] := Viu(nume[i]); IF viu[i] THEN INC(nv) END END;
      (* 1 KB slices taken at equal distances over the whole stream: every cell finds its words in the Egg *)
      cat := Min(EGG, total DIV 8); k := 0;
      IF cat >= 1024 THEN pas := total DIV (cat DIV 1024) ELSE pas := total + 1 END;
      urm := pas DIV 2;
      FOR i := 0 TO nf - 1 DO
        IF viu[i] THEN h := Fisier.Deschide(nume[i]) ELSE h := -1 END;
        IF h >= 0 THEN
          b := Fisier.Citeste(h); felie := 0;
          WHILE (b >= 0) & (eggLen < cat) DO
            IF k >= urm THEN felie := 1024; urm := urm + pas END;
            IF felie > 0 THEN blk[eggLen] := b; INC(eggLen); DEC(felie) END;
            INC(k); b := Fisier.Citeste(h)
          END;
          Fisier.Gata(h)
        ELSE k := k + marime[i]
        END
      END
    END;
    a1 := 1; a2 := 0; FOR i := 0 TO eggLen - 1 DO a1 := (a1 + blk[i]) MOD MOD32; a2 := (a2 + a1) MOD MOD32 END;
    eggS1 := a1; eggS2 := a2;
    Reset;
    hout := Fisier.Creeaza("ou.tmp"); w0 := written;
    IF eggLen > 0 THEN PackBlock(eggLen) END;   (* the model has learned the Egg *)
    eggC := written - w0; Fisier.Gata(hout);
    Save
  END Ou;

  PROCEDURE ScrieArhiva(VAR nm: ARRAY OF CHAR): BOOLEAN;   (* header + map + the Egg twice + the cells *)
    VAR i, j, len, e1, e2: INTEGER; ok: BOOLEAN;
  BEGIN
    hout := Fisier.Creeaza(nm); ok := hout >= 0;
    IF ok THEN
      written := 0; Put(ORD("Z")); Put(ORD("7")); Put(ORD("C")); Put(5);
      ms1 := 1; ms2 := 0;
      PutInt(nfa); PutInt(nca); PutInt(CS); PutInt(eggLen); PutInt(eggC); PutInt(eggS1); PutInt(eggS2);
      FOR i := 0 TO nfa - 1 DO
        len := 0; WHILE (len < 63) & (fNm[i, len] # 0X) DO INC(len) END;
        Put(len); FOR j := 0 TO len - 1 DO Put(ORD(fNm[i, j])) END;
        PutInt(fStart[i]); PutInt(fLen[i]); PutInt(fS1[i]); PutInt(fS2[i])
      END;
      FOR i := 0 TO nca - 1 DO
        PutInt(cRaw[i]); PutInt(cComp[i]); PutInt(cS1[i]); PutInt(cS2[i]);
        IF cFp[i] THEN Put(1); FOR j := 0 TO FPB - 1 DO Put(ORD(fp[i * FPB + j])) END ELSE Put(0) END
      END;
      e1 := ms1; e2 := ms2; PutInt(e1); PutInt(e2);
      CopiazaIn("ou.tmp"); CopiazaIn("ou.tmp");
      CopiazaIn("corp.tmp");
      Fisier.Gata(hout)
    END;
    Fisier.Sterge("ou.tmp"); Fisier.Sterge("corp.tmp")
    RETURN ok
  END ScrieArhiva;

  PROCEDURE Strange(VAR intrat: INTEGER): BOOLEAN;   (* the files in nume[] become new cells, in corp.tmp *)
    VAR i, h, b, n, a1, a2, sum, dus: INTEGER; ok: BOOLEAN; nm: ARRAY 80 OF CHAR;
  BEGIN
    sum := 0; FOR i := 0 TO nf - 1 DO sum := sum + marime[i] END;
    IF nca > 0 THEN dus := cBeg[nca - 1] + cRaw[nca - 1] ELSE dus := 0 END;
    ok := (nfa + nf <= NF) & (nca + (sum + CS - 1) DIV CS <= NC);
    IF ok THEN
      n := 0; intrat := 0;
      FOR i := 0 TO nf - 1 DO
        Baza(nume[i], nm); nm[63] := 0X; Cop(nm, fNm[nfa]); fStart[nfa] := dus + intrat;
        a1 := 1; a2 := 0;
        h := Fisier.Deschide(nume[i]);
        IF h >= 0 THEN
          b := Fisier.Citeste(h);
          WHILE b >= 0 DO
            blk[n] := b; INC(n); INC(intrat); a1 := (a1 + b) MOD MOD32; a2 := (a2 + a1) MOD MOD32;
            IF n = CS THEN Celula(n); n := 0; Progres("PACKING...", intrat, sum) END;
            b := Fisier.Citeste(h)
          END;
          Fisier.Gata(h)
        END;
        fLen[nfa] := dus + intrat - fStart[nfa]; fS1[nfa] := a1; fS2[nfa] := a2;
        fArs[nfa] := FALSE; fScos[nfa] := FALSE; INC(nfa)
      END;
      IF n > 0 THEN Celula(n) END
    END
    RETURN ok
  END Strange;

  (* ---------- reading the cube ---------- *)

  PROCEDURE Sari(la: INTEGER);   (* no seek in files: read up to there *)
    VAR b: INTEGER;
  BEGIN
    IF inByte > la THEN Fisier.Gata(hin); hin := Fisier.Deschide("deschisa.z7c"); inByte := 0 END;
    IF hin < 0 THEN bad := TRUE END;
    WHILE (inByte < la) & ~bad DO b := Get() END
  END Sari;

  PROCEDURE Desface(k: INTEGER): BOOLEAN;   (* cell k into blk; hin is open *)
    VAR n, s1, s2: INTEGER;
  BEGIN
    IF k # ultimCel THEN
      bad := FALSE; Sari(dataStart + cOff[k]);
      Restore; n := GetInt();
      IF bad OR (n # cRaw[k]) THEN bad := TRUE
      ELSE s1 := 1; s2 := 0; UnpackBlock(n, s1, s2); IF (s1 # cS1[k]) OR (s2 # cS2[k]) THEN bad := TRUE END
      END;
      INC(citite);
      IF bad THEN cArs[k] := TRUE; ultimCel := -1 ELSE ultimCel := k END
    END
    RETURN k = ultimCel
  END Desface;

  PROCEDURE OuDin(): BOOLEAN;   (* the Egg from the archive: the model reads it and learns; hin is at its start *)
    VAR n, s1, s2, start: INTEGER; ok: BOOLEAN;
  BEGIN
    start := inByte; Reset; ok := TRUE;
    IF eggLen > 0 THEN
      bad := FALSE; n := GetInt(); ok := ~bad & (n = eggLen) & (n <= CS);
      IF ok THEN s1 := 1; s2 := 0; UnpackBlock(n, s1, s2); ok := ~bad & (s1 = eggS1) & (s2 = eggS2) END
    END;
    IF ok THEN oulBun := 1; Save
    ELSE
      bad := FALSE; Sari(start + eggC); Reset;   (* the first Egg burned: the second one *)
      n := GetInt(); ok := ~bad & (n = eggLen) & (n <= CS);
      IF ok THEN s1 := 1; s2 := 0; UnpackBlock(n, s1, s2); ok := ~bad & (s1 = eggS1) & (s2 = eggS2) END;
      IF ok THEN oulBun := 2; Save ELSE oulBun := 0 END
    END;
    dataStart := start + 2 * eggC
    RETURN ok
  END OuDin;

  PROCEDURE Deschide(): BOOLEAN;   (* deschisa.z7c (the open archive): map + Egg *)
    VAR i, j, len, e1, e2, cs: INTEGER; ok: BOOLEAN;
  BEGIN
    deschisa := FALSE; ultimCel := -1;
    hin := Fisier.Deschide("deschisa.z7c"); bad := FALSE; inByte := 0; ok := FALSE;
    IF hin < 0 THEN Spune("ARCHIVE NOT FOUND", rosu)
    ELSIF (Get() # ORD("Z")) OR (Get() # ORD("7")) THEN Spune("NOT A Z7 ARCH ARCHIVE", rosu); Fisier.Gata(hin)
    ELSE
      i := Get(); j := Get();
      IF (i = ORD("A")) & (j = 1) THEN Spune("THIS IS A Z7 ARCH 3 ARCHIVE (.Z7A):", rosu); Spune("OPEN IT WITH Z7 ARCH 3", gri); Fisier.Gata(hin)
      ELSIF (i # ORD("C")) OR (j < 4) OR (j > 5) THEN Spune("NOT A Z7 ARCH CUBE (4 OR 5)", rosu); Fisier.Gata(hin)
      ELSE
        ver := j;
        ms1 := 1; ms2 := 0;
        nfa := GetInt(); nca := GetInt(); cs := GetInt(); eggLen := GetInt(); eggC := GetInt(); eggS1 := GetInt(); eggS2 := GetInt();
        IF bad OR (nfa < 0) OR (nfa > NF) OR (nca < 0) OR (nca > NC) OR (cs # CS) OR (eggLen > EGG) THEN bad := TRUE
        ELSE
          i := 0;
          WHILE (i < nfa) & ~bad DO
            len := Get(); IF len > 63 THEN bad := TRUE; len := 0 END;
            FOR j := 0 TO len - 1 DO fNm[i, j] := CHR(Get()) END; fNm[i, len] := 0X;
            fStart[i] := GetInt(); fLen[i] := GetInt(); fS1[i] := GetInt(); fS2[i] := GetInt();
            fArs[i] := FALSE; fScos[i] := FALSE; INC(i)
          END;
          i := 0;
          WHILE (i < nca) & ~bad DO
            cRaw[i] := GetInt(); cComp[i] := GetInt(); cS1[i] := GetInt(); cS2[i] := GetInt();
            IF ver = 4 THEN cFp[i] := TRUE ELSE cFp[i] := Get() = 1 END;
            IF cFp[i] THEN FOR j := 0 TO FPB - 1 DO fp[i * FPB + j] := CHR(Get()) END END;
            IF i = 0 THEN cBeg[0] := 0; cOff[0] := 0
            ELSE cBeg[i] := cBeg[i - 1] + cRaw[i - 1]; cOff[i] := cOff[i - 1] + cComp[i - 1]
            END;
            IF (cRaw[i] < 1) OR (cRaw[i] > CS) THEN bad := TRUE END;
            cArs[i] := FALSE; cMarc[i] := FALSE; INC(i)
          END
        END;
        e1 := ms1; e2 := ms2;
        IF bad OR (GetInt() # e1) OR (GetInt() # e2) THEN Spune("THE MAP BURNED: CANNOT READ CUBE", rosu); Fisier.Gata(hin)
        ELSE
          IF ~OuDin() THEN Spune("THE EGG BURNED (BOTH COPIES)", rosu)
          ELSIF oulBun = 2 THEN Spune("FIRST EGG BURNED, USING THE SECOND", violet)
          END;
          Fisier.Gata(hin);
          deschisa := TRUE; ok := TRUE; prim := 0; cubAr := 0; nh := 0
        END
      END
    END
    RETURN ok
  END Deschide;

  (* ---------- what the user does with the cube ---------- *)

  PROCEDURE Scoate(f: INTEGER): BOOLEAN;   (* only the cells of file f; output in scos/; hin is open *)
    VAR k, i, a, b, p0, p1, s1, s2, h: INTEGER; ok: BOOLEAN; cale: ARRAY 80 OF CHAR;
  BEGIN
    cale := "scos/"; i := 0; WHILE fNm[f, i] # 0X DO cale[5 + i] := fNm[f, i]; INC(i) END; cale[5 + i] := 0X;
    h := Fisier.Creeaza(cale); ok := h >= 0; s1 := 1; s2 := 0;
    p0 := fStart[f]; p1 := p0 + fLen[f]; k := 0;
    WHILE ok & (k < nca) DO
      IF (cBeg[k] < p1) & (cBeg[k] + cRaw[k] > p0) THEN
        cMarc[k] := TRUE;
        IF Desface(k) THEN
          a := Max(p0, cBeg[k]) - cBeg[k]; b := Min(p1, cBeg[k] + cRaw[k]) - cBeg[k];
          FOR i := a TO b - 1 DO Fisier.Scrie(h, blk[i]); s1 := (s1 + blk[i]) MOD MOD32; s2 := (s2 + s1) MOD MOD32 END
        ELSE ok := FALSE
        END
      END;
      INC(k)
    END;
    IF h >= 0 THEN Fisier.Gata(h) END;
    IF ok & ((s1 # fS1[f]) OR (s2 # fS2[f])) THEN ok := FALSE END;
    IF ok THEN
      fScos[f] := TRUE; IF ns < NF THEN scos[ns] := cale; INC(ns) END
    ELSE fArs[f] := TRUE; Fisier.Sterge(cale)
    END
    RETURN ok
  END Scoate;

  PROCEDURE Livreaza;   (* the files in scos[] go to Download/Z7Arch/<archive>/ *)
    VAR h, i: INTEGER;
  BEGIN
    Fisier.Sterge("cerere.txt"); h := Fisier.Creeaza("cerere.txt");
    IF h >= 0 THEN
      Scrie(h, arhBaza); FOR i := 0 TO ns - 1 DO Scrie(h, scos[i]) END; Fisier.Gata(h)
    END;
    Cere(-5, 0); astept := DOSAR
  END Livreaza;

  PROCEDURE Deschide1(f: INTEGER);   (* just one file *)
    VAR t0, k: INTEGER;
  BEGIN
    IF oulBun = 0 THEN Spune("THE EGG BURNED: CANNOT DECODE", rosu)
    ELSE
      Progres("EXTRACTING...", 0, 0);
      FOR k := 0 TO nca - 1 DO cMarc[k] := FALSE END;
      t0 := Ceas.Ms(); citite := 0; ns := 0; ultimCel := -1;
      hin := Fisier.Deschide("deschisa.z7c"); inByte := 0; bad := FALSE;
      IF Scoate(f) THEN
        Clr; Add("READ "); AddN(citite); Add(" OF "); AddN(nca); Add(" CELLS, ");
        AddN((Ceas.Ms() - t0) DIV 100 DIV 10); Add("."); AddN((Ceas.Ms() - t0) DIV 100 MOD 10); Add(" S"); Stare(verde);
        Livreaza
      ELSE Clr; Add("BURNED: "); Add(fNm[f]); Stare(rosu)
      END;
      Fisier.Gata(hin)
    END
  END Deschide1;

  PROCEDURE Tot;
    VAR f, nb: INTEGER;
  BEGIN
    IF oulBun = 0 THEN Spune("THE EGG BURNED: CANNOT DECODE", rosu)
    ELSE
      FOR f := 0 TO nca - 1 DO cMarc[f] := FALSE END;
      citite := 0; ns := 0; ultimCel := -1; nb := 0;
      hin := Fisier.Deschide("deschisa.z7c"); inByte := 0; bad := FALSE;
      FOR f := 0 TO nfa - 1 DO
        Progres("EXTRACTING ALL...", f, nfa);
        IF ~Scoate(f) THEN INC(nb) END
      END;
      Fisier.Gata(hin);
      Clr; AddN(ns); Add(" FILE(S) GOOD"); Stare(verde);
      IF nb > 0 THEN Clr; Add("ASH: "); AddN(nb); Add(" FILE(S) BURNED"); Stare(rosu) END;
      IF ns > 0 THEN Livreaza END
    END
  END Tot;

  PROCEDURE Verifica;   (* every cell, with its checksum; the Ash: what burned *)
    VAR k, f, nb, na: INTEGER; ok: BOOLEAN;
  BEGIN
    IF oulBun = 0 THEN Spune("ASH: THE EGG BURNED, CUBE IS DEAD", rosu)
    ELSE
      citite := 0; ultimCel := -1; nb := 0;
      hin := Fisier.Deschide("deschisa.z7c"); inByte := 0; bad := FALSE;
      FOR k := 0 TO nca - 1 DO
        Progres("VERIFYING...", k, nca);
        cMarc[k] := FALSE; ok := Desface(k); IF ~ok THEN INC(nb) END
      END;
      Fisier.Gata(hin);
      na := 0;
      FOR f := 0 TO nfa - 1 DO
        FOR k := 0 TO nca - 1 DO
          IF cArs[k] & (cBeg[k] < fStart[f] + fLen[f]) & (cBeg[k] + cRaw[k] > fStart[f]) THEN fArs[f] := TRUE END
        END;
        IF fArs[f] THEN INC(na) END
      END;
      IF (nb = 0) & (oulBun = 1) THEN Clr; Add("ALL "); AddN(nca); Add(" CELLS ARE GOOD"); Stare(verde)
      ELSE
        IF oulBun = 2 THEN Spune("ASH: FIRST EGG (SECOND ONE WORKS)", violet) END;
        k := 0;
        WHILE k < nca DO
          IF cArs[k] THEN Clr; Add("ASH: CELL "); AddAdr(k); Stare(rosu) END; INC(k)
        END;
        Clr; AddN(na); Add(" FILE(S) HIT, "); AddN(nfa - na); Add(" WHOLE"); Stare(alb)
      END
    END
  END Verifica;

  PROCEDURE Fragment(k, i: INTEGER);   (* the result: the file and the surrounding line *)
    VAR p, f, a, j, c: INTEGER;
  BEGIN
    p := cBeg[k] + i; f := 0;
    WHILE (f < nfa - 1) & ~((p >= fStart[f]) & (p < fStart[f] + fLen[f])) DO INC(f) END;
    hitF[nh] := f;
    j := 0; a := i; WHILE (a > 0) & (i - a < 10) & (blk[a - 1] # 10) DO DEC(a) END;
    WHILE (j < 38) & (a < cRaw[k]) & (blk[a] # 10) DO
      c := blk[a]; IF (c < 32) OR (c > 126) THEN c := 32 END;
      hitS[nh, j] := CHR(c); INC(j); INC(a)
    END;
    hitS[nh, j] := 0X; INC(nh)
  END Fragment;

  PROCEDURE Gaseste(k: INTEGER);   (* the word in cell k (already in blk) *)
    VAR i, j, n: INTEGER; ok: BOOLEAN;
  BEGIN
    n := cRaw[k]; i := 0;
    WHILE (i <= n - nq) & (nh < NH) DO
      j := 0; ok := TRUE;
      IF (i > 0) & Litera(Low(blk[i - 1])) THEN ok := FALSE END;   (* at the start of a word *)
      WHILE ok & (j < nq) DO IF Low(blk[i + j]) # Low(ORD(q[j])) THEN ok := FALSE END; INC(j) END;
      IF ok THEN Fragment(k, i); i := i + nq ELSE INC(i) END
    END
  END Gaseste;

  PROCEDURE Cauta;
    VAR k, j, t0, cand: INTEGER; ok: BOOLEAN;
  BEGIN
    nh := 0;
    IF nq = 0 THEN info := "TYPE WHAT TO SEARCH FOR"
    ELSIF oulBun = 0 THEN info := "THE EGG BURNED: CANNOT SEARCH"
    ELSE
      t0 := Ceas.Ms();
      nqb := 0; h1 := 0; h2 := 0; hl := 0;   (* the query words: their fingerprint bits *)
      FOR j := 0 TO nq DO
        IF j < nq THEN ok := Cuvant(ORD(q[j])) ELSE ok := Cuvant(32) END;
        IF ok THEN
          IF ((j < nq) OR (hl >= 6)) & (nqb < 20) THEN qb1[nqb] := h1 MOD FB; qb2[nqb] := h2 MOD FB; INC(nqb) END;
          h1 := 0; h2 := 0; hl := 0
        END
      END;
      (* a short last word may be the start of a longer word: it does not go through the fingerprint *)
      citite := 0; cand := 0; ultimCel := -1; sarite := 0;
      hin := Fisier.Deschide("deschisa.z7c"); inByte := 0; bad := FALSE;
      FOR k := 0 TO nca - 1 DO
        cMarc[k] := FALSE;
        ok := cFp[k]; j := 0; IF ~ok THEN INC(sarite) END;
        WHILE ok & (j < nqb) DO ok := Are(k, qb1[j]) & Are(k, qb2[j]); INC(j) END;
        IF ok & (nh < NH) THEN
          INC(cand); Progres("SEARCHING...", k, nca);
          IF Desface(k) THEN j := nh; Gaseste(k); IF nh > j THEN cMarc[k] := TRUE END END
        END
      END;
      Fisier.Gata(hin);
      Clr; AddN(nh); IF nh >= NH THEN Add("+") END; Add(" FOUND, READ "); AddN(citite); Add(" OF "); AddN(nca);
      IF sarite > 0 THEN Add(" (NO TEXT: "); AddN(sarite); Add(")") END;
      info := sir;
      Clr; Add("SEARCHED: "); FOR j := 0 TO nq - 1 DO sir[ls] := q[j]; INC(ls) END; sir[ls] := 0X; Stare(alb);
      Clr; Add(info); Stare(verde)
    END
  END Cauta;

  PROCEDURE Impacheteaza;
    VAR i, intrat, t0: INTEGER; nm: ARRAY 80 OF CHAR;
  BEGIN
    IF nf = 0 THEN Spune("CHOOSE FILES FIRST", rosu)
    ELSE
      Progres("MAKING EGG...", 0, 0); t0 := Ceas.Ms();
      intrat := 0; FOR i := 0 TO nf - 1 DO intrat := intrat + marime[i] END;
      nfa := 0; nca := 0; written := 0;
      Ou(intrat);
      hout := Fisier.Creeaza("corp.tmp"); written := 0;
      IF ~Strange(intrat) THEN Fisier.Gata(hout); Spune("TOO MUCH: MAX 7 CUBES, 128 FILES", rosu)
      ELSE
        Fisier.Gata(hout);
        Baza(nume[0], nm); FaraPunct(nm); nm[60] := 0X; arhBaza := nm;
        i := 0; WHILE nm[i] # 0X DO INC(i) END;
        nm[i] := "."; nm[i + 1] := "z"; nm[i + 2] := "7"; nm[i + 3] := "c"; nm[i + 4] := 0X; arhNume := nm;
        IF ScrieArhiva(arhNume) THEN
          Clr; AddK(intrat); Add(" -> "); AddK(written);
          IF intrat > 0 THEN Add(" ("); AddN(written * 100 DIV intrat); Add("%)") END; Stare(verde);
          Clr; AddN(nca); Add(" CELLS, "); AddN((nca + PC - 1) DIV PC); Add(" CUBE(S), ");
          AddN((Ceas.Ms() - t0) DIV 100 DIV 10); Add("."); AddN((Ceas.Ms() - t0) DIV 100 MOD 10); Add(" S"); Stare(alb);
          Copiaza(arhNume, "deschisa.z7c");
          IF Deschide() THEN ecr := CUB END;
          gol[0] := 0X; Fisier.Sterge("cerere.txt"); i := Fisier.Creeaza("cerere.txt");
          IF i >= 0 THEN Scrie(i, gol); Scrie(i, arhNume); Fisier.Gata(i) END;
          Cere(-5, 0); astept := SALVEZ
        ELSE Spune("CANNOT WRITE ARCHIVE", rosu)
        END
      END;
      nf := 0
    END
  END Impacheteaza;

  PROCEDURE Adauga;   (* new files (nume[]) into an open cube: the old cells stay as they are *)
    VAR i, h, b, intrat, vechi, t0: INTEGER;
  BEGIN
    IF oulBun = 0 THEN Spune("THE EGG BURNED: CANNOT ADD", rosu)
    ELSE
      Progres("ADDING...", 0, 0); t0 := Ceas.Ms();
      (* the old Egg, as it is: the good copy *)
      hin := Fisier.Deschide("deschisa.z7c"); inByte := 0; bad := FALSE;
      Sari(dataStart - 2 * eggC + (oulBun - 1) * eggC);
      hout := Fisier.Creeaza("ou.tmp"); FOR i := 1 TO eggC DO Fisier.Scrie(hout, Get()) END; Fisier.Gata(hout);
      (* the old cells, as they are *)
      Sari(dataStart);
      hout := Fisier.Creeaza("corp.tmp"); written := 0; vechi := 0;
      IF nca > 0 THEN vechi := cOff[nca - 1] + cComp[nca - 1] END;
      FOR i := 1 TO vechi DO Put(Get()) END;
      Fisier.Gata(hin);
      h := nca; b := nfa;
      FOR i := 0 TO nf - 1 DO marime[i] := Lungime(nume[i]) END;
      IF bad OR ~Strange(intrat) THEN Fisier.Gata(hout); Spune("CANNOT ADD (TOO MANY?)", rosu); nca := h; nfa := b
      ELSE
        Fisier.Gata(hout);
        i := 0; WHILE arhBaza[i] # 0X DO arhNume[i] := arhBaza[i]; INC(i) END;
        arhNume[i] := "."; arhNume[i + 1] := "z"; arhNume[i + 2] := "7"; arhNume[i + 3] := "c"; arhNume[i + 4] := 0X;
        IF ScrieArhiva(arhNume) THEN
          Clr; Add("+"); AddN(nfa - b); Add(" FILE(S), +"); AddN(nca - h); Add(" NEW CELLS"); Stare(verde);
          Clr; Add("THE "); AddN(h); Add(" OLD ONES COPIED, NOT REPACKED"); Stare(alb);
          Copiaza(arhNume, "deschisa.z7c");
          IF Deschide() THEN ecr := CUB END;
          gol[0] := 0X; Fisier.Sterge("cerere.txt"); i := Fisier.Creeaza("cerere.txt");
          IF i >= 0 THEN Scrie(i, gol); Scrie(i, arhNume); Fisier.Gata(i) END;
          Cere(-5, 0); astept := SALVEZ
        ELSE Spune("CANNOT WRITE ARCHIVE", rosu)
        END
      END;
      nf := 0
    END
  END Adauga;

  PROCEDURE DeschideAleasa;   (* nume[0] is the chosen or received archive *)
    VAR nm: ARRAY 80 OF CHAR;
  BEGIN
    Progres("OPENING...", 0, 0);
    Copiaza(nume[0], "deschisa.z7c");
    Baza(nume[0], nm); FaraPunct(nm); nm[60] := 0X;
    IF Deschide() THEN
      arhBaza := nm; ecr := CUB;
      Clr; Add("CUBE OPEN: "); AddN(nfa); Add(" FILES, "); AddN(nca); Add(" CELLS"); Stare(verde);
      Spune("TAP A FILE TO EXTRACT IT", gri)
    END;
    nf := 0
  END DeschideAleasa;

  (* ---------- drawing ---------- *)

  PROCEDURE Buton(x, y, bw0, bh0: INTEGER; tx: ARRAY OF CHAR; m, c, f: INTEGER);
    VAR n: INTEGER;
  BEGIN
    Grafica.Dreptunghi(x, y, bw0, bh0, f);
    n := 0; WHILE (n < LEN(tx)) & (tx[n] # 0X) DO INC(n) END;
    Grafica.Text(x + (bw0 - n * 6 * m) DIV 2, y + (bh0 - 7 * m) DIV 2, tx, m, c)
  END Buton;

  PROCEDURE Starea;
    VAR i, y: INTEGER;
  BEGIN
    y := H - 230;
    Grafica.Dreptunghi(bx, y - 10, bw, 2, panou);
    FOR i := 0 TO 5 DO Grafica.Text(bx, y + i * 32, stari[i], 2, stc[i]) END;
    IF astept # NIMIC THEN Grafica.Text(bx, H - 36, "WAITING FOR ANDROID...", 2, violet) END
  END Starea;

  PROCEDURE Titlu;
  BEGIN
    Grafica.Dreptunghi(0, 0, W, H, fond);
    Grafica.Text(bx, 24, "Z7 ARCH 6", 6, aur);
    Grafica.Text(bx, 76, "THE CUBE: SEARCH, TAKE ONLY WHAT YOU NEED", 2, gri)
  END Titlu;

  PROCEDURE DeseneazaAcasa;
    VAR i, y, k: INTEGER; nm: ARRAY 80 OF CHAR;
  BEGIN
    IF astept = NIMIC THEN k := panou ELSE k := gri END;
    Buton(bx, by1, bw, bh, "CHOOSE FILES", 4, alb, k);
    IF (nf > 0) & (astept = NIMIC) THEN Buton(bx, by2, bw, bh, "MAKE CUBE", 4, fond, aur) ELSE Buton(bx, by2, bw, bh, "MAKE CUBE", 4, gri, panou) END;
    Buton(bx, by3, bw, bh, "OPEN A CUBE", 4, alb, k);
    y := by3 + bh + 30;
    IF nf > 0 THEN
      Clr; AddN(nf); Add(" FILE(S) CHOSEN:"); Grafica.Text(bx, y, sir, 2, violet); y := y + 26;
      i := 0;
      WHILE (i < nf) & (y < H - 270) DO
        Baza(nume[i], nm); nm[26] := 0X; Grafica.Text(bx, y, nm, 2, alb);
        Clr; AddK(marime[i]); Grafica.Text(W - bx - ls * 12, y, sir, 2, gri); y := y + 24; INC(i)
      END;
      IF i < nf THEN Clr; Add("... AND "); AddN(nf - i); Grafica.Text(bx, y, sir, 2, gri) END
    ELSIF deschisa THEN
      Buton(bx, y, bw, 60, "BACK TO THE OPEN CUBE", 2, violet, inchis)
    END
  END DeseneazaAcasa;

  PROCEDURE DeseneazaCub;   (* 7 layers (z = 0..6), each 7 x 7; the centre is the Egg *)
    VAR x, y, z, k, j, c, x0, y0, p, nc: INTEGER;
  BEGIN
    p := 10; nc := (nca + PC - 1) DIV PC; IF nc < 1 THEN nc := 1 END;
    x0 := (W - (7 * 7 * p + 6 * 4)) DIV 2; y0 := rx;
    FOR z := 0 TO 6 DO
      FOR y := 0 TO 6 DO FOR x := 0 TO 6 DO
        j := loc[x + 7 * y + 49 * z];
        IF j < 0 THEN
          IF (cubAr = 0) & (eggLen > 0) THEN IF oulBun = 0 THEN c := rosu ELSE c := aur END ELSE c := inchis END
        ELSE
          k := cubAr * PC + j;
          IF k >= nca THEN c := inchis
          ELSIF cArs[k] THEN c := rosu
          ELSIF cMarc[k] THEN c := verde
          ELSE c := violet
          END
        END;
        Grafica.Dreptunghi(x0 + z * (7 * p + 4) + x * p, y0 + y * p, p - 1, p - 1, c)
      END END
    END;
    Clr; Add("CUBE "); AddN(cubAr + 1); Add(" OF "); AddN(nc);
    IF nc > 1 THEN Add("  (TAP IT: NEXT)") END;
    Grafica.Text(x0, y0 + 7 * p + 8, sir, 2, gri)
  END DeseneazaCub;

  PROCEDURE DeseneazaArhiva;
    VAR i, y, c, n, bw4: INTEGER; nm: ARRAY 80 OF CHAR;
  BEGIN
    Clr; Add(arhBaza); Add(".Z7C"); sir[38] := 0X; Grafica.Text(bx, 100, sir, 2, alb);
    Clr; AddN(nfa); Add(" FILES  "); AddN(nca); Add(" CELLS OF 64 KB");
    Grafica.Text(bx, 124, sir, 2, gri);
    rx := 152; DeseneazaCub;
    bw4 := (bw - 3 * 8) DIV 4; y := 260;
    IF astept = NIMIC THEN c := panou ELSE c := gri END;
    Buton(bx, y, bw4, 60, "SEARCH", 2, aur, c);
    Buton(bx + bw4 + 8, y, bw4, 60, "VERIFY", 2, alb, c);
    Buton(bx + 2 * (bw4 + 8), y, bw4, 60, "ALL", 2, alb, c);
    Buton(bx + 3 * (bw4 + 8), y, bw4, 60, "ADD", 2, alb, c);
    Grafica.Text(W - bx - 60, 24, "HOME", 2, violet);
    y := 336;
    Clr; Add("TAP A FILE: ONLY IT COMES OUT"); Grafica.Text(bx, y, sir, 2, violet);
    IF nfa > 14 THEN Grafica.Text(W - bx - 84, y, "<   >", 2, aur) END;
    y := 366; n := 0; i := prim;
    WHILE (i < nfa) & (n < 14) DO
      IF fArs[i] THEN c := rosu ELSIF fScos[i] THEN c := verde ELSE c := alb END;
      Cop(fNm[i], nm); nm[26] := 0X; Grafica.Text(bx, y, nm, 2, c);
      Clr; AddK(fLen[i]); Grafica.Text(W - bx - ls * 12, y, sir, 2, gri);
      y := y + 32; INC(i); INC(n)
    END
  END DeseneazaArhiva;

  PROCEDURE Tasta(x, y, w0: INTEGER; tx: ARRAY OF CHAR);
  BEGIN Buton(x + 2, y + 2, w0 - 4, kh - 4, tx, 3, alb, panou)
  END Tasta;

  PROCEDURE DeseneazaCauta;
    VAR i, r, x, y, n, w4: INTEGER; ch: ARRAY 2 OF CHAR; nm: ARRAY 80 OF CHAR;
  BEGIN
    Grafica.Text(bx, 100, "SEARCH THE CUBE:", 2, gri);
    Grafica.Dreptunghi(bx, 124, bw, 52, inchis);
    Clr; FOR i := 0 TO nq - 1 DO sir[ls] := q[i]; INC(ls) END; sir[ls] := "<"; sir[ls + 1] := 0X;
    Grafica.Text(bx + 10, 136, sir, 4, aur);
    y := 194; i := 0;
    WHILE (i < nh) & (y < ky0 - 110) DO
      Cop(fNm[hitF[i]], nm); nm[38] := 0X; Grafica.Text(bx, y, nm, 2, verde);
      Grafica.Text(bx, y + 22, hitS[i], 2, alb); y := y + 52; INC(i)
    END;
    IF i < nh THEN Clr; Add("... AND "); AddN(nh - i); Grafica.Text(bx, y, sir, 2, gri) END;
    Grafica.Text(bx, ky0 - 70, info, 2, violet);
    IF nh > 0 THEN Grafica.Text(bx, ky0 - 42, "TAP A RESULT: ITS FILE COMES OUT", 2, gri) END;
    ch[1] := 0X;
    FOR r := 0 TO 3 DO
      n := 0; WHILE kr[r, n] # 0X DO INC(n) END;
      x := kx0 + (10 - n) * kw DIV 2; y := ky0 + r * kh;
      FOR i := 0 TO n - 1 DO ch[0] := kr[r, i]; Tasta(x + i * kw, y, kw, ch) END
    END;
    w4 := (W - 2 * kx0) DIV 4; y := ky0 + 4 * kh;
    Buton(kx0 + 2, y + 2, w4 - 4, kh - 4, "SPACE", 2, alb, panou);
    Buton(kx0 + w4 + 2, y + 2, w4 - 4, kh - 4, "DELETE", 2, alb, panou);
    Buton(kx0 + 2 * w4 + 2, y + 2, w4 - 4, kh - 4, "SEARCH", 2, fond, aur);
    Buton(kx0 + 3 * w4 + 2, y + 2, w4 - 4, kh - 4, "BACK", 2, alb, panou)
  END DeseneazaCauta;

  PROCEDURE Deseneaza;
  BEGIN
    Titlu;
    IF ecr = ACASA THEN DeseneazaAcasa; Starea
    ELSIF ecr = CUB THEN DeseneazaArhiva; Starea
    ELSE DeseneazaCauta
    END;
    Ecran.Arata
  END Deseneaza;

  (* ---------- touches ---------- *)

  PROCEDURE In(x, y, x0, y0, w0, h0: INTEGER): BOOLEAN;
  BEGIN RETURN (x >= x0) & (x < x0 + w0) & (y >= y0) & (y < y0 + h0)
  END In;

  PROCEDURE AtingeAcasa(x, y: INTEGER);
  BEGIN
    IF In(x, y, bx, by1, bw, bh) THEN Cere(-2, 1); astept := ALEGE; Spune("CHOOSE THE FILES IN ANDROID", alb)
    ELSIF In(x, y, bx, by2, bw, bh) THEN Impacheteaza
    ELSIF In(x, y, bx, by3, bw, bh) THEN Cere(-2, 0); astept := ARHIVA; Spune("CHOOSE THE .Z7C CUBE", alb)
    ELSIF (nf = 0) & deschisa & In(x, y, bx, by3 + bh + 30, bw, 60) THEN ecr := CUB
    END
  END AtingeAcasa;

  PROCEDURE AtingeArhiva(x, y: INTEGER);
    VAR bw4, i, nc: INTEGER;
  BEGIN
    bw4 := (bw - 3 * 8) DIV 4; nc := (nca + PC - 1) DIV PC;
    IF In(x, y, W - bx - 90, 0, 90 + bx, 70) THEN ecr := ACASA
    ELSIF In(x, y, 0, 150, W, 100) THEN IF nc > 1 THEN cubAr := (cubAr + 1) MOD nc END
    ELSIF In(x, y, bx, 260, bw4, 60) THEN ecr := CAUTA; IF nh = 0 THEN info := "TYPE A WORD (AT LEAST 3 LETTERS)" END
    ELSIF In(x, y, bx + bw4 + 8, 260, bw4, 60) THEN Verifica
    ELSIF In(x, y, bx + 2 * (bw4 + 8), 260, bw4, 60) THEN Tot
    ELSIF In(x, y, bx + 3 * (bw4 + 8), 260, bw4, 60) THEN Cere(-2, 1); astept := ADAUG; Spune("CHOOSE WHAT TO ADD", alb)
    ELSIF In(x, y, W - bx - 100, 326, 100, 36) & (nfa > 14) THEN
      IF x < W - bx - 50 THEN prim := Max(0, prim - 14) ELSIF prim + 14 < nfa THEN prim := prim + 14 END
    ELSIF y >= 360 THEN
      i := prim + (y - 360) DIV 32;
      IF (i < nfa) & (i - prim < 14) THEN Deschide1(i) END
    END
  END AtingeArhiva;

  PROCEDURE AtingeCauta(x, y: INTEGER);
    VAR r, i, n, x0, w4: INTEGER;
  BEGIN
    w4 := (W - 2 * kx0) DIV 4;
    IF y >= ky0 + 4 * kh THEN
      i := (x - kx0) DIV w4;
      IF i = 0 THEN IF nq < 30 THEN q[nq] := " "; INC(nq) END
      ELSIF i = 1 THEN IF nq > 0 THEN DEC(nq) END
      ELSIF i = 2 THEN Cauta
      ELSIF i = 3 THEN ecr := CUB
      END
    ELSIF y >= ky0 THEN
      r := (y - ky0) DIV kh;
      n := 0; WHILE kr[r, n] # 0X DO INC(n) END;
      x0 := kx0 + (10 - n) * kw DIV 2;
      IF x >= x0 THEN i := (x - x0) DIV kw; IF (i < n) & (nq < 30) THEN q[nq] := kr[r, i]; INC(nq) END END
    ELSIF (y >= 194) & (y < ky0 - 110) & (nh > 0) THEN
      i := (y - 194) DIV 52;
      IF i < nh THEN ecr := CUB; Deschide1(hitF[i]) END
    END
  END AtingeCauta;

  PROCEDURE Atingere;
    VAR tp, x, y: INTEGER;
  BEGIN
    tp := Ecran.Citeste(3);
    IF tp # ultimTap THEN
      ultimTap := tp; x := Ecran.Citeste(1); y := Ecran.Citeste(2);
      IF astept = NIMIC THEN
        IF ecr = ACASA THEN AtingeAcasa(x, y)
        ELSIF ecr = CUB THEN AtingeArhiva(x, y)
        ELSE AtingeCauta(x, y)
        END
      END
    END
  END Atingere;

  (* ---------- Android's answers ---------- *)

  PROCEDURE Unde;
    VAR i, k: INTEGER;
  BEGIN
    i := 0; k := 0; WHILE (rasp[i] # 0X) & (k < 2) DO IF rasp[i] = " " THEN INC(k) END; INC(i) END;
    Clr; WHILE (rasp[i] # 0X) & (ls < 38) DO sir[ls] := rasp[i]; INC(ls); INC(i) END; sir[ls] := 0X;
    IF ls = 0 THEN Add("THE CHOSEN FOLDER") END;
    Stare(alb)
  END Unde;

  PROCEDURE EArhiva(VAR n: ARRAY OF CHAR): BOOLEAN;   (* starts with Z7 ? *)
    VAR h, a, b: INTEGER;
  BEGIN a := 0; b := 0; h := Fisier.Deschide(n);
    IF h >= 0 THEN a := Fisier.Citeste(h); b := Fisier.Citeste(h); Fisier.Gata(h) END
    RETURN (a = ORD("Z")) & (b = ORD("7"))
  END EArhiva;

  PROCEDURE Primite;
    VAR h, b, i: INTEGER;
  BEGIN
    h := Fisier.Deschide("deschide.txt");
    IF h >= 0 THEN
      b := Fisier.Citeste(h); Fisier.Gata(h); Fisier.Sterge("deschide.txt");
      CitesteLista;
      IF nf > 0 THEN
        IF (nf = 1) & EArhiva(nume[0]) THEN Spune("CUBE RECEIVED", alb); DeschideAleasa
        ELSE
          FOR i := 0 TO nf - 1 DO marime[i] := Lungime(nume[i]) END;
          ecr := ACASA;
          Clr; AddN(nf); Add(" FILE(S) RECEIVED"); Stare(verde); Spune("PRESS MAKE CUBE", alb)
        END
      END
    END
  END Primite;

  PROCEDURE Asteapta;
    VAR r, i: INTEGER;
  BEGIN
    r := Raspuns();
    IF r >= 0 THEN
      IF astept = ALEGE THEN
        astept := NIMIC;
        IF r = 1 THEN
          CitesteLista;
          FOR i := 0 TO nf - 1 DO marime[i] := Lungime(nume[i]) END;
          Clr; AddN(nf); Add(" FILE(S) CHOSEN"); Stare(verde)
        END
      ELSIF astept = ARHIVA THEN
        astept := NIMIC;
        IF r = 1 THEN CitesteLista; IF nf > 0 THEN DeschideAleasa END END
      ELSIF astept = ADAUG THEN
        astept := NIMIC;
        IF r = 1 THEN CitesteLista; IF nf > 0 THEN Adauga END END
      ELSIF astept = SALVEZ THEN
        astept := NIMIC; IF r = 1 THEN Spune("THE CUBE IS IN:", verde); Unde END;
        Fisier.Sterge(arhNume)
      ELSIF astept = DOSAR THEN
        astept := NIMIC; IF r = 1 THEN Spune("EXTRACTED TO:", verde); Unde END;
        FOR i := 0 TO ns - 1 DO Fisier.Sterge(scos[i]) END; ns := 0
      END
    END
  END Asteapta;

  PROCEDURE Porneste;
    VAR i: INTEGER;
  BEGIN
    W := Ecran.Latime(); H := Ecran.Inaltime();
    bx := 20; bw := W - 40; bh := 84; by1 := 120; by2 := by1 + bh + 16; by3 := by2 + bh + 16;
    fond := Grafica.RGB(14, 4, 28); aur := Grafica.RGB(212, 160, 23); alb := Grafica.RGB(240, 235, 250);
    gri := Grafica.RGB(140, 130, 160); violet := Grafica.RGB(191, 128, 255); verde := Grafica.RGB(74, 222, 128);
    rosu := Grafica.RGB(239, 68, 68); panou := Grafica.RGB(52, 22, 86); inchis := Grafica.RGB(30, 12, 50);
    kr[0] := "1234567890"; kr[1] := "QWERTYUIOP"; kr[2] := "ASDFGHJKL"; kr[3] := "ZXCVBNM.-";
    kx0 := 10; kw := (W - 20) DIV 10; kh := 64; ky0 := H - 5 * kh - 16;
    FOR i := 0 TO 5 DO stari[i, 0] := 0X; stc[i] := alb END;
    nf := 0; ns := 0; nq := 0; nh := 0; nfa := 0; nca := 0; astept := NIMIC; ecr := ACASA; deschisa := FALSE;
    ultimTap := Ecran.Citeste(3); info[0] := 0X;
    Fisier.Sterge("raspuns.txt"); arhNume[0] := 0X; arhBaza[0] := 0X; rasp[0] := 0X;
    Adrese;
    Spune("CHOOSE FILES AND MAKE A .Z7C CUBE,", gri);
    Spune("OR OPEN A CUBE", gri)
  END Porneste;

BEGIN
  IF Ecran.Deschide() THEN
    Porneste;
    WHILE Ecran.Deschis() DO
      Atingere; IF astept # NIMIC THEN Asteapta ELSE Primite END;
      Deseneaza; Ceas.Asteapta(30)
    END
  END
END Z7Arch6.
