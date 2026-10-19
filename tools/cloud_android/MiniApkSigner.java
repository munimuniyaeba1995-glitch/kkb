import com.android.apksig.ApkSigner;
import com.android.apksig.ApkVerifier;
import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import java.util.*;

/** Minimal apksigner-compatible CLI: "sign --ks K --ks-pass pass:P --ks-key-alias A apk" and "verify apk". */
public class MiniApkSigner {
    public static void main(String[] a) throws Exception {
        if (a.length == 0 || a[0].equals("--version") || a[0].equals("version")) { System.out.println("0.9"); return; }
        String cmd = a[0];
        String ks = null, pass = null, alias = null, apk = null;
        for (int i = 1; i < a.length; i++) {
            switch (a[i]) {
                case "--ks": ks = a[++i]; break;
                case "--ks-pass": pass = a[++i].replaceFirst("^pass:", ""); break;
                case "--ks-key-alias": alias = a[++i]; break;
                case "--verbose": case "-v": break;
                default: apk = a[i];
            }
        }
        if (cmd.equals("verify")) {
            ApkVerifier.Result r = new ApkVerifier.Builder(new File(apk)).setMinCheckedPlatformVersion(24).build().verify();
            System.out.println("Verifies: " + r.isVerified() + " v1=" + r.isVerifiedUsingV1Scheme() + " v2=" + r.isVerifiedUsingV2Scheme());
            for (Object e : r.getErrors()) System.out.println("ERROR: " + e);
            System.exit(r.isVerified() ? 0 : 1);
        }
        KeyStore store;
        try { store = KeyStore.getInstance("JKS"); store.load(new FileInputStream(ks), pass.toCharArray()); }
        catch (Exception e) { store = KeyStore.getInstance("PKCS12"); store.load(new FileInputStream(ks), pass.toCharArray()); }
        PrivateKey key = (PrivateKey) store.getKey(alias, pass.toCharArray());
        List<X509Certificate> certs = new ArrayList<>();
        for (java.security.cert.Certificate c : store.getCertificateChain(alias)) certs.add((X509Certificate) c);
        ApkSigner.SignerConfig sc = new ApkSigner.SignerConfig.Builder("CERT", key, certs).build();
        File in = new File(apk), out = new File(apk + ".signed");
        new ApkSigner.Builder(Collections.singletonList(sc)).setInputApk(in).setOutputApk(out)
            .setV1SigningEnabled(false).setV2SigningEnabled(true).build().sign();
        Files.move(out.toPath(), in.toPath(), StandardCopyOption.REPLACE_EXISTING);
        System.out.println("Signed");
    }
}
