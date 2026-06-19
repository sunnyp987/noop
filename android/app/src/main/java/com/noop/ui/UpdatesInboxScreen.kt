package com.noop.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.DoneAll
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material.icons.outlined.MonitorHeart
import androidx.compose.material.icons.outlined.NotificationsOff
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

// MARK: - Updates inbox
//
// The sheet behind the Today header's bell. A calm, newest-first log of what's new — release notes,
// "new data arrived" readings, strap heads-ups, and the Today info-cards the user swiped away (which
// can be restored from here). Tapping an actionable row routes via the app's nav; a dismissed-card
// row offers "Restore to Today". Everything is on-device and non-clinical — informational, never a
// verdict.
//
// Kotlin port of Strand/Screens/UpdatesInboxView.swift, presented as the content of a ModalBottomSheet
// (the app's sheet idiom — see AppRoot's More / Quick-actions sheets). Tokens only.

/**
 * The inbox sheet body. Hosted inside a [androidx.compose.material3.ModalBottomSheet] by [AppRoot].
 *
 * @param store the shared [UpdateStore] the bell observes.
 * @param onClose dismiss the sheet (after a tap that routes, or a restore).
 * @param onDeepLink route to a destination by its key (e.g. "trends"); unknown keys are ignored.
 * @param onRestore flip a Today card's dismissed flag back on (by its card id) so it reappears.
 */
@Composable
fun UpdatesInboxScreen(
    store: UpdateStore,
    onClose: () -> Unit,
    onDeepLink: (String) -> Unit,
    onRestore: (String) -> Unit,
) {
    val sorted = store.sortedItems
    val unread = sorted.filter { !it.read }
    val read = sorted.filter { it.read }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(Metrics.sectionGap),
    ) {
        // Header — "INBOX" overline + "Updates" title + a live subtitle.
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Overline("Inbox", color = Palette.textTertiary)
            Text("Updates", style = NoopType.title1, color = Palette.textPrimary)
            Text(subtitle(store), style = NoopType.caption, color = Palette.textSecondary)
        }

        if (store.items.isEmpty()) {
            EmptyInboxState()
        } else {
            if (unread.isNotEmpty()) {
                InboxSection(
                    label = "New",
                    items = unread,
                    onTap = { handleTap(it, store, onDeepLink, onClose) },
                    onRestore = { handleRestore(it, store, onRestore, onClose) },
                )
            }
            if (read.isNotEmpty()) {
                InboxSection(
                    label = "Earlier",
                    items = read,
                    onTap = { handleTap(it, store, onDeepLink, onClose) },
                    onRestore = { handleRestore(it, store, onRestore, onClose) },
                )
            }

            // Footer — Clear all (left) + Mark all read (right). Both disabled when they'd no-op.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(
                    onClick = { store.clearAll() },
                    enabled = store.items.isNotEmpty(),
                ) {
                    Icon(
                        Icons.Outlined.DeleteSweep,
                        contentDescription = null,
                        tint = Palette.textSecondary,
                        modifier = Modifier.size(Metrics.iconSmall),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text("Clear all", style = NoopType.subhead, color = Palette.textSecondary)
                }
                Spacer(Modifier.weight(1f))
                TextButton(
                    onClick = { store.markAllRead() },
                    enabled = store.unreadCount > 0,
                ) {
                    Icon(
                        Icons.Outlined.DoneAll,
                        contentDescription = null,
                        tint = if (store.unreadCount > 0) Palette.accent else Palette.textTertiary,
                        modifier = Modifier.size(Metrics.iconSmall),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "Mark all read",
                        style = NoopType.subhead,
                        color = if (store.unreadCount > 0) Palette.accent else Palette.textTertiary,
                    )
                }
            }
        }
    }
}

private fun subtitle(store: UpdateStore): String {
    if (store.items.isEmpty()) return "What's new in the app and your data"
    val n = store.unreadCount
    return if (n == 0) "All caught up" else "$n unread"
}

@Composable
private fun InboxSection(
    label: String,
    items: List<UpdateItem>,
    onTap: (UpdateItem) -> Unit,
    onRestore: (UpdateItem) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Metrics.gap)) {
        Overline(label, color = Palette.textTertiary)
        items.forEach { item ->
            UpdateRow(item = item, onTap = { onTap(item) }, onRestore = { onRestore(item) })
        }
    }
}

