package com.boardroom.screenprotection

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Registers the calls, and the stream of capture events, of the plugin, and follows the activity,
 * which owns the window the protection acts on. There is no secure view on Android: the window flag
 * keeps the whole window out of captures, so the Dart widget renders its child as it is.
 */
class ScreenProtectionPlugin :
    FlutterPlugin,
    ActivityAware {
    private val host = ScreenProtectionHost()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ScreenProtectionHostApi.setUp(binding.binaryMessenger, host)
        StreamCaptureEventsStreamHandler.register(
            binding.binaryMessenger,
            object : StreamCaptureEventsStreamHandler() {
                override fun onListen(p0: Any?, sink: PigeonEventSink<CaptureEventMessage>) = host.startListening(sink)

                override fun onCancel(p0: Any?) = host.stopListening()
            },
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ScreenProtectionHostApi.setUp(binding.binaryMessenger, null)
        StreamCaptureEventsStreamHandler.register(binding.binaryMessenger, object : StreamCaptureEventsStreamHandler() {})
        host.tearDown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = host.attachActivity(binding.activity)

    override fun onDetachedFromActivityForConfigChanges() = host.attachActivity(null)

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = host.attachActivity(binding.activity)

    override fun onDetachedFromActivity() = host.attachActivity(null)
}
