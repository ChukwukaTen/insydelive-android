package com.insydelive.app;

import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.webkit.WebView;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // v2.4.5: InsydeLive's own security check panel (see InsydeCaptchaPlugin). Must be registered before super.onCreate.
        registerPlugin(InsydeCaptchaPlugin.class);
        super.onCreate(savedInstanceState);

        // Approved 14 Oct 2026 (option A): switch off the phone's autofill pop-up inside the app.
        // On some phones (seen on a Motorola) the pop-up offering a saved email or home address
        // closed the keyboard after one letter. The website keeps autofill; only the app is affected.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WebView webView = getBridge() != null ? getBridge().getWebView() : null;
            if (webView != null) {
                webView.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);
            }
        }
    }
}
