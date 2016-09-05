//
//  FirmwareUpdateComponent.swift
//  StateModeling
//
//  Created by Guido Marucci Blas on 9/1/16.
//  Copyright © 2016 GuidoMB. All rights reserved.
//

import UIKit
import ReactiveCocoa
import Result

public enum State {
    
    case Idle(tracker: TrackerMetadata)
    case CheckingForUpdate(tracker: TrackerMetadata)
    case CheckForUpdateError(tracker: TrackerMetadata, error: NSError)
    case PendingDownload(firmware: FirmwareMetadata)
    case Downloading(firmware: FirmwareMetadata, progress: Progress)
    case DownloadError(firmware: FirmwareMetadata, error: NSError)
    case PendingInstall(firmware: FirmwareArchive)
    case Installing(firmware: FirmwareArchive, progress: Progress)
    case InstallError(firmware: FirmwareArchive, error: NSError)
    case UpToDate(firmwareVersion: SemanticVersion)
    
}

public enum InputMessage {
    
    case CheckForUpdate
    case UpdateUnavailable
    case FailedToCheckForUpdate(error: NSError)
    case UpdateAvailable(firmware: FirmwareMetadata)
    case Download
    case FailedToDownload(error: NSError)
    case ProgressUpdate(progress: Progress)
    case DownloadCompleted(archive: NSURL)
    case Install
    case FailedToInstall(error: NSError)
    case TransferCompleted
    
}


public enum OutputMessage {
    
    case InstallCompleted(firmwareVersion: SemanticVersion)
    
}

public enum Command {
    
    case CheckForUpdate(tracker: TrackerMetadata)
    case Download(firmware: FirmwareMetadata)
    case Install(firmware: FirmwareArchive)
    
}

final class FirmwareUpdateController: ComponentController<State, InputMessage, OutputMessage, Command, FirmwareUpdateCommandExecutor> {
    
    init(tracker: TrackerMetadata) {
        let commandExecutor = FirmwareUpdateCommandExecutor(
            firmwareService: MockFirmwareService(),
            trackerService: MockTrackerService()
        )
        let initialState = State.Idle(tracker: tracker)
        let component = Component(initialState: initialState, commandExecutor: commandExecutor, behavior: behavior)
        super.init(component: component)
    }
    
    override func render(state: State) -> View {
        
        switch state {
            
        case .Idle(_):
            return IdleView { [unowned self] in self.dispatch(.CheckForUpdate) }
            
        case .CheckForUpdateError(_, _):
            let primary = AlertAction(title: "Retry") { [unowned self] in self.dispatch(.CheckForUpdate) }
            let secondary = AlertAction(title: "OK", action: {})
            return AlertView(
                title: "Error",
                message: "There was an error checking for update.",
                primaryAction: primary,
                secondaryAction: secondary
            )
            
        case .Downloading(_, let progress):
            return RecyclerView(viewClass: ProgressView.self) {
                $0.model = ProgressView.Model(unit: .KiloBytes, progress: progress)
            }
            
        case .DownloadError(let firmware, _):
            let primary = AlertAction(title: "Retry") { [unowned self] in self.dispatch(.Download) }
            let secondary = AlertAction(title: "OK", action: {})
            return AlertView(
                title: "Error",
                message: "There was an error downloading firmware version \(firmware.version).",
                primaryAction: primary,
                secondaryAction: secondary
            )
            
        case .InstallError(let firmware, _):
            let primary = AlertAction(title: "Retry") { [unowned self] in self.dispatch(.Install) }
            let secondary = AlertAction(title: "OK", action: {})
            return AlertView(
                title: "Error",
                message: "There was an error installing firmware version \(firmware.metadata.version).",
                primaryAction: primary,
                secondaryAction: secondary
            )
            
        default:
            // TODO handle all possible states
            return UIView()
            
        }
    }
    
}

// Update

