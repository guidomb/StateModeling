//
//  State.swift
//  StateModeling
//
//  Created by Guido Marucci Blas on 8/28/16.
//  Copyright © 2016 GuidoMB. All rights reserved.
//

import UIKit
import ReactiveCocoa
import Result


public protocol CommandExecutor {
    
    associatedtype InputMessageType
    associatedtype CommandType
    
    func execute(command: CommandType, handler: (InputMessageType) -> ())
    
}

public final class AnyCommandExecutor<InputMessageType, CommandType>: CommandExecutor {
    
    private let _execute: (CommandType, (InputMessageType) -> ()) -> ()
    
    init<CommandExecutorType: CommandExecutor
        where   CommandExecutorType.InputMessageType == InputMessageType,
                CommandExecutorType.CommandType == CommandType>(commandExecutor: CommandExecutorType) {
        _execute = commandExecutor.execute
    }
    
    public func execute(command: CommandType, handler: (InputMessageType) -> ()) {
        _execute(command, handler)
    }
    
}

public final class VoidCommandExecutor<InputMessageType>: CommandExecutor {
    
    public func execute(command: Void, handler: (InputMessageType) -> ()) {
        
    }
    
}

public class ReactiveCommandExecutor<InputMessageType, CommandType>: CommandExecutor {
    
    typealias MessageProducer = SignalProducer<InputMessageType, NoError>
    
    final public func execute(command: CommandType, handler: (InputMessageType) -> ()) {
        execute(command).startWithNext(handler)
    }
    
    func execute(command: CommandType) -> MessageProducer {
        return MessageProducer.empty
    }

}

public protocol Dispatcher {
    
    associatedtype InputMessageType
    
    func dispatch(message: InputMessageType)
    
}

public final class Component<StateType, InputMessageType, OutputMessageType, CommandType, CommandExecutorType: CommandExecutor
    where   CommandExecutorType.InputMessageType == InputMessageType,
            CommandExecutorType.CommandType == CommandType>: Dispatcher {

    public typealias Behavior = (StateType, InputMessageType) -> (StateType, CommandType?, OutputMessageType?)?
    
    public let state: AnyProperty<StateType>
    public let messages: Signal<OutputMessageType, NoError>
    
    private let _state: MutableProperty<StateType>
    private let _commandExecutor: CommandExecutorType
    private let _messagesObserver: Observer<OutputMessageType, NoError>
    private let _behavior: Behavior
    
    init(initialState: StateType, commandExecutor: CommandExecutorType, behavior: Behavior) {
        _state = MutableProperty(initialState)
        state = AnyProperty(_state)
        _commandExecutor = commandExecutor
        (messages, _messagesObserver) = Signal<OutputMessageType, NoError>.pipe()
        _behavior = behavior
    }
    
    deinit {
        _messagesObserver.sendCompleted()
    }
    
    public func dispatch(message: InputMessageType) {
        if let (nextState, maybeCommand, maybeMessage) = _behavior(state.value, message) {
            _state.value = nextState
            if let command = maybeCommand {
                _commandExecutor.execute(command, handler: self.dispatch)
            }
            if let message = maybeMessage {
                _messagesObserver.sendNext(message)
            }
        }

    }
    
}


// Views

protocol View { }

protocol Renderable {
    
    func renderIn(containerView containerView: UIView)
    
}

protocol Presentable {
    
    func presentIn(container containerController: UIViewController)
    
}

extension UIView: View, Renderable {
    
    func renderIn(containerView containerView: UIView) {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        loadInto(containerView)
    }
    
}

protocol LoadableView: View {
    
    static func loadFromNib() -> Self?
    
    static func cast(view: UIView) -> Self?
    
}

extension LoadableView {
    
    static func loadFromNib() -> Self? {
        // TODO Add real implementation
        return .None
    }
    
    static func cast(view: UIView) -> Self? {
        return view as? Self
    }
    
}

final class RecyclerView<ViewType: LoadableView where ViewType: UIView> {
    
    private let _configure: (ViewType) -> ()
    private let _viewClass: ViewType.Type
    
    init(viewClass: ViewType.Type, configure: (ViewType) -> ()) {
        _viewClass = viewClass
        _configure = configure
    }
    
}

extension RecyclerView: View {
    
