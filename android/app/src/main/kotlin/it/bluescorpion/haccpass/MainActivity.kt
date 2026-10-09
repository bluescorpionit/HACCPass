package it.bluescorpion.haccpass

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Prompt 17: canale interno SPP per la stampante generica
        // Bluetooth classico (RFCOMM), dietro ByteTransport.
        SppBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            applicationContext,
        )
    }
}
