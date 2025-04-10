import ImageIO
import Metal
import UIKit
import UniformTypeIdentifiers

public enum OutFormat {
    case png
    case heic
}

// Uses BGRA since metal uses it as default
public func metalTextureToImage(texture: MTLTexture, fileName: String,
                                projectDir: String, outFormat: OutFormat)
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
                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
              )
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
        WriteCGIMage(cgImage: cgImage, projectDir: projectDir, fileName: fileName, outFormat: outFormat)
        free(rawData)
    }

    commandBuffer.commit()
}

// Encodes data from CGIMage buffer and writes to disk
func WriteCGIMage(cgImage: CGImage, projectDir: String, fileName: String, outFormat: OutFormat) {
    let image = UIImage(cgImage: cgImage)
    var textureData: Data?
    var fileExtension: String

    switch outFormat {
    case .png:
        textureData = image.pngData()
        fileExtension = ".png"
    case .heic:
        textureData = image.heicData()
        fileExtension = ".heic"
    }

    guard let encodedData = textureData else {
        logger.log("ERROR: Failed to encode data")
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
            logger.log(
                "ERROR: Could not create project directory: \(error.localizedDescription)"
            )
            return
        }
    }

    let filePath = projectDirectoryURL.appendingPathComponent(
        "\(fileName)_\(getTimeStamp())" + fileExtension)

    do {
        try encodedData.write(to: filePath)
        logger.log("SUCCESS: Metal texture saved as \(fileExtension) at \(filePath.path)")
        return
    } catch {
        logger.log(
            "ERROR: Failed to write \(fileExtension) file: \(error.localizedDescription)"
        )
        return
    }
}

// Assuming BGRA since we are dealing with metal
public func texturePrintPixel(texture: MTLTexture, xPos: Int, yPos: Int) {
    let region = MTLRegionMake2D(xPos, yPos, 1, 1)

    let bytesPerPixel = getBytesPerPixel(format: texture.pixelFormat)

    // Buffer to hold the pixel data
    var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)

    // Get the pixel data
    texture.getBytes(&pixelData,
                     bytesPerRow: bytesPerPixel,
                     from: region,
                     mipmapLevel: 0)

    // Print each pixel
    let b = pixelData[0]
    let g = pixelData[1]
    let r = pixelData[2]
    let a = pixelData[3]
    logger.ilog("Pixel at (\(xPos), \(yPos)):  ----->   RGBA: (\(r), \(g), \(b), \(a))")
}

func getTimeStamp() -> String {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
    return dateFormatter.string(from: Date())
}

func getBytesPerPixel(format: MTLPixelFormat) -> Int {
    switch format {
    case .r8Unorm, .r8Snorm, .r8Uint, .r8Sint:
        return 1
    case .r16Unorm, .r16Snorm, .r16Uint, .r16Sint, .r16Float, .rg8Unorm, .rg8Snorm:
        return 2
    case .r32Float, .r32Uint, .r32Sint, .rg16Unorm, .rg16Snorm, .rg16Float:
        return 4
    case .rgba8Unorm, .rgba8Snorm, .rgba8Uint, .rgba8Sint, .bgra8Unorm:
        return 4
    case .rgba16Unorm, .rgba16Snorm, .rgba16Float:
        return 8
    case .rgba32Float, .rgba32Sint, .rgba32Uint:
        return 16
    // Add other formats as needed
    default:
        // For compressed formats, this is an approximation
        return 4
    }
}
