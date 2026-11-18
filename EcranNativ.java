package ro.jahbalon.eulaoberon;

/* ECRAN Z7 (18 nov 2026): fereastra aplicatiilor OLL facute cu ollapk, varianta pentru Z7 Arch.
   Acelasi contract ca ecran-gl4 pentru partea 2D: doua fisiere mapate in cache (ecran-nativ.fb si .in),
   programul ARM64 libjoc.so pornit cu EULA_ECRAN si HOME = dosarul aplicatiei; atingeri in .in (0 jos, 1 x,
   2 y, 3 numarul de atingeri), taste (15, 16), pauza (17), ceasul (13), cadre aratate (14).
   Nu are 3D, sunet sau vibratie. In schimb, coada de note (de la 64) poarta cereri spre Android:
     Nota(-2, 1, 0)  alege fisiere (1 = mai multe, 0 = unul): se copiaza in intrare/, lista in alese.txt
     Nota(-3, 0, 0)  salveaza: cerere.txt = randul 1 calea locala, randul 2 numele propus
     Nota(-4, 0, 0)  alege un dosar si copiaza acolo fisierele din cerere.txt (cate o cale pe rand)
     Nota(-5, 0, 0)  pune fisierele in Download/Z7Arch/<dosar>: cerere.txt = randul 1 dosarul (poate fi gol),
                     apoi cate o cale pe rand; daca Android-ul nu lasa (sub Android 10), intreaba de dosar ca -4
   La sfarsit scrie raspuns.txt: "OK n [unde]", "ANULAT" sau "EROARE ...".
   Z7 Arch 3: Android-ul ii poate da fisiere (Deschide cu / Trimite): le copiaza in intrare/, lista in alese.txt,
   apoi deschide.txt = "Z7A" (o arhiva de despachetat) sau "PACK" (fisiere de impachetat).
   Z7 Arch 4: si cuburile .z7c sunt arhive (deschide.txt = "Z7A"). Pion & Claude, 18.11.2026 */

public class EcranNativ extends android.app.Activity {
    static final int SCARA = 2;
    static final int ALEGE = 1, SALVEAZA = 2, DOSAR = 3;

    Panza panza;
    volatile android.graphics.Bitmap bmp;
    java.nio.MappedByteBuffer mf, mi;
    java.io.RandomAccessFile rf, ri;
    int fw, fh;
    volatile boolean gata;
    Process joc;
    long start;
    int atingeri, taste;

    class Panza extends android.view.View {
        final android.graphics.Paint p = new android.graphics.Paint();
        final android.graphics.Rect src = new android.graphics.Rect(), dst = new android.graphics.Rect();
        Panza(android.content.Context c) { super(c); p.setFilterBitmap(false); }
        protected void onSizeChanged(int w, int h, int ow, int oh) {
            if (bmp == null && w > 0 && h > 0) porneste(w, h);
        }
        protected void onDraw(android.graphics.Canvas c) {
            android.graphics.Bitmap b = bmp;
            if (b != null) {
                src.set(0, 0, b.getWidth(), b.getHeight());
                dst.set(0, 0, getWidth(), getHeight());
                c.drawBitmap(b, src, dst, p);
            }
        }
        public boolean onTouchEvent(android.view.MotionEvent e) { return atinge(e); }
    }

    protected void onCreate(android.os.Bundle b) {
        super.onCreate(b);
        panza = new Panza(this);
        setContentView(panza);
        panza.setFocusable(true);
        panza.setFocusableInTouchMode(true);
        panza.requestFocus();
        panza.setKeepScreenOn(true);
        start = System.currentTimeMillis();
        new java.io.File(getFilesDir(), "scos").mkdirs();     // aici despacheteaza Z7 Arch
        primite(getIntent());
    }

    void pune(int k, int v) {
        java.nio.MappedByteBuffer m = mi;
        if (m != null && k >= 0 && k < 64) m.putInt(k * 4, v);
    }

