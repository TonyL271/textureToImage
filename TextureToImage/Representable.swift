import Foundation
import MetalKit
import os.log
import SwiftUI

extension Logger {
    func ilog(_ items: Any...) {
        let stringified = items.map { String(describing: $0) }.joined(separator: "")
        self.log("\(stringified)")
    }
}

let logger = Logger(subsystem: "MetalDraw", category: "general")

struct MetalView: UIViewRepresentable {
    @Binding var captureImage: Bool

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("ERROR: Metal is not supported on this device")
        }

        let mtkView = MTKView(frame: .zero, device: device)
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = false // Critical change: disable framebuffer-only to allow texture capture

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("ERROR: Failed to create Metal command queue")
        }

        let renderer = PurpleRenderer(device: device, commandQueue: commandQueue)
        mtkView.delegate = renderer
        context.coordinator.renderer = renderer

        return mtkView
    }

    func updateUIView(_: MTKView, context: Context) {
        if self.captureImage {
            if let renderer = context.coordinator.renderer {
                renderer.shouldCaptureNextFrame = true
            }
            DispatchQueue.main.async {
                self.captureImage = false // Reset flag after triggering capture
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var renderer: PurpleRenderer?
    }
}
