package com.flamesup.nativeapp

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val coreStatus = runCatching { NativeCore.initNativeCore() }
            .getOrElse { "Native core failed: ${it.message}" }
        val rankedItems = runCatching { NativeCore.rankPreview().toList() }
            .getOrElse { listOf("Rust ranking unavailable: ${it.message}") }

        setContentView(buildContent(coreStatus, rankedItems))
    }

    private fun buildContent(coreStatus: String, rankedItems: List<String>): View {
        val scroll = ScrollView(this)
        scroll.setBackgroundColor(Color.rgb(248, 248, 243))

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(18), dp(18), dp(28))
        }

        root.addView(header())
        root.addView(tabRow())
        root.addView(coreCard(coreStatus))
        root.addView(heroCard(rankedItems.firstOrNull() ?: "For You is ready"))
        root.addView(sectionTitle("Native ranking preview"))

        rankedItems.forEachIndexed { index, item ->
            root.addView(rankTile(index + 1, item))
        }

        scroll.addView(root)
        return scroll
    }

    private fun header(): View = LinearLayout(this).apply {
        gravity = Gravity.CENTER_VERTICAL
        orientation = LinearLayout.HORIZONTAL

        addView(TextView(context).apply {
            text = "🔥"
            textSize = 28f
            gravity = Gravity.CENTER
            setBackgroundColor(Color.rgb(52, 211, 74))
        }, LinearLayout.LayoutParams(dp(42), dp(42)))

        addView(TextView(context).apply {
            text = "  Flames"
            textSize = 30f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.BLACK)
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        addView(pill("+", true))
    }

    private fun tabRow(): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setPadding(0, dp(18), 0, dp(14))
        addView(pill("World Board", false))
        addView(space(dp(10), 1))
        addView(pill("For You", true))
    }

    private fun coreCard(status: String): View = card().apply {
        addView(sectionTitle("Kotlin + Rust + C++"))
        addView(bodyText(status))
        addView(bodyText("Android Studio project with JNI bridge and native ranking core."))
    }

    private fun heroCard(title: String): View = card().apply {
        setBackgroundColor(Color.BLACK)
        setPadding(dp(18), dp(180), dp(18), dp(20))
        addView(TextView(context).apply {
            text = title
            textSize = 30f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
        })
        addView(TextView(context).apply {
            text = "Tap-to-pause video feed layout will land here next."
            textSize = 15f
            setTextColor(Color.rgb(230, 230, 230))
            setPadding(0, dp(8), 0, 0)
        })
    }

    private fun rankTile(index: Int, item: String): View = card().apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(TextView(context).apply {
            text = index.toString()
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.BLACK)
            setBackgroundColor(Color.rgb(52, 211, 74))
        }, LinearLayout.LayoutParams(dp(44), dp(44)))
        addView(TextView(context).apply {
            text = "  $item"
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.BLACK)
        })
    }

    private fun sectionTitle(value: String): TextView = TextView(this).apply {
        text = value
        textSize = 20f
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(Color.BLACK)
        setPadding(0, dp(6), 0, dp(8))
    }

    private fun bodyText(value: String): TextView = TextView(this).apply {
        text = value
        textSize = 15f
        setTextColor(Color.rgb(72, 72, 72))
        setPadding(0, dp(4), 0, dp(4))
    }

    private fun card(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(18), dp(18), dp(18), dp(18))
        setBackgroundColor(Color.WHITE)
        val params = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        )
        params.setMargins(0, dp(8), 0, dp(10))
        layoutParams = params
    }

    private fun pill(label: String, active: Boolean): TextView = TextView(this).apply {
        text = label
        textSize = 15f
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setTextColor(if (active) Color.WHITE else Color.BLACK)
        setBackgroundColor(if (active) Color.BLACK else Color.WHITE)
        setPadding(dp(16), dp(10), dp(16), dp(10))
    }

    private fun space(width: Int, height: Int): View = View(this).apply {
        layoutParams = LinearLayout.LayoutParams(width, height)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
