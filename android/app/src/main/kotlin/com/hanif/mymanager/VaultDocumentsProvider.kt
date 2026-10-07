package com.hanif.mymanager

import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Point
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException

/**
 * ব্রাউজার বা যেকোনো অ্যাপের ফাইল-পিকারে ("Choose file" / "Upload") গ্যালারির মতো
 * "ডকুমেন্ট ভল্ট" নামে একটা সোর্স দেখায়।
 *
 * নিরাপত্তা:
 *  • এখানে শুধু সেই ফাইলগুলোই দেখা যায় যা ব্যবহারকারী ভল্টের ভেতর থেকে (ফিঙ্গারপ্রিন্ট/PIN
 *    যাচাইয়ের পর) "আপলোডের জন্য প্রস্তুত করো" চেপে ট্রেতে (cacheDir/vault_out) রেখেছে।
 *    ভল্টের এনক্রিপ্টেড ফাইল এখান থেকে কখনও পড়া যায় না।
 *  • ট্রেতে কিছু না থাকলে রুটটাই দেখায় না।
 *  • ১০ মিনিটের পুরনো ফাইল দেখায় না ও মুছে ফেলে (Dart-এর DocsExport.trayTtl-এর সাথে মেলাতে হবে)।
 *  • MANAGE_DOCUMENTS পারমিশনের কারণে শুধু সিস্টেমের পিকারই এটা কল করতে পারে।
 */
class VaultDocumentsProvider : DocumentsProvider() {

    companion object {
        private const val ROOT_ID = "vault"
        private const val ROOT_DOC_ID = "root"
        private const val TTL_MS = 10 * 60 * 1000L

        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_FLAGS,
            Root.COLUMN_ICON,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID,
        )

        private val DEFAULT_DOC_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE,
        )
    }

    override fun onCreate(): Boolean = true

    private fun trayDir(): File = File(context!!.cacheDir, "vault_out")

    /** মেয়াদ-শেষ ফাইল মুছে বাকিগুলো (নতুন আগে) ফেরত দেয়। */
    private fun liveFiles(): List<File> {
        val dir = trayDir()
        val files = dir.listFiles() ?: return emptyList()
        val now = System.currentTimeMillis()
        val live = ArrayList<File>()
        for (f in files) {
            if (!f.isFile) continue
            if (now - f.lastModified() > TTL_MS) {
                f.delete()
            } else {
                live.add(f)
            }
        }
        live.sortByDescending { it.lastModified() }
        return live
    }

    private fun resolve(documentId: String?): File {
        if (documentId == null) throw FileNotFoundException("no id")
        val dir = trayDir()
        val f = File(dir, documentId)
        // পাথ-ট্রাভার্সাল ঠেকানো: ফাইল অবশ্যই সরাসরি ট্রের ভেতরে হতে হবে।
        if (f.parentFile?.canonicalPath != dir.canonicalPath) throw FileNotFoundException("bad id")
        if (!f.isFile) throw FileNotFoundException("missing")
        if (System.currentTimeMillis() - f.lastModified() > TTL_MS) {
            f.delete()
            throw FileNotFoundException("expired")
        }
        return f
    }

    private fun mimeOf(f: File): String {
        val ext = f.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }

    private fun addFileRow(c: MatrixCursor, f: File) {
        val mime = mimeOf(f)
        var flags = 0
        if (mime.startsWith("image/")) flags = flags or Document.FLAG_SUPPORTS_THUMBNAIL
        c.newRow().apply {
            add(Document.COLUMN_DOCUMENT_ID, f.name)
            add(Document.COLUMN_MIME_TYPE, mime)
            add(Document.COLUMN_DISPLAY_NAME, f.name)
            add(Document.COLUMN_LAST_MODIFIED, f.lastModified())
            add(Document.COLUMN_FLAGS, flags)
            add(Document.COLUMN_SIZE, f.length())
        }
    }

    private fun addRootDirRow(c: MatrixCursor) {
        c.newRow().apply {
            add(Document.COLUMN_DOCUMENT_ID, ROOT_DOC_ID)
            add(Document.COLUMN_MIME_TYPE, Document.MIME_TYPE_DIR)
            add(Document.COLUMN_DISPLAY_NAME, "ডকুমেন্ট ভল্ট")
            add(Document.COLUMN_LAST_MODIFIED, null)
            add(Document.COLUMN_FLAGS, 0)
            add(Document.COLUMN_SIZE, null)
        }
    }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val cols = if (projection != null) arrayOf(*projection) else DEFAULT_ROOT_PROJECTION
        val c = MatrixCursor(cols)
        // ট্রে ফাঁকা হলে রুট লুকানো — পিকারে অকারণ ভিড় হয় না।
        if (liveFiles().isEmpty()) return c
        c.newRow().apply {
            add(Root.COLUMN_ROOT_ID, ROOT_ID)
            add(Root.COLUMN_MIME_TYPES, "*/*")
            add(Root.COLUMN_FLAGS, Root.FLAG_LOCAL_ONLY)
            add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
            add(Root.COLUMN_TITLE, "ডকুমেন্ট ভল্ট")
            add(Root.COLUMN_SUMMARY, "আপলোডের জন্য প্রস্তুত ফাইল")
            add(Root.COLUMN_DOCUMENT_ID, ROOT_DOC_ID)
        }
        return c
    }

    override fun queryDocument(documentId: String?, projection: Array<out String>?): Cursor {
        val cols = if (projection != null) arrayOf(*projection) else DEFAULT_DOC_PROJECTION
        val c = MatrixCursor(cols)
        if (documentId == ROOT_DOC_ID) {
            addRootDirRow(c)
        } else {
            addFileRow(c, resolve(documentId))
        }
        return c
    }

    override fun queryChildDocuments(
        parentDocumentId: String?,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val cols = if (projection != null) arrayOf(*projection) else DEFAULT_DOC_PROJECTION
        val c = MatrixCursor(cols)
        if (parentDocumentId != ROOT_DOC_ID) return c
        for (f in liveFiles()) addFileRow(c, f)
        return c
    }

    override fun openDocument(
        documentId: String?,
        mode: String?,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        // শুধু পড়া — লেখার মোড দিলে অস্বীকার।
        if (mode != null && mode != "r") throw FileNotFoundException("read-only")
        return ParcelFileDescriptor.open(resolve(documentId), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun openDocumentThumbnail(
        documentId: String?,
        sizeHint: Point?,
        signal: CancellationSignal?,
    ): AssetFileDescriptor {
        val pfd = ParcelFileDescriptor.open(resolve(documentId), ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }
}
