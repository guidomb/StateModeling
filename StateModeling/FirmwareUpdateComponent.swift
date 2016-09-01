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

public enum Event {
    
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

public enum Command {
    
    case CheckForUpdate(tracker: TrackerMetadata)
    case Download(firmware: FirmwareMetadata)
    case Install(firmware: FirmwareArchive)
    
}

// Views

final class ProgressView: UIView, LoadableView {
    
    @IBOutlet weak var partialLabel: UILabel!
    @IBOutlet weak var totalLabel: UILabel!
    @IBOutlet weak var progressBar: UIProgressView!
    
    var unit = ProgressUnit.Bytes
    
    var progress = Progress(partial: 0, total: 0) {
        didSet {
            if progress.total > 0 {
                partialLabel.text = format(progress.partial)
                totalLabel.text = format(progress.total)
                progressBar.progress = progress.relative
            }
        }
    }
    
    init() {
        super.init(frame: CGRect.zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func format(value: UInt) -> String {
        switch unit {
        case .Bytes:
            return "\(value) B"
        case .KiloBytes:
            return "\(value / 1024) KB"
        case .MegaBytes:
            return "\(value / 1024 / 1024) MB"
        }
    }
    
}

final class IdleView: UIView {
    
    @IBOutlet weak var checkForUpdateButton: UIButton!
    
    private let _onTap: () -> ()
    
    init(onTap: () -> ()) {
        _onTap = onTap
        super.init(frame: CGRect.zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    func handleTap() {
        _onTap()
    }
    
}

final class FirmwareUpdateController: BaseComponentController<State, Event, FirmwareUpdateComponent> {
    
    init(tracker: TrackerMetadata) {
        let commandExecutor = FirmwareUpdateCommandExecutor(
            firmwareService: MockFirmwareService(),
            trackerService: MockTrackerService()
        )
        let component = FirmwareUpdateComponent(
            tracker: tracker,
            commandExecutor: AnyCommandExecutor(commandExecutor: commandExecutor)
        )
        super.init(state: component.state, dispatcher: component)
    }
    
    override func render(state: State) -> View {
        let dispatch = dispatcher.dispatch
        
        switch state {
            
        case .Idle(_):
            return IdleView { dispatch(.CheckForUpdate) }
            
        case .Downloading(_, let progress):
            return RecyclerView(viewClass: ProgressView.self) {
                $0.unit = .KiloBytes
                $0.progress = progress
            }
            
        default:
            // TODO handle all possible states
            return UIView()
            
        }
    }
    
}

// Update

public final class FirmwareUpdateComponent: BaseComponent<State, Event, Command, AnyCommandExecutor<Event, Command>> {
    
    
    init(tracker: TrackerMetadata, commandExecutor: AnyCommandExecutor<Event, Command>) {
        super.init(initialState: .Idle(tracker: tracker), commandExecutor: commandExecutor)
    }
    
    public override func handle(event: Event) -> (State, Command?)? {
        switch (state.value, event) {
            
            
        case (.Idle(let tracker), .CheckForUpdate):
            return (.CheckingForUpdate(tracker: tracker), .CheckForUpdate(tracker: tracker))
            
        case (.CheckingForUpdate(let tracker), .FailedToCheckForUpdate(let error)):
            return (.CheckForUpdateError(tracker: tracker, error: error), .None)
            
        case (.CheckingForUpdate(let tracker), .UpdateUnavailable):
            return (.UpToDate(firmwareVersion: tracker.firmwareVersion), .None)
            
        case (.CheckingForUpdate(_), .UpdateAvailable(let firmware)):
            return (.PendingDownload(firmware: firmware), .None)
            
        case (.PendingDownload(let firmware), .Download):
            let progress = Progress(partial: 0, total: firmware.size)
            return (.Downloading(firmware: firmware, progress: progress), .Download(firmware: firmware))
            
        case (.Downloading(let firmware, _), .ProgressUpdate(let progress)):
            return (.Downloading(firmware: firmware, progress: progress), .None)
            
        case (.Downloading(let firmware, _), .FailedToDownload(let error)):
            return (.DownloadError(firmware: firmware, error: error), .None)
            
        case (.Downloading(let metadata, _), .DownloadCompleted(let archive)):
            let firmware = FirmwareArchive(metadata: metadata, archive: archive, downloadedAt: NSDate())
            return (.PendingInstall(firmware: firmware), .None)
            
        case (.PendingInstall(let firmware), .Install):
            let progress = Progress(partial: 0, total: firmware.metadata.size)
            return (.Installing(firmware: firmware, progress: progress), .Install(firmware: firmware))
            
        case (.Installing(let firmware, _), .ProgressUpdate(let progress)):
            return (.Installing(firmware: firmware, progress: progress), .None)
            
        case (.Installing(let firmware, _), .FailedToInstall(let error)):
            return (.InstallError(firmware: firmware, error: error), .None)
            
        case (.Installing(let firmware, _), .TransferCompleted):
            return (.UpToDate(firmwareVersion: firmware.metadata.version), .None)
            
            
        default:
            return .None
            
        }
    }
    
}

final class FirmwareUpdateCommandExecutor: ReactiveCommandExecutor<Event, Command> {
    
    private let _firmwareService: FirmwareService
    private let _trackerService: TrackerService
    
    init(firmwareService: FirmwareService, trackerService: TrackerService) {
        _firmwareService = firmwareService
        _trackerService = trackerService
    }
    
    override func execute(command: Command) -> SignalProducer<Event, NoError> {
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
    
    private func checkForUpdate(tracker: TrackerMetadata) -> SignalProducer<Event, NoError> {
        // TODO check in the local file system if there are archive already
        // downloaded
        return _firmwareService.checkForUpdate(tracker)
            .map {
                if let firmware = $0 {
                    return Event.UpdateAvailable(firmware: firmware)
                } else {
                    return Event.UpdateUnavailable
                }
            }
            .flatMapError { SignalProducer(value: .FailedToCheckForUpdate(error: $0)) }
    }
    
    private func download(firmwareMetadata: FirmwareMetadata) -> SignalProducer<Event, NoError> {
        return _firmwareService.download(firmwareMetadata)
            .map {
                switch $0 {
                case .Chunck(let progress):
                    return Event.ProgressUpdate(progress: progress)
                case .Completed(let archive):
                    return Event.DownloadCompleted(archive: archive)
                }
            }
            .flatMapError { SignalProducer(value: .FailedToDownload(error: $0)) }
    }
    
    private func install(firmware: FirmwareArchive) -> SignalProducer<Event, NoError> {
        return _trackerService.install(firmware)
            .map {
                switch $0 {
                case .Chunck(let progress):
                    return Event.ProgressUpdate(progress: progress)
                case .Completed(_):
                    return Event.TransferCompleted
                }
            }
            .flatMapError { SignalProducer(value: .FailedToInstall(error: $0)) }
    }
    
}


// Models

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
    
    var relative: Float { return Float(partial) / Float(total) }
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