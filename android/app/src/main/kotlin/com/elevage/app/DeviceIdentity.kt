package com.elevage.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.UUID

/** One installation identity. The private key has no export operation. */
class DeviceIdentity(context: Context) {
    private val preferences = context.getSharedPreferences("installation_identity", Context.MODE_PRIVATE)
    private val alias = "elevage.installation.signing.v1"
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    @Synchronized
    fun identity(): Map<String, Any> {
        var installation = preferences.getString("uuid", null)
        val hasKey = store.containsAlias(alias)
        // Do not silently replace a provisioned identity if the key is lost.
        if (installation != null && !hasKey) error("DEVICE_KEY_LOST")
        if (installation == null && hasKey) error("DEVICE_IDENTITY_INCONSISTENT")
        if (installation == null) {
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
            generator.initialize(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256).build())
            generator.generateKeyPair()
            installation = UUID.randomUUID().toString()
            check(preferences.edit().putString("uuid", installation).commit())
        }
        val key = store.getKey(alias, null)
        check(key.encoded == null) { "DEVICE_PRIVATE_KEY_EXPORTABLE" }
        val public = Base64.encodeToString(store.getCertificate(alias).publicKey.encoded, Base64.NO_WRAP)
        val pem = "-----BEGIN PUBLIC KEY-----\n" + public.chunked(64).joinToString("\n") +
            "\n-----END PUBLIC KEY-----\n"
        return mapOf("installation_uuid" to installation, "public_key" to pem,
            "algorithm" to "P256-SHA256-DER", "private_key_exportable" to false)
    }

    @Synchronized
    fun sign(message: ByteArray): String {
        require(message.size in 1..8192) { "DEVICE_MESSAGE_INVALID" }
        identity()
        val signer = Signature.getInstance("SHA256withECDSA")
        signer.initSign(store.getKey(alias, null) as java.security.PrivateKey)
        signer.update(message)
        return Base64.encodeToString(signer.sign(), Base64.NO_WRAP)
    }
}
