package com.fatihgocgun.wisepath

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner

class WisePathApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val app = AppModel.get(this)
        // leaving the screen: the library, the places and the log are on disk before the process can be killed
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStop(owner: LifecycleOwner) {
                app.store.saveNow()
                app.log.save(force = true)
            }
        })
    }
}
