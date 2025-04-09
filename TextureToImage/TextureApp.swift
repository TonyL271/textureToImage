import SwiftUI

@main
struct PurpleBackgroundApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var captureImage = false

    var body: some View {
        ZStack {
            MetalView(captureImage: $captureImage)
                .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()
                Button("Capture Image") {
                    captureImage = true
                }
                .padding()
                .background(Color.white.opacity(0.7))
                .cornerRadius(10)
                .padding(.bottom, 50)
            }
        }
    }
}
