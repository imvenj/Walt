//
//  Walt.swift
//  Pods
//
//  Created by Gonzalo Nunez on 10/3/16.
//
//
#if os(macOS)
import AppKit
#else
import UIKit
import MobileCoreServices
#endif
import AVFoundation

import ImageIO

public typealias DataCompletionBlock = (URL, Data?) -> Void

public enum WaltError: Error {
  case noImages
  case durationZero
  case fileExists
}

public enum Walt {
  
  //MARK: Movies
  
  fileprivate static let k2500kbps = 2500 * 1000
  fileprivate static let kVideoQueue = DispatchQueue(label: "com.ZenunSoftware.Walt.VideoQueue")
  
  public static func writeMovie(with images: [WTImage],
                                options: MovieWritingOptions,
                                completion: @escaping DataCompletionBlock) throws
  {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com-ZenunSoftware-Walt-Movie.MOV")
    return try writeMovie(with: images, options: options, url: url, completion: completion)
  }
  
  public static func writeMovie(with images: [WTImage],
                                options: MovieWritingOptions,
                                url: URL,
                                completion: @escaping DataCompletionBlock) throws
  {
    if images.count < 2 {
      throw WaltError.noImages
    }
    
    if options.loopDuration == 0 || options.duration == 0 {
      throw WaltError.durationZero
    }
    
    if (FileManager.default.fileExists(atPath: url.path)) {
      if options.shouldOverwrite {
        try FileManager.default.removeItem(atPath: url.path)
      } else {
        throw WaltError.fileExists
      }
    }
    
    let assetWriter = try AVAssetWriter(url: url, fileType: AVFileType.mov)
    
    let frameSize = images[0].pixelBufferSize
    let iterations = Int(ceil(Double(options.duration)/options.loopDuration))
    let fps = Int(ceil(Double(images.count)/options.loopDuration))
    
    var finalVideoArray = [WTImage]()
    for _ in 0..<iterations {
      finalVideoArray.append(contentsOf: images)
    }
    
      let outputSettings: [String : Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                          AVVideoWidthKey: frameSize.width,
                                          AVVideoHeightKey: frameSize.height,
                                          AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
                                          AVVideoCompressionPropertiesKey: [AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                                                            AVVideoAverageBitRateKey: Walt.k2500kbps,
                                                                            AVVideoExpectedSourceFrameRateKey: fps]]
    
    let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
    assetWriterInput.expectsMediaDataInRealTime = true
    
    let attributes: [String : Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                                      kCVPixelBufferWidthKey as String: frameSize.width,
                                      kCVPixelBufferHeightKey as String: frameSize.height,
                                      kCVPixelFormatCGBitmapContextCompatibility as String: true,
                                      kCVPixelFormatCGImageCompatibility as String: true]
    
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: attributes)
    
    assetWriter.add(assetWriterInput)
    assetWriter.startWriting()
    assetWriter.startSession(atSourceTime: CMTime.zero)
    
    var pxBufferIndex = 0
    
    assetWriterInput.requestMediaDataWhenReady(on: Walt.kVideoQueue) { [weak assetWriter] in
      guard let assetWriter = assetWriter else { return }
      
      while assetWriterInput.isReadyForMoreMediaData {
        
        if pxBufferIndex < finalVideoArray.count {
          if let pxBuffer = finalVideoArray[pxBufferIndex].toPixelBuffer() {
            adaptor.append(pxBuffer, withPresentationTime: CMTime(value: CMTimeValue(pxBufferIndex), timescale: CMTimeScale(fps)))
          }
        }
        
        if pxBufferIndex == finalVideoArray.count {
          assetWriterInput.markAsFinished()
          assetWriter.finishWriting {
            if assetWriter.status == .completed {
              DispatchQueue.main.async {
                  let data = try? Data(contentsOf: url)
                  completion(url, data)
              }
            }
          }
        }
        
        pxBufferIndex += 1
      }
    }
  }
  
  //MARK: Gifs
  
  public static func createGif(with images: [WTImage],
                               options: GifWritingOptions,
                               completion: @escaping DataCompletionBlock) throws
  {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("com-ZenunSoftware-Walt-Gif.gif")
    return try createGif(with: images, options: options, url: url, completion: completion)
  }

  
  public static func createGif(with images: [WTImage],
                               options: GifWritingOptions,
                               url: URL,
                               completion: @escaping DataCompletionBlock) throws
  {
    if images.count < 2 {
      throw WaltError.noImages
    }
    
    if options.duration == 0 {
      throw WaltError.durationZero
    }
    
    if (FileManager.default.fileExists(atPath: url.path)) {
      if options.shouldOverwrite {
        try FileManager.default.removeItem(atPath: url.path)
      } else {
        throw WaltError.fileExists
      }
    }
    
    DispatchQueue.global(qos: .userInitiated).async {
      guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeGIF, images.count, nil) else {
        DispatchQueue.main.async {
          completion(url, nil)
        }
        return
      }
      
      let desiredFrameDuration = options.duration/Double(images.count)
      let clampedFrameDuration = max(0.1, desiredFrameDuration)
      
      let delayTimes = [kCGImagePropertyGIFUnclampedDelayTime as String: desiredFrameDuration,
                        kCGImagePropertyGIFDelayTime as String: clampedFrameDuration]
      
      let gifProperties = [kCGImagePropertyGIFDictionary as String: options.gifLoop.dict]
      CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)
      
      let frameProperties = [kCGImagePropertyGIFDictionary as String: delayTimes]
      
      let first = images.first!
      let scaledSize = first.size.scaled(by: options.scale)
      
      for image in images {
        #if os(macOS)
        let result = NSImage(size: scaledSize)
        result.lockFocus()
        let rect = CGRect(origin: .zero, size: scaledSize)
        image.draw(in: rect)
        result.unlockFocus()
        guard let cgImage = result.cgImage else {
          if options.skipsFailedImages {
            continue
          }

          DispatchQueue.main.async {
            completion(url, nil)
          }

          return
        }
        #else
        UIGraphicsBeginImageContext(scaledSize)

        defer {
          UIGraphicsEndImageContext()
        }

        let rect = CGRect(origin: .zero, size: scaledSize)
        image.draw(in: rect)

        guard let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else {
          if options.skipsFailedImages {
            continue
          }

          DispatchQueue.main.async {
            completion(url, nil)
          }

          return
        }
        #endif
        
        CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
      }
      
      CGImageDestinationFinalize(destination)
      
      let data = try? Data(contentsOf: url)
      
      DispatchQueue.main.async {
        completion(url, data)
      }
    }
  }
  
}
