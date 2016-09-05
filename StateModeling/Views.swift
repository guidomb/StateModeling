//
//  Views.swift
//  StateModeling
//
//  Created by Guido Marucci Blas on 9/2/16.
//  Copyright © 2016 GuidoMB. All rights reserved.
//

import UIKit

final class ProgressView: UIView, LoadableView {
    
    struct Model {
        
        private let unit: ProgressUnit
        private let progress: Progress
        
        var partial: String { return format(progress.partial) }
        var total: String { return format(progress.total) }
        
        init(unit: ProgressUnit = .Bytes, progress: Progress = Progress(partial: 0, total: 0)) {
            self.unit = unit
            self.progress = progress
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
    
    @IBOutlet weak var partialLabel: UILabel!
    @IBOutlet weak var totalLabel: UILabel!
    @IBOutlet weak var progressBar: UIProgressView!
    
    var model = ProgressView.Model() {
        didSet {
            partialLabel.text = model.partial
            totalLabel.text = model.total
            progressBar.progress = model.progress.relative
        }
    }
    
    init() {
        super.init(frame: CGRect.zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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