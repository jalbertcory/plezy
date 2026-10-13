package com.plezy.credentials

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.UnrecoverableKeyException
import java.util.UUID
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** One Keystore alias per item. No namespace-wide reset, logging, or fallback. */
class AndroidCredentialStorePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    companion object {
        private const val PREFIX = "com.plezy.credentials.android.v1."
        private const val FILE = "plezy_android_credentials_v1"
        // All engines in this app process serialize storage operations.
        private val executor = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
        private val idPattern = Regex("^[a-f0-9]{64}$")
    }
    private lateinit var prefs: SharedPreferences
    private lateinit var data: SharedPreferences
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        data = binding.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        // Nonsecret reset journals and reauth markers survive device backup.
        prefs = binding.applicationContext.getSharedPreferences("plezy_android_credential_state_v1", Context.MODE_PRIVATE)
        channel = MethodChannel(binding.binaryMessenger, "com.plezy/android_credentials")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "listOwnedIds") {
            executor.execute {
                try {
                    val ids = (prefs.all.keys + data.all.keys).map { it.substringBefore('.') }
                        .filter { idPattern.matches(it) }.distinct()
                    main.post { result.success(ids) }
                } catch (_: Exception) {
                    main.post { result.error("unavailable", "Credential storage unavailable", null) }
                }
            }
            return
        }
        val id = call.argument<String>("id")
        if (id == null || !idPattern.matches(id)) {
            result.error("unavailable", "Credential storage unavailable", null)
            return
        }
        executor.execute {
            try {
                val answer: Any? = when (call.method) {
                    "read" -> read(id)
                    "write" -> write(id, call.argument<String>("value") ?: throw Unavailable())
                    "reset" -> reset(id, call.argument<String>("revision") ?: throw Unavailable())
                    "delete" -> { delete(id); null }
                    else -> throw Unavailable()
                }
                main.post { result.success(answer) }
            } catch (error: Exception) {
                val code = problem(error)
                // Only an opaque revision is returned, never exceptions or values.
                val revision = try { revision(id) } catch (_: Exception) { "unknown" }
                main.post { result.error(code, "Credential storage unavailable", mapOf("revision" to revision)) }
            }
        }
    }

    private fun problem(error: Exception): String {
        val causes = generateSequence<Throwable>(error) { it.cause }.take(8).toList()
        if (causes.any { it is UserNotAuthenticatedException }) return "unavailable"
        if (error is PendingReset) return "reset_pending"
        if (error is Stale) return "stale"
        return if (causes.any { it is Lost || it is KeyPermanentlyInvalidatedException ||
            it is UnrecoverableKeyException || it is AEADBadTagException }) "permanent" else "unavailable"
    }

    private fun store(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun revision(id: String) = prefs.getString("$id.rev", null) ?: "absent"
    private fun commit(editor: SharedPreferences.Editor) {
        if (!editor.commit()) throw Unavailable()
    }
    private fun read(id: String): Map<String, String> {
        val state = prefs.getString("$id.state", null)
        if (state == "reset_pending") throw PendingReset()
        if (state == "reauth") return mapOf("state" to "reauth", "revision" to revision(id))
        val encoded = data.getString("$id.data", null)
            ?: return mapOf("state" to "missing", "revision" to revision(id))
        val key = store().getKey(PREFIX + id, null) as? SecretKey ?: throw Lost()
        val parts = encoded.split(':')
        if (parts.size != 2) throw Lost()
        val iv: ByteArray
        val bytes: ByteArray
        try {
            iv = Base64.decode(parts[0], Base64.NO_WRAP)
            bytes = Base64.decode(parts[1], Base64.NO_WRAP)
            if (iv.size != 12 || bytes.size < 16) throw Lost()
        } catch (_: IllegalArgumentException) { throw Lost() }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(id.toByteArray(Charsets.UTF_8))
        return mapOf("state" to "ready", "revision" to revision(id),
            "value" to String(cipher.doFinal(bytes), Charsets.UTF_8))
    }
    private fun write(id: String, value: String): Map<String, String> {
        // Never silently replace an existing corrupt key. Only consented reset
        // can remove it. A missing item can create a fresh per-item alias.
        read(id)
        commit(prefs.edit().putBoolean("$id.owned", true))
        val ks = store()
        var key = ks.getKey(PREFIX + id, null) as? SecretKey
        if (key == null) {
            key = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(PREFIX + id,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256).build())
            }.generateKey()
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(id.toByteArray(Charsets.UTF_8))
        val bytes = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val encoded = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(bytes, Base64.NO_WRAP)
        commit(data.edit().putString("$id.data", encoded))
        commit(prefs.edit().putString("$id.state", "ready").putString("$id.rev", UUID.randomUUID().toString()))
        val verified = read(id)
        if (verified["value"] != value) throw Unavailable()
        return verified
    }
    private fun reset(id: String, expectedRevision: String): Map<String, String> {
        if (revision(id) != expectedRevision) throw Stale()
        // Re-check after the confirmation dialog. A healthy replaced item may
        // never be cleared by a stale recovery screen.
        try {
            val current = read(id)
            if (current["state"] == "ready" || current["state"] == "reauth") throw Stale()
        } catch (error: Exception) {
            // Never treat a transient unlock failure (including a wrapped
            // UserNotAuthenticatedException) as consent to destroy a key.
            if (problem(error) !in setOf("permanent", "reset_pending")) throw error
        }
        // This journal precedes deletion. A crash yields a prompt to finish
        // the same scoped reset, never automatic deletion at next startup.
        commit(prefs.edit().putString("$id.state", "reset_pending"))
        store().deleteEntry(PREFIX + id)
        commit(data.edit().remove("$id.data"))
        commit(prefs.edit().putString("$id.state", "reauth").putString("$id.rev", UUID.randomUUID().toString()))
        return read(id)
    }
    private fun delete(id: String): Boolean {
        // Account removal is already an explicit action. Keep the journal
        // until both the exact alias and item are removed successfully.
        commit(prefs.edit().putString("$id.state", "reset_pending"))
        store().deleteEntry(PREFIX + id)
        commit(data.edit().remove("$id.data"))
        commit(prefs.edit().remove("$id.state").remove("$id.rev").remove("$id.owned"))
        return true
    }
    private class Lost : Exception()
    private class PendingReset : Exception()
    private class Stale : Exception()
    private class Unavailable : Exception()
}
