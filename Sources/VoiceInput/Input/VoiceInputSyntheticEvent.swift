import CoreGraphics

enum VoiceInputSyntheticEvent {
    // Stable process-local marker used only to keep our event tap from treating
    // generated paste events as physical keyboard input.
    static let marker: Int64 = 0x564F_4943_4549_4E50

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    static func isMarked(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }
}
