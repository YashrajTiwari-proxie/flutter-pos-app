package com.proxiestudio.kds_pos.softpay

import android.content.Context
import com.proxiestudio.kds_pos.BuildConfig
import io.softpay.client.Client
import io.softpay.client.ClientOptions
import io.softpay.client.Softpay
import io.softpay.client.SoftpayTarget
import io.softpay.client.domain.Integrator
import io.softpay.client.domain.IntegratorEnvironment.KotlinEnvironment

/**
 * Creates/holds the single Softpay [Client] used by the Employee Terminal feature.
 *
 * Integrator credentials come from [BuildConfig], which in turn are sourced from
 * `android/local.properties` (gitignored) - see the TODOs there for what must be filled in
 * before this can connect to a real Softpay app.
 */
object SoftPayClientProvider {

    private fun target(): SoftpayTarget? =
        when (BuildConfig.SOFTPAY_TARGET.lowercase()) {
            "sandbox" -> SoftpayTarget.SANDBOX
            "production" -> SoftpayTarget.PRODUCTION
            else -> null // SoftpayTarget.ANY
        }

    private fun integrator(): Integrator {
        val environment = KotlinEnvironment(description = "kds-pos-employee-terminal", appId = "kds_pos")
        return Integrator(
            id = BuildConfig.SOFTPAY_INTEGRATOR_ID,
            merchant = BuildConfig.SOFTPAY_MERCHANT_NAME,
            secret = BuildConfig.SOFTPAY_INTEGRATOR_SECRET.toCharArray(),
            environment = environment,
            target = target(),
        )
    }

    fun getClient(context: Context): Client =
        Softpay.clientOrNew {
            ClientOptions(context = context.applicationContext, integrator = integrator())
        }
}
