package com.trippals.shared.platform

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AndroidNetworkReachabilityMonitor(context: Context) : NetworkReachabilityMonitor {
    private val connectivityManager = context.applicationContext.getSystemService(ConnectivityManager::class.java)
    private val mutableReachability = MutableStateFlow(currentReachability())
    override val reachability = mutableReachability.asStateFlow()
    private var started = false

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = update()
        override fun onLost(network: Network) = update()
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = update()
    }

    override fun start() {
        if (!started) {
            started = true
            connectivityManager.registerDefaultNetworkCallback(callback)
            update()
        }
    }

    override fun stop() {
        if (started) {
            started = false
            connectivityManager.unregisterNetworkCallback(callback)
        }
    }

    private fun update() {
        mutableReachability.value = currentReachability()
    }

    private fun currentReachability(): NetworkReachability {
        val capabilities = connectivityManager.getNetworkCapabilities(connectivityManager.activeNetwork)
        return if (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true) {
            NetworkReachability.AVAILABLE
        } else {
            NetworkReachability.UNAVAILABLE
        }
    }
}
