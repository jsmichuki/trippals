package com.trippals.shared.platform

import androidx.biometric.BiometricPrompt
import androidx.biometric.BiometricManager
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.Executor
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/** Uses system biometric/device-credential UX; no biometric result is retained. */
class AndroidBiometricAppLock(
    private val activity: FragmentActivity,
    private val executor: Executor,
    private val subtitle: String? = null,
) : LocalAppLock {
    override suspend fun unlock(
        localizedReason: String,
    ): AppLockResult = suspendCancellableCoroutine { continuation ->
        val prompt = BiometricPrompt(
            activity,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    if (continuation.isActive) continuation.resume(AppLockResult.UNLOCKED)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (continuation.isActive) continuation.resume(AppLockResult.CANCELLED)
                }

                override fun onAuthenticationFailed() = Unit
            },
        )
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(localizedReason)
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
            .build()
        continuation.invokeOnCancellation { prompt.cancelAuthentication() }
        prompt.authenticate(promptInfo)
    }
}