    static void inchideVechi(java.io.File f) {
        if (f.exists() && f.length() >= 32) {
            try {
                java.io.RandomAccessFile r = new java.io.RandomAccessFile(f, "rw");
                r.seek(20); r.write(new byte[] {1, 0, 0, 0}); r.close();
            } catch (Throwable t) { }
        }
    }

    void porneste(int w, int h) {
        final java.io.File cache = getCacheDir();
        try {
            java.io.File ffb = new java.io.File(cache, "ecran-nativ.fb");
            java.io.File fin = new java.io.File(cache, "ecran-nativ.in");
            inchideVechi(ffb);
            ffb.delete(); fin.delete();
            fw = w / SCARA; fh = h / SCARA;
            ri = new java.io.RandomAccessFile(fin, "rw");
            ri.setLength(1024);
            mi = ri.getChannel().map(java.nio.channels.FileChannel.MapMode.READ_WRITE, 0, 1024);
            mi.order(java.nio.ByteOrder.LITTLE_ENDIAN);
            long n = (long) fw * fh * 4 + 32;
            rf = new java.io.RandomAccessFile(ffb, "rw");
            rf.setLength(n);
            mf = rf.getChannel().map(java.nio.channels.FileChannel.MapMode.READ_WRITE, 0, n);
            mf.order(java.nio.ByteOrder.LITTLE_ENDIAN);
            mf.put(0, (byte) 'E'); mf.put(1, (byte) 'N'); mf.put(2, (byte) 'F'); mf.put(3, (byte) '1');
            mf.putInt(4, fw); mf.putInt(8, fh); mf.putInt(12, 0); mf.putInt(20, 0); mf.putInt(16, 1);
            bmp = android.graphics.Bitmap.createBitmap(fw, fh, android.graphics.Bitmap.Config.ARGB_8888);
            new Thread(new Runnable() { public void run() { arata(); } }, "ecran-z7").start();
            java.io.File lib = new java.io.File(getApplicationInfo().nativeLibraryDir, "libjoc.so");
            if (!lib.exists()) return;
            ProcessBuilder pb = new ProcessBuilder(lib.getAbsolutePath());
            pb.directory(getFilesDir());
            pb.environment().put("EULA_ECRAN", new java.io.File(cache, "ecran-nativ").getAbsolutePath());
            pb.environment().put("HOME", getFilesDir().getAbsolutePath());
            pb.redirectErrorStream(true);
            joc = pb.start();
            final java.io.InputStream out = joc.getInputStream();
            new Thread(new Runnable() { public void run() {   // ce scrie programul ajunge in joc.jurnal
                try {
                    java.io.FileOutputStream j = new java.io.FileOutputStream(new java.io.File(cache, "joc.jurnal"));
                    byte[] b = new byte[4096]; int k;
                    while ((k = out.read(b)) > 0) { j.write(b, 0, k); j.flush(); }
                    j.close();
                } catch (Throwable t) { }
            } }, "jurnal").start();
        } catch (Throwable t) {
            gata = true;
        }
    }

    void arata() {
        int ultim = -1, aratate = 0;
        while (!gata) {
            pune(13, (int) (System.currentTimeMillis() - start));
            int c = mf.getInt(12);
            if (c != ultim) {
                java.nio.ByteBuffer d = mf.duplicate();
                d.position(32); d.limit(fw * fh * 4 + 32);
                bmp.copyPixelsFromBuffer(d.slice());
                panza.postInvalidate();
                aratate++; pune(14, aratate);
                ultim = c;
            }
            cereri();
            try { Thread.sleep(8); } catch (Throwable t) { break; }
        }
    }

    void cereri() {   // coada de note: 64 = cate a scris programul, 65 = cate am citit noi
        java.nio.MappedByteBuffer m = mi;
        int w = m.getInt(256), r = m.getInt(260);
        if (w - r > 32 || w < r) r = w;
        while (r < w) {
            int b = ((r & 31) * 3 + 66) * 4;
            final int hz = m.getInt(b), ms = m.getInt(b + 4);
            r++;
            if (hz == -2 || hz == -3 || hz == -4 || hz == -5) {
                runOnUiThread(new Runnable() { public void run() { cere(hz, ms); } });
            }
        }
        m.putInt(260, r);
    }

