//
//  UIImage+PixelBufferConvertible.swift
//  Pods
//
//  Created by Gonzalo Nunez on 10/7/16.
//
//

#if os(macOS)
import AppKit
public typealias WTColor = NSColor
#else
import UIKit
public typealias WTColor = UIColor
#endif
import AVFoundation

#if os(macOS)
extension NSImage {
  var realSize: CGSize {
    let cgImage = self.cgImage!
    return CGSize(width: cgImage.width, height: cgImage.height)
  }

  var cgImage: CGImage? {
    return cgImage(forProposedRect: nil, context: nil, hints: nil)
  }
}
#endif

public protocol PixelBufferConvertible {
  var pixelBufferSize: CGSize { get }
  func toPixelBuffer() -> CVPixelBuffer?
}

extension WTImage: PixelBufferConvertible {
  
  public var pixelBufferSize: CGSize {
    #if os(macOS)
    let size = self.realSize
    #else
    let size = self.size
    #endif
    if size.width > 1920 || size.height > 1920 {
      let maxRect = (size.width > size.height) ? CGRect(x: 0, y: 0, width: 1920, height: 1080) : CGRect(x: 0, y: 0, width: 1080, height: 1920)
      let aspectRect = AVMakeRect(aspectRatio: size, insideRect: maxRect)
      return aspectRect.size.rounded(to: 16)
    } else {
      return size.rounded(to: 16)
    }
  }
  
  public func toPixelBuffer() -> CVPixelBuffer? {
    
    let options = [kCVPixelBufferCGImageCompatibilityKey as String : NSNumber(value: true),
                   kCVPixelBufferCGBitmapContextCompatibilityKey as String : NSNumber(value: true)] as CFDictionary
    
    let bufferSize = pixelBufferSize
    
    let pxBufferPtr = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
    
    defer {
      pxBufferPtr.deinitialize(count: 1)
    }
    
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(bufferSize.width),
      Int(bufferSize.height),
      kCVPixelFormatType_32ARGB,
      options, pxBufferPtr)
    
    guard let pxBuffer = pxBufferPtr.pointee else {
      return nil
    }
    
    CVPixelBufferLockBaseAddress(pxBuffer, [])
    
    let baseAddress = CVPixelBufferGetBaseAddress(pxBuffer)
    let bytesPerRow = bufferSize.width*4
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    guard let context = CGContext(data: baseAddress, width: Int(bufferSize.width), height: Int(bufferSize.height),
                                  bitsPerComponent: 8, bytesPerRow: Int(bytesPerRow), space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
      else {
        return nil
    }
    
    guard let cgImage = cgImage else {
      return nil
    }
    
    let rect = CGRect(origin: .zero, size: bufferSize)
    
    context.setFillColor(WTColor.white.cgColor)
    context.fill(rect)
    context.interpolationQuality = .high
    
    context.draw(cgImage, in: rect)
    
    CVPixelBufferUnlockBaseAddress(pxBuffer, [])
    
    return pxBuffer
  }
  
}
