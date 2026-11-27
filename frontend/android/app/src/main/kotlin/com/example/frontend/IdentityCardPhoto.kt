package com.example.frontend

import android.graphics.Bitmap
import android.graphics.BitmapRegionDecoder
import android.graphics.Matrix
import android.graphics.Rect
import android.media.ExifInterface
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import kotlin.math.min
import kotlin.math.roundToInt

internal fun registerIdentityCardPhotoChannel(messenger: BinaryMessenger) {
    MethodChannel(
        messenger,
        "yuemnoi/identity_card_photo",
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue(),
    ).setMethodCallHandler { call, result ->
        if (call.method != "prepare") {
            result.notImplemented()
            return@setMethodCallHandler
        }

        val path = call.argument<String>("path")
        val preview = call.argument<Double>("previewAspectRatio")
        val card = call.argument<Double>("cardAspectRatio")
        if (path.isNullOrEmpty() || preview == null || !preview.isFinite() || preview <= 0 ||
            card == null || !card.isFinite() || card <= 0
        ) {
            result.error("invalid_photo", "Invalid card photo arguments", null)
            return@setMethodCallHandler
        }

        try {
            result.success(prepareCardPhoto(path, preview, card))
        } catch (_: Exception) {
            result.error("invalid_photo", "Cannot prepare card photo", null)
        }
    }
}

@Suppress("DEPRECATION")
private fun prepareCardPhoto(path: String, previewAspect: Double, cardAspect: Double): ByteArray {
    val orientation = ExifInterface(path).getAttributeInt(
        ExifInterface.TAG_ORIENTATION,
        ExifInterface.ORIENTATION_NORMAL,
    )
    val swapped = orientation in ExifInterface.ORIENTATION_TRANSPOSE..ExifInterface.ORIENTATION_ROTATE_270
    val preview = if (swapped) 1 / previewAspect else previewAspect
    val card = if (swapped) 1 / cardAspect else cardAspect
    val decoder = checkNotNull(
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) BitmapRegionDecoder.newInstance(path)
        else BitmapRegionDecoder.newInstance(path, false),
    )
    val region = try {
        // เทียบพื้นที่กลางของภาพถ่ายกับสัดส่วนพรีวิว ก่อนเลือกเฉพาะส่วนที่เห็นในกรอบ
        val previewWidth = min(decoder.width.toDouble(), decoder.height * preview)
        val cropWidth = min(previewWidth, previewWidth / preview * card)
        val width = cropWidth.roundToInt().coerceIn(1, decoder.width)
        val height = (cropWidth / card).roundToInt().coerceIn(1, decoder.height)
        val left = (decoder.width - width) / 2
        val top = (decoder.height - height) / 2
        checkNotNull(decoder.decodeRegion(Rect(left, top, left + width, top + height), null))
    } finally {
        decoder.recycle()
    }

    val transform = Matrix()
    when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> transform.setScale(-1f, 1f)
        ExifInterface.ORIENTATION_ROTATE_180 -> transform.setRotate(180f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> transform.setScale(1f, -1f)
        ExifInterface.ORIENTATION_TRANSPOSE, ExifInterface.ORIENTATION_ROTATE_90 ->
            transform.setRotate(90f)
        ExifInterface.ORIENTATION_TRANSVERSE, ExifInterface.ORIENTATION_ROTATE_270 ->
            transform.setRotate(-90f)
    }
    if (orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
        orientation == ExifInterface.ORIENTATION_TRANSVERSE
    ) {
        transform.postScale(-1f, 1f)
    }
    val scale = min(1f, 1800f / if (swapped) region.height else region.width)
    transform.postScale(scale, scale)

    try {
        val output = Bitmap.createBitmap(region, 0, 0, region.width, region.height, transform, true)
        try {
            return ByteArrayOutputStream().use { jpeg ->
                check(output.compress(Bitmap.CompressFormat.JPEG, 90, jpeg))
                jpeg.toByteArray()
            }
        } finally {
            if (output !== region) output.recycle()
        }
    } finally {
        region.recycle()
    }
}