    void cere(int hz, int ms) {
        try {
            android.content.Intent i;
            if (hz == -2) {
                i = new android.content.Intent("android.intent.action.OPEN_DOCUMENT");
                i.addCategory("android.intent.category.OPENABLE");
                i.setType("*/*");
                i.putExtra("android.intent.extra.ALLOW_MULTIPLE", ms == 1);
                startActivityForResult(i, ALEGE);
            } else if (hz == -3) {
                String[] c = cerere();
                i = new android.content.Intent("android.intent.action.CREATE_DOCUMENT");
                i.addCategory("android.intent.category.OPENABLE");
                i.setType("application/octet-stream");
                i.putExtra("android.intent.extra.TITLE", c.length > 1 ? c[1] : "arhiva.z7a");
                startActivityForResult(i, SALVEAZA);
            } else if (hz == -4) {
                i = new android.content.Intent("android.intent.action.OPEN_DOCUMENT_TREE");
                startActivityForResult(i, DOSAR);
            } else {
                new Thread(new Runnable() { public void run() { inDescarcari(); } }, "descarcari").start();
            }
        } catch (Throwable t) {
            raspuns("EROARE " + t);
        }
    }

    protected void onActivityResult(final int cerere, final int rezultat, final android.content.Intent date) {
        new Thread(new Runnable() { public void run() { primeste(cerere, rezultat, date); } }, "fisiere").start();
    }

    void primeste(int cerere, int rezultat, android.content.Intent date) {
        try {
            if (rezultat != -1 || date == null) { raspuns("ANULAT"); return; }
            android.content.ContentResolver cr = getContentResolver();
            if (cerere == ALEGE) {
                java.util.ArrayList<android.net.Uri> uri = new java.util.ArrayList<android.net.Uri>();
                android.content.ClipData cd = date.getClipData();
                if (cd != null) { for (int k = 0; k < cd.getItemCount(); k++) uri.add(cd.getItemAt(k).getUri()); }
                else if (date.getData() != null) uri.add(date.getData());
                java.io.File dir = new java.io.File(getFilesDir(), "intrare");
                sterge(dir); dir.mkdirs();
                StringBuilder lista = new StringBuilder();
                java.util.HashSet<String> folosite = new java.util.HashSet<String>();
                for (android.net.Uri u : uri) {
                    String nume = curat(nume(cr, u));
                    String n = nume; int k = 2;
                    while (folosite.contains(n.toLowerCase())) { n = k + "-" + nume; k++; }
                    folosite.add(n.toLowerCase());
                    copiaza(cr.openInputStream(u), new java.io.FileOutputStream(new java.io.File(dir, n)));
                    lista.append("intrare/").append(n).append('\n');
                }
                scrie(new java.io.File(getFilesDir(), "alese.txt"), lista.toString());
                raspuns("OK " + uri.size());
            } else if (cerere == SALVEAZA) {
                String[] c = cerere();
                copiaza(new java.io.FileInputStream(new java.io.File(getFilesDir(), c[0])), cr.openOutputStream(date.getData()));
                raspuns("OK 1");
            } else {
                android.net.Uri arbore = date.getData();
                android.net.Uri parinte = android.provider.DocumentsContract.buildDocumentUriUsingTree(arbore,
                    android.provider.DocumentsContract.getTreeDocumentId(arbore));
                String[] c = cerere(); int n = 0;
                for (int q = 1; q < c.length; q++) {
                    String cale = c[q];
                    if (cale.length() == 0) continue;
                    java.io.File f = new java.io.File(getFilesDir(), cale);
                    android.net.Uri doc = android.provider.DocumentsContract.createDocument(cr, parinte, "application/octet-stream", f.getName());
                    if (doc == null) continue;
                    copiaza(new java.io.FileInputStream(f), cr.openOutputStream(doc));
                    n++;
                }
                raspuns("OK " + n);
            }
        } catch (Throwable t) {
            raspuns("EROARE " + t);
        }
    }

