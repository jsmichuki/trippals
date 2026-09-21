package com.trippals.shared.platform

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.trippals.shared.auth.SecureSessionStore
import com.trippals.shared.auth.SessionTokens
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Sensitive session material. Never log an instance of this type. */
@Serializable
private data class StoredSession(
    val accessToken: String,
    val refreshToken: String,
)

/**
 * Stores one encrypted session blob. The AES-GCM key is non-exportable and
 * created in Android Keystore; SharedPreferences contains ciphertext only.
 */
class AndroidKeystoreSecureSessionStore(context: Context) : SecureSessionStore {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    override suspend fun accessToken(): String? = readSession()?.accessToken

    override suspend fun refreshToken(): String? = readSession()?.refreshToken

    override suspend fun replace(tokens: SessionTokens) {
        writeSession(StoredSession(tokens.accessToken, tokens.refreshToken))
    }

    override suspend fun clear() {
        preferences.edit().remove(SESSION_KEY).commit()
    }

    private fun readSession(): StoredSession? {
        val stored = preferences.getString(SESSION_KEY, null) ?: return null
        return runCatching {
            val bytes = Base64.decode(stored, Base64.NO_WRAP)
            require(bytes.size > GCM_IV_LENGTH) { "Malformed encrypted session" }
            val iv = bytes.copyOfRange(0, GCM_IV_LENGTH)
            val encrypted = bytes.copyOfRange(GCM_IV_LENGTH, bytes.size)
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv))
            }
            Json.decodeFromString<StoredSession>(cipher.doFinal(encrypted).decodeToString())
        }.getOrElse {
            // A missing/invalid Keystore key or tampered ciphertext must end the local session.
            preferences.edit().remove(SESSION_KEY).commit()
            null
        }
    }

    private fun writeSession(session: StoredSession) {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        }
        val encrypted = cipher.doFinal(Json.encodeToString(session).encodeToByteArray())
        val value = Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP)
        check(preferences.edit().putString(SESSION_KEY, value).commit()) {
            "Unable to persist encrypted session"
        }
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE).apply {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
        }.generateKey()
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "trippals.session.v1"
        const val PREFERENCES_NAME = "trippals.secure_session"
        const val SESSION_KEY = "encrypted_session"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val GCM_IV_LENGTH = 12
        const val GCM_TAG_LENGTH_BITS = 128
    }
}
