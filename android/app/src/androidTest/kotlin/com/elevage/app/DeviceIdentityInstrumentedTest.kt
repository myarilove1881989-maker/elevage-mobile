package com.elevage.app

import android.content.pm.ApplicationInfo
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class DeviceIdentityInstrumentedTest {
    @Test
    fun privateKeyStaysInKeystoreAndSignsBackendContract() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val identity = DeviceIdentity(context)
        val public = identity.identity()
        assertEquals(false, public["private_key_exportable"])
        assertEquals("P256-SHA256-DER", public["algorithm"])
        assertEquals(public, DeviceIdentity(context).identity())
        assertEquals(0, context.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
        val challenge = UUID.randomUUID().toString()
        val digest = MessageDigest.getInstance("SHA-256").digest("{}".toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        val message = "ELEVAGE-DEVICE-V1\n$challenge\n7\n1\nACTIVATE\nPOST\n/api/devices/7/activate/\n$digest"
        val signature = identity.sign(message.toByteArray(Charsets.UTF_8))
        val pem = public["public_key"] as String
        val der = Base64.decode(pem.replace("-----BEGIN PUBLIC KEY-----", "")
            .replace("-----END PUBLIC KEY-----", "").replace(Regex("\\s"), ""), Base64.DEFAULT)
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(der))
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(key)
        verifier.update(message.toByteArray(Charsets.UTF_8))
        assertTrue(verifier.verify(Base64.decode(signature, Base64.DEFAULT)))
        verifier.initVerify(key)
        verifier.update((message + "tampered").toByteArray(Charsets.UTF_8))
        assertFalse(verifier.verify(Base64.decode(signature, Base64.DEFAULT)))
        // Public proof only, for a synthetic PostgreSQL activation probe. No secret.
        val vector = JSONObject().put("public_key", pem)
            .put("installation_uuid", public["installation_uuid"])
            .put("challenge_id", challenge).put("signature", signature)
            .put("message", message).put("private_key_exportable", false)
        context.openFileOutput("native-proof-vector.json", 0).use { it.write(vector.toString().toByteArray()) }
    }
}