    void inDescarcari() {   // -5: direct in Download/Z7Arch/<dosar>, fara intrebari (Android 10 si mai nou)
        String[] c = cerere();
        String sub = c.length > 0 ? curat(c[0]) : "";
        String unde = "Download/Z7Arch/" + (c.length > 0 && c[0].length() > 0 ? sub + "/" : "");
        try {
            android.content.ContentResolver cr = getContentResolver();
            android.net.Uri col = android.net.Uri.parse("content://media/external/downloads");
            int n = 0;
            for (int q = 1; q < c.length; q++) {
                if (c[q].length() == 0) continue;
                java.io.File f = new java.io.File(getFilesDir(), c[q]);
                android.content.ContentValues v = new android.content.ContentValues();
                v.put("_display_name", f.getName());
                v.put("mime_type", "application/octet-stream");
                v.put("relative_path", unde);
                android.net.Uri u = cr.insert(col, v);
                if (u == null) throw new java.io.IOException("insert");
                copiaza(new java.io.FileInputStream(f), cr.openOutputStream(u));
                n++;
            }
            raspuns("OK " + n + " " + unde);
        } catch (Throwable t) {   // Android vechi sau refuz: alegi tu dosarul
            runOnUiThread(new Runnable() { public void run() { cere(-4, 0); } });
        }
    }

    protected void onNewIntent(android.content.Intent i) {
        super.onNewIntent(i); setIntent(i); primite(i);
    }

    void primite(final android.content.Intent in) {   // Deschide cu / Trimite catre Z7 Arch
        if (in == null || in.getAction() == null) return;
        final String a = in.getAction();
        final java.util.ArrayList<android.net.Uri> uri = new java.util.ArrayList<android.net.Uri>();
        try {
            if (a.equals("android.intent.action.VIEW")) { if (in.getData() != null) uri.add(in.getData()); }
            else if (a.equals("android.intent.action.SEND")) {
                android.net.Uri u = in.getParcelableExtra("android.intent.extra.STREAM"); if (u != null) uri.add(u);
            } else if (a.equals("android.intent.action.SEND_MULTIPLE")) {
                java.util.ArrayList<android.net.Uri> l = in.getParcelableArrayListExtra("android.intent.extra.STREAM");
                if (l != null) uri.addAll(l);
            }
        } catch (Throwable t) { }
        if (uri.isEmpty()) return;
        new Thread(new Runnable() { public void run() {
            try {
                android.content.ContentResolver cr = getContentResolver();
                java.io.File dir = new java.io.File(getFilesDir(), "intrare");
                sterge(dir); dir.mkdirs();
                StringBuilder lista = new StringBuilder(); boolean arhiva = false;
                java.util.HashSet<String> folosite = new java.util.HashSet<String>();
                for (android.net.Uri u : uri) {
                    String nume = curat(nume(cr, u));
                    String n = nume; int k = 2;
                    while (folosite.contains(n.toLowerCase())) { n = k + "-" + nume; k++; }
                    folosite.add(n.toLowerCase());
                    copiaza(cr.openInputStream(u), new java.io.FileOutputStream(new java.io.File(dir, n)));
                    lista.append("intrare/").append(n).append('\n');
                    if (n.toLowerCase().endsWith(".z7a") || n.toLowerCase().endsWith(".z7c")) arhiva = true;
                }
                scrie(new java.io.File(getFilesDir(), "alese.txt"), lista.toString());
                boolean z7a = uri.size() == 1 && (arhiva || a.equals("android.intent.action.VIEW"));
                java.io.File t = new java.io.File(getFilesDir(), "deschide.tmp");
                scrie(t, z7a ? "Z7A\n" : "PACK\n");
                t.renameTo(new java.io.File(getFilesDir(), "deschide.txt"));
            } catch (Throwable e) { raspuns("EROARE " + e); }
        } }, "primite").start();
    }

