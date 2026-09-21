package com.trippals.shared.platform

import android.content.Context
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential

/** Native Credential Manager implementation of the shared WebAuthn boundary. */
class AndroidCredentialManagerPasskeyAuthenticator(
    private val context: Context,
    private val credentialManager: CredentialManager = CredentialManager.create(context),
) : PasskeyAuthenticator {
    override suspend fun createCredential(creationOptionsJson: String): String {
        val response = credentialManager.createCredential(
            context = context,
            request = CreatePublicKeyCredentialRequest(creationOptionsJson),
        )
        return (response as? CreatePublicKeyCredentialResponse)?.registrationResponseJson
            ?: error("The selected credential was not a passkey")
    }

    override suspend fun getAssertion(requestOptionsJson: String): String {
        val result = credentialManager.getCredential(
            context = context,
            request = GetCredentialRequest(
                listOf(GetPublicKeyCredentialOption(requestOptionsJson)),
            ),
        )
        return (result.credential as? PublicKeyCredential)?.authenticationResponseJson
            ?: error("The selected credential was not a passkey")
    }
}
