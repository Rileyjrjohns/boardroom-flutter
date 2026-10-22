/// The connectivity switch shared by the fake remote sources of a test: when it
/// is off, every call to the fake meeting, document and vote repositories fails
/// with `networkUnavailable`.
class FakeNetwork {
  /// Whether the network is up.
  bool online = true;

  /// Cuts the network.
  void goOffline() {
    online = false;
  }

  /// Restores the network.
  void goOnline() {
    online = true;
  }
}
