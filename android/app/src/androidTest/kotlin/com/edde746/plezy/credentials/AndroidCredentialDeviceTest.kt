package com.edde746.plezy.credentials

import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.plezy.credentials.AndroidCredentialStorePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Explicit opt-in only, on a disposable emulator. Every value is fabricated. */
@RunWith(AndroidJUnit4::class)
class AndroidCredentialDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private fun guard() {
        assertEquals("true", InstrumentationRegistry.getArguments().getString("plezy.disposable"))
        assertTrue("A disposable emulator is required", Build.PRODUCT.contains("sdk_gphone"))
    }
    private fun id(name: String) = MessageDigest.getInstance("SHA-256")
        .digest("plezy-disposable-test:$name".toByteArray()).joinToString("") { "%02x".format(it) }
    private fun engine(): FlutterEngine {
        guard()
        lateinit var engine: FlutterEngine
        instrumentation.runOnMainSync { engine = FlutterEngine(context) }
        return engine
    }
    private data class Reply(val value: Any?, val error: String?, val details: Any?)
    private fun call(engine: FlutterEngine, operation: String, name: String, extra: Map<String, String> = emptyMap()): Reply {
        val plugin = engine.plugins.get(AndroidCredentialStorePlugin::class.java) as? AndroidCredentialStorePlugin
        assertNotNull("Generated registration must include the credential plugin", plugin)
        val latch = CountDownLatch(1)
        var reply: Reply? = null
        instrumentation.runOnMainSync {
            plugin!!.onMethodCall(MethodCall(operation, mapOf("id" to id(name)) + extra), object : MethodChannel.Result {
                override fun success(result: Any?) { reply = Reply(result, null, null); latch.countDown() }
                override fun error(code: String, message: String?, details: Any?) { reply = Reply(null, code, details); latch.countDown() }
                override fun notImplemented() { reply = Reply(null, "not_implemented", null); latch.countDown() }
            })
        }
        assertTrue("Native operation timed out", latch.await(20, TimeUnit.SECONDS))
        return reply!!
    }
    private fun destroy(engine: FlutterEngine) = instrumentation.runOnMainSync { engine.destroy() }
    private fun value(reply: Reply): Map<*, *> {
        assertNull("Unexpected native failure: ${reply.error}", reply.error)
        return reply.value as Map<*, *>
    }

    @Test fun writeReadAndDeleteAcrossFreshEngines() {
        val first = engine()
        try {
            value(call(first, "write", "roundtrip", mapOf("value" to "fake-roundtrip")))
            assertEquals("fake-roundtrip", value(call(first, "read", "roundtrip"))["value"])
        } finally { destroy(first) }
        val second = engine()
        try {
            assertEquals("fake-roundtrip", value(call(second, "read", "roundtrip"))["value"])
            assertNull(call(second, "delete", "roundtrip").error)
            assertEquals("missing", value(call(second, "read", "roundtrip"))["state"])
        } finally { destroy(second) }
    }

    @Test fun lostKeyRequiresScopedResetAndReauthentication() {
        val engine = engine()
        try {
            value(call(engine, "write", "lost", mapOf("value" to "fake-old")))
            value(call(engine, "write", "unrelated", mapOf("value" to "fake-unrelated")))
            val data = context.getSharedPreferences("plezy_android_credentials_v1", Context.MODE_PRIVATE)
            val before = data.getString("${id("lost")}.data", null)
            val legacy = context.getSharedPreferences("plezy_disposable_test_legacy", Context.MODE_PRIVATE)
            legacy.edit().putString("source", "fake-legacy-recovery").commit()
            KeyStore.getInstance("AndroidKeyStore").apply { load(null); deleteEntry("com.plezy.credentials.android.v1.${id("lost")}") }
            val failed = call(engine, "read", "lost")
            assertEquals("permanent", failed.error)
            assertEquals(before, data.getString("${id("lost")}.data", null))
            val revision = (failed.details as Map<*, *>)["revision"] as String
            assertEquals("reauth", value(call(engine, "reset", "lost", mapOf("revision" to revision)))["state"])
            assertEquals("fake-unrelated", value(call(engine, "read", "unrelated"))["value"])
            assertEquals("fake-legacy-recovery", legacy.getString("source", null))
            value(call(engine, "write", "lost", mapOf("value" to "fake-reauthenticated")))
            assertEquals("fake-reauthenticated", value(call(engine, "read", "lost"))["value"])
            assertEquals("stale", call(engine, "reset", "lost", mapOf("revision" to revision)).error)
            call(engine, "delete", "lost"); call(engine, "delete", "unrelated")
            legacy.edit().remove("source").commit()
        } finally { destroy(engine) }
    }

    @Test fun seedProcessRestart() {
        val engine = engine()
        try { value(call(engine, "write", "process-restart", mapOf("value" to "fake-persistent"))) }
        finally { destroy(engine) }
    }

    @Test fun verifyProcessRestartAndDelete() {
        val engine = engine()
        try {
            assertEquals("fake-persistent", value(call(engine, "read", "process-restart"))["value"])
            assertNull(call(engine, "delete", "process-restart").error)
            assertEquals("missing", value(call(engine, "read", "process-restart"))["state"])
        } finally { destroy(engine) }
    }
}
