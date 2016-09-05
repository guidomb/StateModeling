//
//  Models.swift
//  StateModeling
//
//  Created by Guido Marucci Blas on 9/2/16.
//  Copyright © 2016 GuidoMB. All rights reserved.
//

import Foundation

public struct TrackerMetadata {
    
    let firmwareVersion: SemanticVersion
    let modelNumber: UInt
    let hardwareRevision: HardwareRevision
    
}

public struct SemanticVersion {
    
    let mayor: UInt
    let minor: UInt
    let patch: UInt
    
}

public struct HardwareRevision {
    
    let minor: UInt
    let patch: UInt
    
}

public struct FirmwareMetadata {
    
    let version: SemanticVersion
    let hardwareRevision: HardwareRevision
    let modelNumber: UInt
    let bucket: String
    let key: String
    let size: UInt
    
}

public struct FirmwareArchive {
    
    let metadata: FirmwareMetadata
    let archive: NSURL
    let downloadedAt: NSDate
    
}

public struct Progress {
    
    let partial: UInt
    let total: UInt
    
    var relative: Float { return total > 0 ? Float(partial) / Float(total) : 0 }
    var percentage: Float { return relative * 100.0 }
    
}

public enum TransferState<Value> {
    
    case Chunck(progress: Progress)
    case Completed(value: Value)
    
}

public enum ProgressUnit {
    
    case Bytes
    case KiloBytes
    case MegaBytes
    
}