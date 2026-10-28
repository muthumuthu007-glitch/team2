package in.carloo.team2;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.DownloadListener;
import android.webkit.GeolocationPermissions;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Team2 is a thin shell around https://team2.carloo.in.
 *
 * There is no copy of the app inside this APK. The page is fetched from our own
 * server on every launch, and the server sends it with Cache-Control: no-store,
 * so whatever was last pushed to GitHub is what opens. Updating the app means
 * pushing code — nobody reinstalls anything.
 *
 * Mono does this differently: it downloads an HTML file from storage and renders
 * it at a borrowed origin, which welds the APK to that origin forever. We own
 * team2.carloo.in, so we just load it, and login, local storage and the camera
 * all behave exactly as they do in a browser.
 *
 * Before the login page appears the shell checks the server and shows which
 * build it is about to open, so an update is visibly finished before anyone
 * types a password.
 */
public class MainActivity extends Activity {

    private static final String APP_URL = "https://team2.carloo.in/";
    private static final String PREFS = "team2";
    private static final String KEY_ASKED = "asked_permissions";
    private static final int REQ_FILE = 1001;
    private static final int REQ_PERMS = 1002;

    private static final int INK = Color.parseColor("#231f20");
    private static final int MUTED = Color.parseColor("#6b7280");
    private static final int BRAND = Color.parseColor("#2f4bd0");
    private static final int PAPER = Color.parseColor("#ffffff");

