import CoreGraphics
import CoreImage
import ImageIO
import Metal
import MetalKit
import UIKit
import UniformTypeIdentifiers

func getTimeStamp() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
    return dateFormatter.string(from: Date())
}

// Converts from texture to png
public func convertMetalTextureToPNG(texture: MTLTexture, fileName: String,
                                     projectDir: String, completion: ((Bool) -> Void)? = nil)
{
    // 1. Configure texture descriptor for CPU access
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: texture.pixelFormat,
        width: texture.width,
        height: texture.height,
        mipmapped: false
    )
    descriptor.usage = .shaderRead // Set appropriate usage
    descriptor.storageMode = .shared

    // 2. Create staging texture for CPU read operations
    let device = texture.device
    guard let stagingTexture = device.makeTexture(descriptor: descriptor)
    else {
        return
    }

    // 3. Create command objects
    guard let commandQueue = device.makeCommandQueue(),
          let commandBuffer = commandQueue.makeCommandBuffer(),
          let blitEncoder = commandBuffer.makeBlitCommandEncoder()
    else {
        logger.log("ERROR: Failed to create command objects")
        return
    }

    // 4. Copy original texture to staging texture
    blitEncoder.copy(
        from: texture,
        sourceSlice: 0,
        sourceLevel: 0,
        sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
        sourceSize: MTLSize(
            width: texture.width, height: texture.height, depth: 1
        ),
        to: stagingTexture,
        destinationSlice: 0,
        destinationLevel: 0,
        destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
    )
    blitEncoder.endEncoding()

    commandBuffer.addCompletedHandler { [weak commandBuffer] _ in

        // 5. Create bitmap context for image processing
        let bytesPerPixel = 4
        let bytesPerRow = texture.width * bytesPerPixel
        let rawData = malloc(texture.height * bytesPerRow)
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)

        // 6. Copy texture data to memory buffer
        stagingTexture.getBytes(
            rawData!,
            bytesPerRow: bytesPerRow,
            from: region,
            mipmapLevel: 0
        )

        // 7. Create CGImage from raw data
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: rawData,
                  width: texture.width,
                  height: texture.height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) // Use noneSkipLast to treat as RGB
        else {
            free(rawData)
            logger.log("ERROR: Failed to create CGContext")
            return
        }

        guard let cgImage = context.makeImage() else {
            free(rawData)
            logger.log("ERROR: Failed to create CGImage")
            return
        }

        let image = UIImage(cgImage: cgImage)
        guard let pngData = image.pngData() else {
            free(rawData)
            logger.log("ERROR: Failed to create PNG data")
            return
        }

        // Validate and prepare project directory path
        let fileManager = FileManager.default
        let projectDirectoryURL = URL(fileURLWithPath: projectDir)

        // Verify directory exists
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(
            atPath: projectDir, isDirectory: &isDirectory
        )
            || !isDirectory.boolValue
        {
            do {
                logger.log("\(projectDir)")
                try fileManager.createDirectory(
                    at: projectDirectoryURL, withIntermediateDirectories: true
                )
            } catch {
                free(rawData)
                logger.log(
                    "ERROR: Could not create project directory: \(error.localizedDescription)"
                )
                return
            }
        }

        let filePath = projectDirectoryURL.appendingPathComponent(
            "\(fileName)_\(getTimeStamp()).png")

        do {
            try pngData.write(to: filePath)
            logger.log("SUCCESS: Metal texture saved as PNG at \(filePath.path)")
            free(rawData)
            completion?(true)
            return
        } catch {
            logger.log(
                "ERROR: Failed to write PNG file: \(error.localizedDescription)"
            )
            free(rawData)
            return
        }
    }

    commandBuffer.commit()
}

func saveMetalTextureAsBMP(texture: MTLTexture, url: URL, completion: ((Bool) -> Void)? = nil) {
    let device = texture.device
    let width = texture.width
    let height = texture.height
    // RGB data with padding for alignment
    let bytesPerRow = width * 4
    let bufferSize = bytesPerRow * height

    guard let sharedBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
        logger.log("Failed to create shared buffer")
        completion?(false)
        return
    }

    guard let commandQueue = device.makeCommandQueue(),
          let commandBuffer = commandQueue.makeCommandBuffer()
    else {
        completion?(false)
        return
    }

    guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
        completion?(false)
        return
    }

    blitEncoder.copy(from: texture,
                     sourceSlice: 0,
                     sourceLevel: 0,
                     sourceOrigin: MTLOriginMake(0, 0, 0),
                     sourceSize: MTLSizeMake(width, height, 1),
                     to: sharedBuffer,
                     destinationOffset: 0,
                     destinationBytesPerRow: bytesPerRow,
                     destinationBytesPerImage: bufferSize)
    blitEncoder.endEncoding()

    // Create a dispatch group to coordinate parallel work
    let group = DispatchGroup()

    // Variable to store destination outside of closures
    var destination: CGImageDestination?
    var destinationCreationFailed = false
    var colorSpace: CGColorSpace?
    var bitmapInfo: CGBitmapInfo?

    // Start a parallel task to create the destination
    group.enter()
    DispatchQueue.global().async {
        if let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.bmp.identifier as CFString, 1, nil
        ) {
            destination = dest
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
            bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue)
        } else {
            logger.log("Failed dest")
            destinationCreationFailed = true
        }
        group.leave()
    }

    // Add completion handler to run when GPU finishes
    commandBuffer.addCompletedHandler { [weak sharedBuffer] _ in
        // This runs on a background thread when the GPU work finishes
        guard let buffer = sharedBuffer else {
            completion?(false)
            return
        }

        let data = buffer.contents()

        guard let colorSpace = colorSpace, let bitmapInfo = bitmapInfo else {
            return
        }

        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            logger.log("Failed CGContext creation")
            completion?(false)
            return
        }

        guard let cgImage = context.makeImage() else {
            logger.log("Failed context.makeImage")
            completion?(false)
            return
        }

        // Wait for destination creation to complete
        group.wait()

        // Check if destination creation succeeded
        guard !destinationCreationFailed, let destination = destination else {
            completion?(false)
            return
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        let success = CGImageDestinationFinalize(destination)

        // Call completion on main thread if needed
        if let completion = completion {
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    // Just commit and continue - don't wait
    commandBuffer.commit()
}