    String[] cerere() {
        try {
            java.io.File f = new java.io.File(getFilesDir(), "cerere.txt");
            byte[] b = new byte[(int) f.length()];
            java.io.FileInputStream in = new java.io.FileInputStream(f);
            int k = 0; while (k < b.length) { int r = in.read(b, k, b.length - k); if (r < 0) break; k += r; }
            in.close();
            return new String(b, 0, k, "ISO-8859-1").split("\n");
        } catch (Throwable t) { return new String[] {""}; }
    }

    static String nume(android.content.ContentResolver cr, android.net.Uri u) {
        String n = null;
        try {
            android.database.Cursor c = cr.query(u, null, null, null, null);
            if (c != null) {
                if (c.moveToFirst()) { int i = c.getColumnIndex("_display_name"); if (i >= 0) n = c.getString(i); }
                c.close();
            }
        } catch (Throwable t) { }
        if (n == null) { n = u.getLastPathSegment(); if (n == null) n = "fisier"; int s = n.lastIndexOf('/'); if (s >= 0) n = n.substring(s + 1); }
        return n;
    }

    static String curat(String n) {   // doar litere, cifre, . - _ (ca sa-l poata scrie Grafica si Fisier)
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < n.length() && b.length() < 60; i++) {
            char c = n.charAt(i);
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_') b.append(c);
            else b.append('-');
        }
        if (b.length() == 0) b.append("fisier");
        return b.toString();
    }

    static void copiaza(java.io.InputStream in, java.io.OutputStream out) throws java.io.IOException {
        try {
            byte[] b = new byte[65536]; int k;
            while ((k = in.read(b)) > 0) out.write(b, 0, k);
        } finally { in.close(); out.close(); }
    }

    static void sterge(java.io.File d) {
        java.io.File[] l = d.listFiles();
        if (l != null) for (java.io.File f : l) f.delete();
    }

    static void scrie(java.io.File f, String s) throws java.io.IOException {
        java.io.FileOutputStream o = new java.io.FileOutputStream(f);
        o.write(s.getBytes("ISO-8859-1")); o.close();
    }

    void raspuns(String s) {   // intai .tmp, apoi redenumit: programul nu prinde niciodata un raspuns pe jumatate
        try {
            java.io.File t = new java.io.File(getFilesDir(), "raspuns.tmp");
            scrie(t, s + "\n");
            t.renameTo(new java.io.File(getFilesDir(), "raspuns.txt"));
        } catch (Throwable e) { }
    }

    boolean atinge(android.view.MotionEvent e) {
        int x = (int) (e.getX() / SCARA), y = (int) (e.getY() / SCARA);
        switch (e.getActionMasked()) {
            case 0: pune(1, x); pune(2, y); pune(0, 1); atingeri++; pune(3, atingeri); break;
            case 1: case 3: pune(0, 0); break;
            case 2: pune(1, x); pune(2, y); break;
        }
        return true;
    }

    public boolean onKeyDown(int k, android.view.KeyEvent e) {
        if (k == 4) return super.onKeyDown(k, e);
        int c = e.getUnicodeChar(); if (c <= 0) c = k + 1000;
        pune(15, c); taste++; pune(16, taste);
        return true;
    }

    protected void onPause() { pune(17, 1); super.onPause(); }
    protected void onResume() { super.onResume(); pune(17, 0); }

    protected void onDestroy() {
        gata = true;
        try { if (mf != null) mf.putInt(20, 1); } catch (Throwable t) { }
        final Process p = joc;
        if (p != null) new Thread(new Runnable() { public void run() {
            try { Thread.sleep(500); } catch (Throwable t) { }
            p.destroy();
        } }).start();
        super.onDestroy();
    }
}
