import Foundation

@main
struct ModelSelectorTests {
    static func main() async {
        let model = await ModelSelector.shared.fastestAvailable()
        precondition(!model.isEmpty)
        print("Automatic model: \(model)")
    }
}