@Composable
private fun UpdateRow(
    item: UpdateItem,
    onTap: () -> Unit,
    onRestore: () -> Unit,
) {
    val tint = kindTint(item.kind)
    NoopCard(
        // Unread rows carry the kind's colour wash; read rows sit on the plain navy fill.
        tint = if (item.read) null else tint,
        modifier = Modifier
            .clip(RoundedCornerShape(Metrics.cardRadius))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onTap,
            )
            .semantics {
                contentDescription = if (item.read) {
                    "${item.title}. ${item.message}"
                } else {
                    "Unread. ${item.title}. ${item.message}"
                }
            },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(
                    kindIcon(item.kind),
                    contentDescription = null,
                    tint = tint,
                    modifier = Modifier
                        .size(24.dp)
                        .padding(top = 1.dp),
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text(item.title, style = NoopType.headline, color = Palette.textPrimary)
                    Text(
                        item.message,
                        style = NoopType.subhead,
                        color = Palette.textSecondary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        relativeAgo(item.date / 1000L),
                        style = NoopType.footnote,
                        color = Palette.textTertiary,
                        modifier = Modifier.padding(top = 1.dp),
                    )
                }
                if (!item.read) {
                    // Gold unread dot.
                    Box(
                        modifier = Modifier
                            .padding(top = 5.dp)
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(Palette.gold),
                    )
                }
            }
            if (item.kind == UpdateKind.DISMISSED_CARD) {
                Row(modifier = Modifier.fillMaxWidth()) {
                    TextButton(onClick = onRestore) {
                        Icon(
                            Icons.AutoMirrored.Outlined.Undo,
                            contentDescription = null,
                            tint = Palette.accent,
                            modifier = Modifier.size(Metrics.iconSmall),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text("Restore to Today", style = NoopType.subhead, color = Palette.accent)
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyInboxState() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 40.dp, horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            Icons.Outlined.NotificationsOff,
            contentDescription = null,
            tint = Palette.textTertiary,
            modifier = Modifier.size(34.dp),
        )
        Text("You're all caught up.", style = NoopType.headline, color = Palette.textPrimary)
        Text(
            "New release notes and fresh data will land here.",
            style = NoopType.subhead,
            color = Palette.textSecondary,
        )
    }
}

/** The per-kind icon — mirrors the Swift SF Symbol → Material mapping in the spec. */
private fun kindIcon(kind: UpdateKind): ImageVector = when (kind) {
    UpdateKind.DISMISSED_CARD -> Icons.Outlined.Layers
    UpdateKind.WHATS_NEW -> Icons.Outlined.AutoAwesome
    UpdateKind.READING -> Icons.Outlined.MonitorHeart
    UpdateKind.STRAP_ALERT -> Icons.Outlined.Warning
}

/** A per-kind tint drawn from the domain palette so each row reads in its own colour world.
 *  Mirrors the Swift `UpdateRow.tint`. */
private fun kindTint(kind: UpdateKind): Color = when (kind) {
    UpdateKind.DISMISSED_CARD -> Palette.textSecondary
    UpdateKind.WHATS_NEW -> Palette.accent
    UpdateKind.READING -> Palette.restColor
    UpdateKind.STRAP_ALERT -> Palette.statusWarning
}

/** Tapping a row marks it read, then routes if it carries a deep link (else just stays open). */
private fun handleTap(
    item: UpdateItem,
    store: UpdateStore,
    onDeepLink: (String) -> Unit,
    onClose: () -> Unit,
) {
    store.markRead(item.id)
    val key = item.deepLink ?: return
    onDeepLink(key)
    onClose()
}

/** Restore a dismissed Today card: flip its flag back (so it reappears), drop the inbox item, and
 *  close so the card is on screen. */
private fun handleRestore(
    item: UpdateItem,
    store: UpdateStore,
    onRestore: (String) -> Unit,
    onClose: () -> Unit,
) {
    item.restorePayload?.let { onRestore(it) }
    store.remove(item.id)
    onClose()
}
