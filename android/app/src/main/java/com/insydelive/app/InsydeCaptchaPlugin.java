package com.insydelive.app;

import android.annotation.SuppressLint;
import android.app.Dialog;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONObject;

/**
 * InsydeLive security check panel (v2.4.5, approved 18 Oct 2026). Same as the iPhone app:
 * opens https://app.insydelive.com/captcha.html in a small panel, which runs Cloudflare's check and
 * posts back {"token": "..."} or {"error": "..."} through window.InsydeCaptchaBridge.post(json).
 */
@CapacitorPlugin(name = "InsydeCaptcha")
public class InsydeCaptchaPlugin extends Plugin {
    private static final String HOST = "app.insydelive.com";
    private Dialog dialog;
    private PluginCall pending;
    private final Handler main = new Handler(Looper.getMainLooper());
    private Runnable timeout;

    @SuppressLint("SetJavaScriptEnabled")
    @PluginMethod
    public void getToken(PluginCall call) {
        String urlString = call.getString("url", "https://app.insydelive.com/captcha.html");
        Uri uri = Uri.parse(urlString);
        if (!"https".equals(uri.getScheme()) || !HOST.equals(uri.getHost())) {
            call.reject("bad_url");
            return;
        }
        main.post(() -> {
            if (pending != null) { call.reject("busy"); return; }
            pending = call;

            WebView web = new WebView(getActivity());
            WebSettings ws = web.getSettings();
            ws.setJavaScriptEnabled(true);
            ws.setDomStorageEnabled(true);
            ws.setCacheMode(WebSettings.LOAD_NO_CACHE);
            web.setBackgroundColor(Color.parseColor("#140B22"));
            web.addJavascriptInterface(new Bridge(), "InsydeCaptchaBridge");
            web.setWebViewClient(new WebViewClient() {
                // Keep the panel on our own page only (Cloudflare's challenge runs inside frames, which are allowed).
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    return request.isForMainFrame() && !HOST.equals(request.getUrl().getHost());
                }
            });

            dialog = new Dialog(getActivity());
            dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
            dialog.setContentView(web);
            dialog.setCanceledOnTouchOutside(true);
            dialog.setOnCancelListener(d -> finish(null, "cancelled", false));
            Window w = dialog.getWindow();
            if (w != null) {
                w.setBackgroundDrawable(new ColorDrawable(Color.parseColor("#140B22")));
                int height = (int) (getActivity().getResources().getDisplayMetrics().heightPixels * 0.55);
                w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, height);
                w.setGravity(Gravity.BOTTOM);
                w.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
                w.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            }
            dialog.show();
            web.loadUrl(urlString);

            // Never leave the person stuck: give up after 90 seconds.
            timeout = () -> finish(null, "timeout", true);
            main.postDelayed(timeout, 90000);
        });
    }

    private void finish(String token, String error, boolean close) {
        main.post(() -> {
            PluginCall call = pending;
            if (call == null) return;
            pending = null;
            if (timeout != null) main.removeCallbacks(timeout);
            if (close && dialog != null && dialog.isShowing()) {
                try { dialog.dismiss(); } catch (Exception ignored) {}
            }
            dialog = null;
            if (token != null) {
                JSObject ret = new JSObject();
                ret.put("token", token);
                call.resolve(ret);
            } else {
                call.reject(error == null ? "failed" : error);
            }
        });
    }

    private class Bridge {
        @JavascriptInterface
        public void post(String json) {
            try {
                JSONObject o = new JSONObject(json);
                String token = o.optString("token", "");
                if (!token.isEmpty()) {
                    finish(token, null, true);
                } else if (o.has("error")) {
                    finish(null, "check_failed:" + o.optString("error"), true);
                }
            } catch (Exception e) {
                finish(null, "bad_message", true);
            }
        }
    }
}
