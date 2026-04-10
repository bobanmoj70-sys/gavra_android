package com.gavra013.gavra_android;

import android.app.Application;

import androidx.annotation.NonNull;

import com.google.android.recaptcha.Recaptcha;
import com.google.android.recaptcha.RecaptchaAction;
import com.google.android.recaptcha.RecaptchaTasksClient;

public final class RecaptchaBridge {
    public interface InitCallback {
        void onSuccess();

        void onError(String code, String message);
    }

    public interface ExecuteCallback {
        void onSuccess(String token);

        void onError(String code, String message);
    }

    private RecaptchaTasksClient recaptchaTasksClient;
    private String recaptchaSiteKey;

    public void initialize(@NonNull Application application, @NonNull String siteKey, @NonNull InitCallback callback) {
        if (recaptchaTasksClient != null && siteKey.equals(recaptchaSiteKey)) {
            callback.onSuccess();
            return;
        }

        Recaptcha.fetchTaskClient(application, siteKey)
                .addOnSuccessListener(client -> {
                    recaptchaTasksClient = client;
                    recaptchaSiteKey = siteKey;
                    callback.onSuccess();
                })
                .addOnFailureListener(error -> callback.onError(
                        "RECAPTCHA_INIT_FAILED",
                        error != null && error.getMessage() != null ? error.getMessage() : "Init failed"
                ));
    }

    public void execute(@NonNull String action, long timeoutMs, @NonNull ExecuteCallback callback) {
        if (recaptchaTasksClient == null) {
            callback.onError("RECAPTCHA_NOT_INITIALIZED", "reCAPTCHA client nije inicijalizovan.");
            return;
        }

        final RecaptchaAction recaptchaAction;
        switch (action.toUpperCase()) {
            case "LOGIN":
                recaptchaAction = RecaptchaAction.LOGIN;
                break;
            case "SIGNUP":
                recaptchaAction = RecaptchaAction.SIGNUP;
                break;
            default:
                recaptchaAction = RecaptchaAction.custom(action);
                break;
        }

        final long safeTimeoutMs = Math.max(timeoutMs, 5000L);
        recaptchaTasksClient.executeTask(recaptchaAction, safeTimeoutMs)
                .addOnSuccessListener(callback::onSuccess)
                .addOnFailureListener(error -> callback.onError(
                        "RECAPTCHA_EXECUTE_FAILED",
                        error != null && error.getMessage() != null ? error.getMessage() : "Execute failed"
                ));
    }
}