    func renderIn(containerView containerView: UIView) {
        if let genericSubview = containerView.subviews.first, let subview = _viewClass.cast(genericSubview) {
            _configure(subview)
        } else {
            if let view = _viewClass.loadFromNib() {
                view.renderIn(containerView: containerView)
                _configure(view)
            } else {
                print("View of type \(_viewClass) could not be loaded")
            }
        }
    }
    
}

struct AlertAction {
    
    let title: String
    let action: () -> ()
    
}

struct AlertView: View {
    
    let title: String
    let message: String
    let primaryAction: AlertAction
    let secondaryAction: AlertAction
    
}

extension AlertView: Presentable {
    
    func presentIn(container containerController: UIViewController) {
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .Alert
        )
        let primary = UIAlertAction(
            title: primaryAction.title,
            style: .Default,
            handler: { _ in self.primaryAction.action() }
        )
        let secondary = UIAlertAction(
            title: secondaryAction.title,
            style: .Cancel,
            handler: { _ in self.secondaryAction.action() }
        )
        alertController.addAction(primary)
        alertController.addAction(secondary)
        
        containerController.presentViewController(alertController, animated: true, completion: nil)
    }
    
}

public enum ViewPositioning {
    case Back
    case Front
}

extension UIView {
    
    /**
     Loads the view into the specified containerView.
     
     - warning: It must be done after self's view is loaded.
     - note: It uses constraints to determine the size, so the frame isn't needed. Because of this, `loadInto()` can be used in viewDidLoad().
     - parameter containerView: The container view.
     - parameter viewPositioning: Back or Front. Default: Front
     */
    public func loadInto(containerView: UIView, viewPositioning: ViewPositioning = .Front) {
        containerView.addSubview(self)
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        
        containerView.topAnchor.constraintEqualToAnchor(topAnchor).active = true
        containerView.bottomAnchor.constraintEqualToAnchor(bottomAnchor).active = true
        containerView.leadingAnchor.constraintEqualToAnchor(leadingAnchor).active = true
        containerView.trailingAnchor.constraintEqualToAnchor(trailingAnchor).active = true
        
        if case viewPositioning = ViewPositioning.Back {
            containerView.sendSubviewToBack(self)
        }
    }
    
}

extension UIViewController {
    
    /**
     Loads the childViewController into the specified containerView.
     
     It can be done after self's view is initialized, as it uses constraints to determine the childViewController size.
     Take into account that self will retain the childViewController, so if for any other reason the childViewController is retained in another place, this would
     lead to a memory leak. In that case, one should call unloadViewController().
     
     - parameter childViewController: The controller to load.
     - parameter into: The containerView into which the controller will be loaded.
     - parameter viewPositioning: Back or Front. Default: Front
     */
    public func load(childViewController childViewController: UIViewController, into containerView: UIView, viewPositioning: ViewPositioning = .Front) {
        childViewController.willMoveToParentViewController(self)
        addChildViewController(childViewController)
        childViewController.didMoveToParentViewController(self)
        childViewController.view.loadInto(containerView, viewPositioning: viewPositioning)
    }
    
}

public class ComponentController<StateType, InputMessageType, OutputMessageType, CommandType, CommandExecutorType: CommandExecutor
    where   CommandExecutorType.InputMessageType == InputMessageType,
            CommandExecutorType.CommandType == CommandType>: UIViewController, Dispatcher {

    typealias ComponentType = Component<StateType, InputMessageType, OutputMessageType, CommandType, CommandExecutorType>
    
    public var messages: Signal<OutputMessageType, NoError> { return _component.messages }
    
    private let _component: ComponentType
    
    init(component: ComponentType) {
        _component = component
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        // TODO maybe we could add some logic here to filter states that don't need to
        // be rendered. To do this we need views to have an associated state and those
        // states should be comparables.
        //
        // For that to be implemetned view should have a comparable model associated with them.
        // And in orther to be performant models should be reference values and the default comparison
        // should be by reference.
        _component.state.producer
            .map { [unowned self] in self.render($0) }
            .observeOn(UIScheduler())
            .startWithNext { [unowned self] view in
                switch view {
                    
                case let renderable as Renderable:
                    renderable.renderIn(containerView: self.view)
                
                case let presentable as Presentable:
                    presentable.presentIn(container: self)
                
                default:
                    break
                
                }
            }
    }
    
    public final func dispatch(message: InputMessageType) {
        _component.dispatch(message)
    }
    
    func render(state: StateType) -> View {
        return UIView()
    }
    
}
