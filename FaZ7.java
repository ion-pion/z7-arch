// Face Z7Arch6.apk cu uneltele lui Byz7 4 (Axml, Iconita, Semnatura, Pachet), plus filtrele pentru .z7c si Share.
import java.io.*; import java.util.*;
public class FaZ7 {
  public static void main(String[] a) throws Exception {
    String pkg = "ro.jahbalon.z7arch6", eticheta = "Z7 Arch 6";
    // atributele noi in tabelul lui Axml (pe locuri nefolosite de manifestul nostru)
    String[] N = {"drawable", "windowSoftInputMode", "largeHeap", "process", "value", "authorities"};
    String[] Nou = {"mimeType", "scheme", "host", "pathPattern", "priority", "pathSuffix"};
    int[] Id = {0x01010026, 0x01010027, 0x01010028, 0x0101002c, 0x0101001c, 0x010105e7};
    for (int k = 0; k < N.length; k++) for (int i = 0; i < Axml.ATR.length; i++)
      if (Axml.ATR[i].equals(N[k])) { Axml.ATR[i] = Nou[k]; Axml.ATR_ID[i] = Id[k]; }
    int ver = (int) (((System.currentTimeMillis() / 1000) - 1767225600L) / 60);
    Map<String, byte[]> m = new LinkedHashMap<String, byte[]>();
    Map<String, byte[]> res = new LinkedHashMap<String, byte[]>();
    byte[] ic = a.length > 3 ? Iconita.propriu(new File(a[3])) : null;
    int icon = Iconita.pune(res, pkg, eticheta, ic);
    Axml x = new Axml();
    x.incepeNs();
    x.incepe("manifest", Axml.a("versionCode", 16, ver), Axml.a("versionName", "6." + ver), Axml.simplu("package", pkg));
    x.incepe("uses-sdk", Axml.a("minSdkVersion", 16, 21), Axml.a("targetSdkVersion", 16, 29)); x.termina("uses-sdk");
    x.incepe("application", Axml.a("label", eticheta), Axml.a("theme", 1, 16973831), Axml.a("icon", 1, icon), Axml.a("extractNativeLibs", 18, -1));
    x.incepe("activity", Axml.a("name", "ro.jahbalon.eulaoberon.EcranNativ"), Axml.a("exported", 18, -1), Axml.a("label", eticheta),
      Axml.a("screenOrientation", 16, 1), Axml.a("configChanges", 16, 1184), Axml.a("launchMode", 16, 2));
    x.incepe("intent-filter");
    x.incepe("action", Axml.a("name", "android.intent.action.MAIN")); x.termina("action");
    x.incepe("category", Axml.a("name", "android.intent.category.LAUNCHER")); x.termina("category");
    x.termina("intent-filter");
    // Deschide cu: fisiere .z7c (Android le da ca application/octet-stream sau dupa nume)
    x.incepe("intent-filter");
    x.incepe("action", Axml.a("name", "android.intent.action.VIEW")); x.termina("action");
    x.incepe("category", Axml.a("name", "android.intent.category.DEFAULT")); x.termina("category");
    x.incepe("data", Axml.a("mimeType", "application/octet-stream")); x.termina("data");
    x.incepe("data", Axml.a("mimeType", "application/x-z7c")); x.termina("data");
    x.termina("intent-filter");
    x.incepe("intent-filter");
    x.incepe("action", Axml.a("name", "android.intent.action.VIEW")); x.termina("action");
    x.incepe("category", Axml.a("name", "android.intent.category.DEFAULT")); x.termina("category");
    x.incepe("data", Axml.a("scheme", "content")); x.termina("data");
    x.incepe("data", Axml.a("scheme", "file")); x.termina("data");
    x.incepe("data", Axml.a("host", "*")); x.termina("data");
    x.incepe("data", Axml.a("mimeType", "*/*")); x.termina("data");
    x.incepe("data", Axml.a("pathPattern", ".*\\.z7c")); x.termina("data");
    x.termina("intent-filter");
    // Trimite (Share): unul sau mai multe fisiere de orice fel
    for (String act : new String[] {"android.intent.action.SEND", "android.intent.action.SEND_MULTIPLE"}) {
      x.incepe("intent-filter");
      x.incepe("action", Axml.a("name", act)); x.termina("action");
      x.incepe("category", Axml.a("name", "android.intent.category.DEFAULT")); x.termina("category");
      x.incepe("data", Axml.a("mimeType", "*/*")); x.termina("data");
      x.termina("intent-filter");
    }
    x.termina("activity"); x.termina("application"); x.termina("manifest"); x.terminaNs();
    m.put("AndroidManifest.xml", x.gata());
    m.put("classes.dex", Pachet.citesteTot(new File(a[0])));
    m.putAll(res);
    m.put("lib/arm64-v8a/libjoc.so", Pachet.citesteTot(new File(a[1])));
    Semnatura s = Semnatura.cheia(new File(a[2]), "Z7 Arch");
    File apk = new File("Z7Arch6.apk");
    Pachet.scrieApk(apk, m, s);
    System.out.println("gata " + apk.length() + " versiunea " + ver + " " + res.keySet());
  }
}
