import MetalKit
import os.log

class PurpleRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let texture: MTLTexture
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let blitCommandQueue: MTLCommandQueue // Dedicated command queue for blit operations

    var shouldCaptureNextFrame = false // Flag to trigger capture on next frame

    // Vertices for a full-screen quad (position x,y only - 2D)
    private let vertices: [Float] = [
        -1.0, -1.0, // bottom left
        1.0, -1.0, // bottom right
        -1.0, 1.0, // top left
        1.0, 1.0, // top right
    ]

    init(device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue

        // Create dedicated blit command queue
        guard let blitQueue = device.makeCommandQueue() else {
            fatalError("ERROR: Failed to create blit command queue")
        }
        self.blitCommandQueue = blitQueue

        self.texture = PurpleRenderer.createPurpleTexture(device: device)
        self.pipelineState = PurpleRenderer.create2DPipelineState(device: device)

        let vertexDataSize = self.vertices.count * MemoryLayout<Float>.stride
        guard
            let buffer = device.makeBuffer(
                bytes: vertices, length: vertexDataSize, options: []
            )
        else {
            fatalError("ERROR: Failed to create vertex buffer")
        }
        self.vertexBuffer = buffer

        super.init()
    }

    private static func createPurpleTexture(device: MTLDevice) -> MTLTexture {
        let width = 1
        let height = 1
        var pixelData: [UInt8] = [128, 0, 128, 255] // R=128, G=0, B=128, A=255

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: textureDescriptor)
        else {
            fatalError("ERROR: Failed to create texture")
        }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: &pixelData,
            bytesPerRow: 4
        ) // 4 bytes per pixel (RGBA)

        return texture
    }

    private static func create2DPipelineState(device: MTLDevice)
        -> MTLRenderPipelineState
    {
        let library = device.makeDefaultLibrary()
        guard
            let vertexFunction = library?.makeFunction(name: "vertex2DShader"),
            let fragmentFunction = library?.makeFunction(
                name: "fragment2DShader")
        else {
            fatalError("ERROR: Failed to create shader functions")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            return try device.makeRenderPipelineState(
                descriptor: pipelineDescriptor)
        } catch {
            fatalError(
                "ERROR: Failed to create render pipeline state: \(error)")
        }
    }

    func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor)
        else { return }
        renderEncoder.setRenderPipelineState(self.pipelineState)
        renderEncoder.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)

        // Set the texture
        renderEncoder.setFragmentTexture(self.texture, index: 0)
        renderEncoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: 4
        )

        renderEncoder.endEncoding()

        guard let drawable = view.currentDrawable else { return }

        // Capture this frame if requested
        if self.shouldCaptureNextFrame {
            let mtlTexture = self.texture
            let currentFileURL = URL(fileURLWithPath: #file)
            let projectDir = currentFileURL.deletingLastPathComponent().path + "/Outputs"

            // ---------------------------- Save Texture as PNG -------------------------------------------------------

            texturePrintPixel(texture: self.texture, xPos: 0, yPos: 0)
            let startTimePNG = CFAbsoluteTimeGetCurrent()
            metalTextureToImage(
                texture: drawable.texture, fileName: "screen",
                projectDir: projectDir, outFormat: .png
            )
            let endTimePNG = CFAbsoluteTimeGetCurrent()

            let elapsedTimePNG = endTimePNG - startTimePNG
            logger.log("------PNG  took \(elapsedTimePNG) seconds")

            // ---------------------------- Save Texture as heic -------------------------------------------------------

            let startTimeBMP = CFAbsoluteTimeGetCurrent()
            // Create a URL for a file in the Documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let bmpFileURL = documentsPath.appendingPathComponent("metalTexture.bmp")

            metalTextureToImage(
                texture: drawable.texture, fileName: "screen",
                projectDir: projectDir, outFormat: .heic
            )

            let endTimeBMP = CFAbsoluteTimeGetCurrent()
            let elapsedTime = endTimeBMP - startTimeBMP
            logger.log("------BMP  took \(elapsedTime) seconds")
            logger.log("\n\n")

            self.shouldCaptureNextFrame = false // Reset flag
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}
}
