package com.example.hangman

import android.util.Log
import com.salesforce.marketingcloud.MCLogListener
import com.salesforce.marketingcloud.MarketingCloudConfig
import com.salesforce.marketingcloud.MarketingCloudSdk
import com.salesforce.marketingcloud.notifications.NotificationCustomizationOptions
import com.salesforce.marketingcloud.sfmcsdk.SFMCSdk
import com.salesforce.marketingcloud.sfmcsdk.SFMCSdkModuleConfig
import com.salesforce.marketingcloud.sfmcsdk.components.logging.LogLevel
import com.salesforce.marketingcloud.sfmcsdk.components.logging.LogListener
import io.flutter.app.FlutterApplication

class HangmanApp : FlutterApplication() {

    override fun onCreate() {
        super.onCreate()
        SFMCSdk.requestSdk { sdk ->
            sdk.mp { push ->
                push.registrationManager.registerForRegistrationEvents {
                    Log.i("~\$HangmanApp", it.toString())
                }
            }
        }

        SFMCSdk.configure(applicationContext, SFMCSdkModuleConfig.build {
            pushModuleConfig = MarketingCloudConfig.builder().apply {
                    //Update these details based on your MC config
                    setApplicationId(BuildConfig.PUSH_APP_ID)
                    setAccessToken(BuildConfig.PUSH_ACCESS_TOKEN)
                    setMarketingCloudServerUrl(BuildConfig.PUSH_SERVER_URL)
                    setSenderId(BuildConfig.PUSH_SENDER_ID)
                    setNotificationCustomizationOptions(
                        NotificationCustomizationOptions.create(
                            R.mipmap.ic_launcher
                        )
                    )
                    setAnalyticsEnabled(true)
                }.build(applicationContext)
        }) {}
    }
}