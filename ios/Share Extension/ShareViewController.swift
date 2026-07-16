import receive_sharing_intent

/// The iOS share extension (Requirement 12).
///
/// This is a **separate process** from the app, launched by the system inside
/// whatever app the user is sharing from. It cannot reach the database, the
/// blocs, or anything else in Dart — its entire job is to hand the shared items
/// to the app through the shared App Group container and open it.
///
/// All of that is `RSIShareViewController`. What is left to decide is whether the
/// user sees anything at all on the way through, and this app's answer is no.
///
/// [shouldAutoRedirect] returns true, which skips the plugin's built-in compose
/// UI — the Cancel/Send screen with a caption field. That UI would be wrong here
/// for two reasons. The caption it collects has nowhere to go: nothing in this
/// app's share flow takes a message, because a shared link becomes a bookmark
/// with a derived title and a shared note becomes a document. And the app already
/// asks the only question that matters — *where should this go* — in its own
/// chooser (`ShareSheet`), with the app's fonts, the user's accent, and the
/// destinations that actually fit what arrived. Showing the plugin's sheet first
/// would make sharing a link a two-screen operation where the first screen asks
/// nothing worth answering.
class ShareViewController: RSIShareViewController {

    override func shouldAutoRedirect() -> Bool {
        return true
    }
}
