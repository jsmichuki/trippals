package com.trippals.android

import android.os.Bundle
import android.widget.TextView
import androidx.fragment.app.FragmentActivity

/**
 * Android owns its navigation and screen presentation. Shared code is injected
 * into feature-specific Android UI as those features are implemented.
 */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "TripPals" })
    }
}