    private WebView web;
    private LinearLayout splash;
    private TextView splashLine;
    private Button splashButton;
    private ValueCallback<Uri[]> filePicker;
    private boolean pageShown = false;

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);

        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(PAPER);

        web = buildWebView();
        splash = buildSplash();

        root.addView(web);
        root.addView(splash);
        setContentView(root);

        if (getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_ASKED, false)) {
            checkThenLoad();
        } else {
            askForPermissions();
        }
    }

    // ---------------------------------------------------------------- web view

    private WebView buildWebView() {
        WebView w = new WebView(this);
        w.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        w.setBackgroundColor(PAPER);

        WebSettings s = w.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);      // the app keeps GPS here until it can send it
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setGeolocationEnabled(true);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        // Lets the page tell it is running inside the app, so it can hide the
        // Admin tab — this shell is for staff, not for administration.
        s.setUserAgentString(s.getUserAgentString() + " Team2App/" + versionName());
        CookieManager.getInstance().setAcceptCookie(true);

        w.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView v, String url) {
                pageShown = true;
                hideSplash();
            }

            @Override
            public void onReceivedError(WebView v, int code, String desc, String url) {
                if (!pageShown) failed(desc);
            }
        });

        w.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb,
                                             FileChooserParams params) {
                if (filePicker != null) filePicker.onReceiveValue(null);
                filePicker = cb;
                try {
                    startActivityForResult(widen(params.createIntent()), REQ_FILE);
                } catch (Exception e) {
                    filePicker = null;
                    return false;
                }
                return true;
            }

            /** Camera and microphone asked for by the page itself. */
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                ui.post(new Runnable() {
                    @Override public void run() { request.grant(request.getResources()); }
                });
            }

            /** The page asking for GPS. Android has already been asked separately. */
            @Override
            public void onGeolocationPermissionsShowPrompt(String origin,
                                                           GeolocationPermissions.Callback cb) {
                boolean granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                        || checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                           == PackageManager.PERMISSION_GRANTED;
                cb.invoke(origin, granted, false);
            }
        });

        // A link to a document would otherwise do nothing in a WebView. Hand it
        // to whatever app on the phone can open that kind of file.
        w.setDownloadListener(new DownloadListener() {
            @Override
            public void onDownloadStart(String url, String ua, String disposition,
                                        String mime, long size) {
                try {
                    Intent open = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                    open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(open);
                } catch (Exception e) {
                    Toast.makeText(MainActivity.this,
                            "No app on this phone can open that file.",
                            Toast.LENGTH_LONG).show();
                }
            }
        });
        return w;
    }

    /**
     * Staff attach whatever the job produced - a gallery photo, a scanned PDF, a
     * spreadsheet - so the picker is opened on every file type, even when the
     * page asked only for images. The camera option the page requested is left
     * alone, so taking a selfie still works.
     */
    private Intent widen(Intent intent) {
        if (intent == null) return null;
        Intent content = intent;
        if (Intent.ACTION_CHOOSER.equals(intent.getAction())) {
            // createIntent() wraps camera and file-picking in a chooser.
            // Widen the file-picking half and leave the camera half untouched.
            Object inner = intent.getParcelableExtra(Intent.EXTRA_INTENT);
            if (inner instanceof Intent) content = (Intent) inner;
        }
        content.setType("*/*");
        content.removeExtra(Intent.EXTRA_MIME_TYPES);
        content.addCategory(Intent.CATEGORY_OPENABLE);
        return intent;
    }

    // ------------------------------------------------------------ splash panel

    private LinearLayout buildSplash() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setBackgroundColor(PAPER);
        box.setPadding(dp(32), dp(32), dp(32), dp(32));
        box.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        // Swallow taps so they cannot reach the page loading underneath.
        box.setClickable(true);

        ImageView logo = new ImageView(this);
        logo.setImageResource(R.drawable.carloo_logo);
        logo.setAdjustViewBounds(true);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(210),
                ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.bottomMargin = dp(28);
        logo.setLayoutParams(lp);
        box.addView(logo);

        splashLine = new TextView(this);
        splashLine.setTextColor(MUTED);
        splashLine.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        splashLine.setGravity(Gravity.CENTER);
        splashLine.setLineSpacing(dp(4), 1f);
        splashLine.setText("Starting…");
        box.addView(splashLine);

        splashButton = new Button(this);
        splashButton.setAllCaps(false);
        splashButton.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        splashButton.setTypeface(Typeface.DEFAULT_BOLD);
        splashButton.setTextColor(Color.WHITE);
        splashButton.setBackgroundColor(BRAND);
        splashButton.setVisibility(View.GONE);
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(dp(220), dp(48));
        bp.topMargin = dp(24);
        splashButton.setLayoutParams(bp);
        box.addView(splashButton);

        return box;
    }

    private void say(String text) {
        splashLine.setTextColor(MUTED);
        splashLine.setText(text);
        splashButton.setVisibility(View.GONE);
    }

    private void offer(String text, String label, View.OnClickListener action) {
        splashLine.setText(text);
        splashButton.setText(label);
        splashButton.setVisibility(View.VISIBLE);
        splashButton.setOnClickListener(action);
    }

    private void hideSplash() {
        splash.setVisibility(View.GONE);
    }

    private void failed(String why) {
        splash.setVisibility(View.VISIBLE);
        splashLine.setTextColor(INK);
        offer("Could not reach team2.carloo.in.\n"
                + (why == null ? "" : why) + "\n\nCheck your internet and try again.",
              "Try again", new View.OnClickListener() {
                  @Override public void onClick(View v) { checkThenLoad(); }
              });
    }

    // ------------------------------------------------------------- permissions

    /** First launch only: say what is needed and why, then ask Android for it. */
    private void askForPermissions() {
        offer("Team2 needs a few things on this phone:\n\n"
                + "Camera — your punch-in selfie and visit photos\n"
                + "Location — where you punched in and which places you visited\n"
                + "Photos and videos — to attach from your gallery\n\n"
                + "Documents are picked one at a time and need no permission.\n"
                + "You can change these later in Settings.",
              "Continue", new View.OnClickListener() {
                  @Override public void onClick(View v) { requestThem(); }
              });
    }

    private void requestThem() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(KEY_ASKED, true).apply();

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) { checkThenLoad(); return; }

        List<String> want = new ArrayList<String>();
        want.add(Manifest.permission.CAMERA);
        want.add(Manifest.permission.ACCESS_FINE_LOCATION);
        want.add(Manifest.permission.ACCESS_COARSE_LOCATION);
        if (Build.VERSION.SDK_INT >= 33) {
            want.add(Manifest.permission.READ_MEDIA_IMAGES);
            want.add(Manifest.permission.READ_MEDIA_VIDEO);
            // Android 14 lets someone grant only the items they pick. Asking for
            // it alongside the two above is what puts "Select photos" on the
            // prompt; without it they only get all-or-nothing.
            if (Build.VERSION.SDK_INT >= 34) {
                want.add(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED);
            }
        } else {
            want.add(Manifest.permission.READ_EXTERNAL_STORAGE);
        }

        List<String> missing = new ArrayList<String>();
        for (String p : want) {
            if (checkSelfPermission(p) != PackageManager.PERMISSION_GRANTED) missing.add(p);
        }
        if (missing.isEmpty()) { checkThenLoad(); return; }

        say("Waiting for your answer…");
        requestPermissions(missing.toArray(new String[0]), REQ_PERMS);
    }

    @Override
    public void onRequestPermissionsResult(int req, String[] perms, int[] results) {
        if (req == REQ_PERMS) {
            // Refusing is allowed. The screens that need a camera or GPS will say
            // so when they are opened; the rest of the app works regardless.
            checkThenLoad();
            return;
        }
        super.onRequestPermissionsResult(req, perms, results);
    }

    // -------------------------------------------------- update check, then load

    /**
     * Reads just the head of the page to learn which build the server is
     * serving, shows it, then opens the app. This is the "update before login"
     * step: by the time the login page appears, the newest build is what loaded.
     */
    private void checkThenLoad() {
        splash.setVisibility(View.VISIBLE);
        say("Checking for updates…");

        io.execute(new Runnable() {
            @Override public void run() {
                String version = null;
                String error = null;
                HttpURLConnection c = null;
                try {
                    c = (HttpURLConnection) new URL(APP_URL).openConnection();
                    c.setConnectTimeout(15000);
                    c.setReadTimeout(20000);
                    c.setRequestProperty("Cache-Control", "no-cache");
                    int code = c.getResponseCode();
                    if (code == 200) {
                        // APP_CFG sits at the very top of the page, so the first
                        // few kB are enough — no need to pull the whole file twice.
                        char[] buf = new char[8192];
                        InputStreamReader r =
                                new InputStreamReader(c.getInputStream(), "UTF-8");
                        int n = r.read(buf);
                        r.close();
                        if (n > 0) {
                            Matcher m = Pattern.compile("version:\\s*\"([^\"]+)\"")
                                               .matcher(new String(buf, 0, n));
                            if (m.find()) version = m.group(1);
                        }
                    } else {
                        error = "Server returned " + code;
                    }
                } catch (Exception e) {
                    error = e.getMessage();
                } finally {
                    if (c != null) c.disconnect();
                }

                final String v = version;
                final String err = error;
                ui.post(new Runnable() {
                    @Override public void run() {
                        if (err != null) { failed(err); return; }
                        say(v == null ? "Loading…" : "Loading Team2 " + v + "…");
                        web.loadUrl(APP_URL);
                    }
                });
            }
        });
    }

    // ------------------------------------------------------------------ plumbing

    private String versionName() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "1.0.0";
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onActivityResult(int req, int result, Intent data) {
        if (req == REQ_FILE) {
            if (filePicker == null) return;
            Uri[] out = null;
            if (result == RESULT_OK && data != null) {
                if (data.getDataString() != null) {
                    out = new Uri[]{ Uri.parse(data.getDataString()) };
                } else if (data.getClipData() != null) {
                    int n = data.getClipData().getItemCount();
                    out = new Uri[n];
                    for (int i = 0; i < n; i++) out[i] = data.getClipData().getItemAt(i).getUri();
                }
            }
            filePicker.onReceiveValue(out);
            filePicker = null;
            return;
        }
        super.onActivityResult(req, result, data);
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) web.goBack();
        else super.onBackPressed();
    }
}
