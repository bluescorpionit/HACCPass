package it.bluescorpion.haccpass

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID

/**
 * Collegamento Bluetooth classico SPP/RFCOMM per la stampante generica
 * (Prompt 17). Canale interno "haccpass/spp": poche decine di righe su
 * BluetoothAdapter/BluetoothSocket dietro l'interfaccia Dart
 * `BluetoothSppByteTransport`, così nulla di critico dipende da un
 * plugin esterno (flutter_classic_bluetooth 1.7.0 richiede Flutter 3.44:
 * vedi docs/stampanti.md).
 *
 * Codici errore distinti (messaggi in italiano lato Dart):
 * "off" (Bluetooth spento), "permission" (BLUETOOTH_CONNECT negato),
 * "not_bonded" (dispositivo non associato), "unreachable" (spenta o
 * fuori portata), "busy" (socket già aperto), "timeout",
 * "lost" (connessione caduta durante l'invio).
 */
object SppState {
    @Volatile var socket: BluetoothSocket? = null
    @Volatile var output: java.io.OutputStream? = null
    @Volatile var address: String? = null
}

class SppBridge private constructor(private val context: Context) {
    private val ioLock = Any()

    private val adapter: BluetoothAdapter? by lazy {
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    }

    companion object {
        @Volatile private var instance: SppBridge? = null

        fun from(context: Context): SppBridge =
            instance ?: synchronized(this) {
                instance ?: SppBridge(context.applicationContext).also { instance = it }
            }

        /** Registra il canale "haccpass/spp": chiamato da MainActivity. */
        fun register(
            messenger: io.flutter.plugin.common.BinaryMessenger,
            context: Context,
        ) {
            MethodChannel(messenger, "haccpass/spp").setMethodCallHandler { call, result ->
                from(context).handle(call, result)
            }
        }

        /** UUID standard del Serial Port Profile. */
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(adapter != null)
            "isAdapterOn" -> result.success(adapter?.isEnabled == true)
            "openBluetoothSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                result.success(true)
            }
            "listPaired" -> listPaired(result)
            "connect" -> connect(call.argument<String>("address")!!, result)
            "write" -> write(call.argument<ByteArray>("bytes")!!, result)
            "disconnect" -> disconnect(result)
            else -> result.notImplemented()
        }
    }

    @SuppressLint("MissingPermission")
    private fun listPaired(result: MethodChannel.Result) {
        val a = adapter ?: return result.error("off", "Bluetooth non disponibile", null)
        if (!a.isEnabled) return result.error("off", "Bluetooth spento", null)
        try {
            val devices = a.bondedDevices.orEmpty().map { d ->
                mapOf("name" to (d.name ?: ""), "address" to d.address)
            }
            result.success(devices)
        } catch (e: SecurityException) {
            result.error("permission", "Permesso Bluetooth negato", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        synchronized(ioLock) {
        val a = adapter ?: return result.error("off", "Bluetooth non disponibile", null)
        if (!a.isEnabled) return result.error("off", "Bluetooth spento", null)
        if (SppState.socket?.isConnected == true && SppState.address == address) {
            return result.success(true)
        }
        // Evita collisioni con vecchie sessioni/socket lasciati appesi.
        disconnectQuietly()
        // La discovery attiva degrada/rompe spesso la RFCOMM connect.
        try {
            a.cancelDiscovery()
        } catch (_: SecurityException) {
            return result.error("permission", "Permesso Bluetooth negato", null)
        }

        val device: BluetoothDevice = try {
            a.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            return result.error("not_bonded", "Indirizzo non valido", null)
        }
        // Solo dispositivi associati: la scoperta non serve (Prompt 17 §2).
        val bonded = try {
            a.bondedDevices.orEmpty().any { it.address == address }
        } catch (e: SecurityException) {
            return result.error("permission", "Permesso Bluetooth negato", null)
        }
        if (!bonded) {
            return result.error("not_bonded", "Dispositivo non associato", null)
        }
        // Connessione RFCOMM sequenziale. Ordine: non sicuro → sicuro →
        // canale 1 (stampanti vecchie via reflection).
        val socket = try {
            trySocket(device, secure = false)
                ?: trySocket(device, secure = true)
                ?: legacyChannel1(device)
        } catch (e: Throwable) {
            return result.error(classify(e), "Connessione non riuscita", null)
        }
        if (socket == null) {
            return result.error("unreachable", "Socket non stabilito", null)
        }
        SppState.socket = socket
        SppState.address = address
        SppState.output = try {
            socket.outputStream
        } catch (e: IOException) {
            disconnectQuietly()
            return result.error("lost", "Stream non disponibile", null)
        }
        result.success(true)
        }
    }

    @SuppressLint("MissingPermission")
    private fun trySocket(device: BluetoothDevice, secure: Boolean): BluetoothSocket? {
        val socket: BluetoothSocket = try {
            if (secure) {
                device.createRfcommSocketToServiceRecord(SPP_UUID)
            } else {
                device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
            }
        } catch (e: SecurityException) {
            return null
        }
        return try {
            socket.connect()
            socket
        } catch (_: Throwable) {
            try {
                socket.close()
            } catch (_: Throwable) {
            }
            null
        }
    }

    /** Ripiego per stampanti vecchie: canale RFCOMM 1 via reflection. */
    private fun legacyChannel1(device: BluetoothDevice): BluetoothSocket? {
        var socket: BluetoothSocket? = null
        return try {
            val method =
                device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
            socket = method.invoke(device, 1) as BluetoothSocket
            socket.connect()
            socket
        } catch (_: Throwable) {
            try {
                socket?.close()
            } catch (_: Throwable) {
            }
            null
        }
    }

    /** Classifica l'errore di connessione per i messaggi lato Dart. */
    private fun classify(cause: Throwable?): String = when {
        cause is SecurityException -> "permission"
        else -> "unreachable"
    }

    private fun write(bytes: ByteArray, result: MethodChannel.Result) {
        synchronized(ioLock) {
        val out = SppState.output
            ?: return result.error("lost", "Socket non aperto", null)
        try {
            out.write(bytes)
            out.flush()
            result.success(true)
        } catch (e: IOException) {
            disconnectQuietly()
            result.error("lost", "Scrittura fallita", null)
        }
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        synchronized(ioLock) {
        disconnectQuietly()
        result.success(true)
        }
    }

    /** Flush + attesa 500 ms + close: mai chiusure brusche. */
    private fun disconnectQuietly() {
        val socket = SppState.socket ?: return
        SppState.socket = null
        SppState.output = null
        SppState.address = null
        try {
            socket.outputStream?.flush()
        } catch (_: Throwable) {
        }
        try {
            Thread.sleep(500)
        } catch (_: InterruptedException) {
        }
        try {
            socket.close()
        } catch (_: Throwable) {
        }
    }
}
