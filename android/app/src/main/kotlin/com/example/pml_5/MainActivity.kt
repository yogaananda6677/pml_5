package com.example.pml_5

import android.os.Bundle
import android.util.Log
import com.google.firebase.installations.FirebaseInstallations
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        FirebaseInstallations.getInstance().id.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                val id = task.result
                Log.i("FIAM.Headless", "Starting InAppMessaging runtime with Installation ID $id")
            } else {
                Log.e("FIAM.Headless", "Failed to get Installation ID", task.exception)
            }
        }
    }
}
