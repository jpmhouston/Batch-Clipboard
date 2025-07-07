import Intents

@available(macOS 11.0, *)
class ClearIntentHandler: NSObject, ClearIntentHandling {
  private var model: AppModel!

  init(_ model: AppModel) {
    self.model = model
  }

  func handle(intent: ClearIntent, completion: @escaping (ClearIntentResponse) -> Void) {
    model.clearUnpinned()
    return completion(ClearIntentResponse(code: .success, userActivity: nil))
  }
}