public func behavior(state: State, message: InputMessage) -> (State, Command?, OutputMessage?)? {
    switch (state, message) {
        
    case (.Idle(let tracker), .CheckForUpdate):
        return (.CheckingForUpdate(tracker: tracker), .CheckForUpdate(tracker: tracker), .None)
        
    case (.CheckingForUpdate(let tracker), .FailedToCheckForUpdate(let error)):
        return (.CheckForUpdateError(tracker: tracker, error: error), .None, .None)
        
    case (.CheckForUpdateError(let tracker, _), .CheckForUpdate):
        return (.CheckingForUpdate(tracker: tracker), .CheckForUpdate(tracker: tracker), .None)
        
    case (.CheckingForUpdate(let tracker), .UpdateUnavailable):
        return (.UpToDate(firmwareVersion: tracker.firmwareVersion), .None, .None)
        
    case (.CheckingForUpdate(_), .UpdateAvailable(let firmware)):
        return (.PendingDownload(firmware: firmware), .None, .None)
        
    case (.PendingDownload(let firmware), .Download):
        let progress = Progress(partial: 0, total: firmware.size)
        return (.Downloading(firmware: firmware, progress: progress), .Download(firmware: firmware), .None)
        
    case (.Downloading(let firmware, _), .ProgressUpdate(let progress)):
        return (.Downloading(firmware: firmware, progress: progress), .None, .None)
        
    case (.Downloading(let firmware, _), .FailedToDownload(let error)):
        return (.DownloadError(firmware: firmware, error: error), .None, .None)
        
    case (.DownloadError(let firmware, _), .Download):
        let progress = Progress(partial: 0, total: firmware.size)
        return (.Downloading(firmware: firmware, progress: progress), .Download(firmware: firmware), .None)
        
    case (.Downloading(let metadata, _), .DownloadCompleted(let archive)):
        let firmware = FirmwareArchive(metadata: metadata, archive: archive, downloadedAt: NSDate())
        return (.PendingInstall(firmware: firmware), .None, .None)
        
    case (.PendingInstall(let firmware), .Install):
        let progress = Progress(partial: 0, total: firmware.metadata.size)
        return (.Installing(firmware: firmware, progress: progress), .Install(firmware: firmware), .None)
        
    case (.Installing(let firmware, _), .ProgressUpdate(let progress)):
        return (.Installing(firmware: firmware, progress: progress), .None, .None)
        
    case (.Installing(let firmware, _), .FailedToInstall(let error)):
        return (.InstallError(firmware: firmware, error: error), .None, .None)
        
    case (.InstallError(let firmware, _), .Install):
        let progress = Progress(partial: 0, total: firmware.metadata.size)
        return (.Installing(firmware: firmware, progress: progress), .Install(firmware: firmware), .None)
        
    case (.Installing(let firmware, _), .TransferCompleted):
        return (.UpToDate(firmwareVersion: firmware.metadata.version), .None, .InstallCompleted(firmwareVersion: firmware.metadata.version))
        
        
    default:
        return .None
        
    }
}

final class FirmwareUpdateCommandExecutor: ReactiveCommandExecutor<InputMessage, Command> {
    
    private let _firmwareService: FirmwareService
    private let _trackerService: TrackerService
    
    init(firmwareService: FirmwareService, trackerService: TrackerService) {
        _firmwareService = firmwareService
        _trackerService = trackerService
    }
    
    override func execute(command: Command) -> SignalProducer<InputMessage, NoError> {
        switch command {
            
        case .CheckForUpdate(let tracker):
            return checkForUpdate(tracker)
            
        case .Download(let firmware):
            return download(firmware)
            
        case .Install(let firmware):
            return install(firmware)
            
        }
    }
    
}

private extension FirmwareUpdateCommandExecutor {
    
    private func checkForUpdate(tracker: TrackerMetadata) -> SignalProducer<InputMessage, NoError> {
        // TODO check in the local file system if there are archive already
        // downloaded
        return _firmwareService.checkForUpdate(tracker)
            .map {
                if let firmware = $0 {
                    return InputMessage.UpdateAvailable(firmware: firmware)
                } else {
                    return InputMessage.UpdateUnavailable
                }
            }
            .flatMapError { SignalProducer(value: .FailedToCheckForUpdate(error: $0)) }
    }
    
    private func download(firmwareMetadata: FirmwareMetadata) -> SignalProducer<InputMessage, NoError> {
        return _firmwareService.download(firmwareMetadata)
            .map {
                switch $0 {
                case .Chunck(let progress):
                    return InputMessage.ProgressUpdate(progress: progress)
                case .Completed(let archive):
                    return InputMessage.DownloadCompleted(archive: archive)
                }
            }
            .flatMapError { SignalProducer(value: .FailedToDownload(error: $0)) }
    }
    
    private func install(firmware: FirmwareArchive) -> SignalProducer<InputMessage, NoError> {
        return _trackerService.install(firmware)
            .map {
                switch $0 {
                case .Chunck(let progress):
                    return InputMessage.ProgressUpdate(progress: progress)
                case .Completed(_):
                    return InputMessage.TransferCompleted
                }
            }
            .flatMapError { SignalProducer(value: .FailedToInstall(error: $0)) }
    }
    
}


// Services

protocol FirmwareService {
    
    func checkForUpdate(tracker: TrackerMetadata) -> SignalProducer<FirmwareMetadata?, NSError>
    
    func download(firmware: FirmwareMetadata) -> SignalProducer<TransferState<NSURL>, NSError>
    
}

protocol TrackerService {
    
    func install(firmware: FirmwareArchive) -> SignalProducer<TransferState<Void>, NSError>
    
}

final class MockFirmwareService: FirmwareService {
    
    func checkForUpdate(tracker: TrackerMetadata) -> SignalProducer<FirmwareMetadata?, NSError> {
        return SignalProducer.empty
    }
    
    func download(firmware: FirmwareMetadata) -> SignalProducer<TransferState<NSURL>, NSError> {
        return SignalProducer.empty
    }
    
}

final class MockTrackerService: TrackerService {
    
    func install(firmware: FirmwareArchive) -> SignalProducer<TransferState<Void>, NSError> {
        return SignalProducer.empty
    }
    
}