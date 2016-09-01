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
    
    associatedtype EventType
    associatedtype CommandType
    
    func execute(command: CommandType, handler: (EventType) -> ())
    
}

public final class AnyCommandExecutor<EventType, CommandType>: CommandExecutor {
    
    private let _execute: (CommandType, (EventType) -> ()) -> ()
    
    init<CommandExecutorType: CommandExecutor
        where   CommandExecutorType.EventType == EventType,
                CommandExecutorType.CommandType == CommandType>(commandExecutor: CommandExecutorType) {
        _execute = commandExecutor.execute
    }
    
    public func execute(command: CommandType, handler: (EventType) -> ()) {
        _execute(command, handler)
    }
    
}

public class ReactiveCommandExecutor<EventType, CommandType>: CommandExecutor {
    
    typealias EventProducer = SignalProducer<EventType, NoError>
    
    final public func execute(command: CommandType, handler: (EventType) -> ()) {
        execute(command).startWithNext(handler)
    }
    
    func execute(command: CommandType) -> EventProducer {
        return EventProducer.empty
    }

}

public protocol Component {
    
    associatedtype StateType
    associatedtype EventType
    associatedtype CommandType
    
    var state: AnyProperty<StateType> { get }
    
    func handle(event: EventType) -> (StateType, CommandType?)?
    
}

public protocol Dispatcher {
    
    associatedtype EventType
    
    func dispatch(event: EventType)
    
}

public class BaseComponent<StateType, EventType, CommandType, CommandExecutorType: CommandExecutor
    where   CommandExecutorType.EventType == EventType,
            CommandExecutorType.CommandType == CommandType>: Component, Dispatcher {
    
    public let state: AnyProperty<StateType>
    
    private let _state: MutableProperty<StateType>
    private let _commandExecutor: CommandExecutorType
    
    init(initialState: StateType, commandExecutor: CommandExecutorType) {
        _commandExecutor = commandExecutor
        _state = MutableProperty(initialState)
        state = AnyProperty(_state)
    }
    
    public final func dispatch(event: EventType) {
        if let (nextState, maybeCommand) = handle(event) {
            _state.value = nextState
            if let command = maybeCommand {
                _commandExecutor.execute(command, handler: dispatch)
            }
        }
    }
    
    public func handle(event: EventType) -> (StateType, CommandType?)? {
        return .None
    }
    
}

public final class AnyComponent<StateType, EventType, CommandType, CommandExecutorType: CommandExecutor
    where   CommandExecutorType.EventType == EventType,
            CommandExecutorType.CommandType == CommandType>: BaseComponent<StateType, EventType, CommandType, CommandExecutorType> {
    
    private let _handler: (EventType) -> (StateType, CommandType?)?
    
//    init<ComponentType: Component
//        where   ComponentType.StateType == StateType,
//                ComponentType.EventType == EventType,
//                ComponentType.CommandType == CommandType>(component: ComponentType) {
//        self.init(initialState: component.state.value, commandExecutor: component._commandExecutor)
//    }
    
    init(initialState: StateType, commandExecutor: CommandExecutorType, handler: (EventType) -> (StateType, CommandType?)?) {
        _handler = handler
        super.init(initialState: initialState, commandExecutor: commandExecutor)
    }
    
    override public func handle(event: EventType) -> (StateType, CommandType?)? {
        return _handler(event)
    }
    
}


// Views

protocol View {
    
    func renderIn(containerView containerView: UIView)
    
}

extension UIView: View {
    
    func renderIn(containerView containerView: UIView) {
        containerView.subviews.forEach { $0.removeFromSuperview() }
        containerView.addSubview(self)
        
        self.topAnchor.constraintEqualToAnchor(containerView.topAnchor).active = true
        self.bottomAnchor.constraintEqualToAnchor(containerView.bottomAnchor).active = true
        self.leadingAnchor.constraintEqualToAnchor(containerView.leadingAnchor).active = true
        self.trailingAnchor.constraintEqualToAnchor(containerView.trailingAnchor).active = true
    }
    
}

protocol LoadableView {
    
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

//
// TODO
//
// Think about how things like alerts should be handled. Probably the best thing
// would be to have an AlertView which conforms to Alert and make the controller 
// intercept it and present an alert view controller
//
// Things like transitions, push a controller to the navigation stack should be
// handled by the parent components and the child components should send an 
// OutputMessage. Is the resposability of the parent to know which controller to present
// next. Container controller should not have a componenet associated with them. They
// should only compose component controllers and coordinate transitions. Pretty much
// like a coordinator.
//
public class BaseComponentController<StateType, EventType, DispatcherType: Dispatcher
    where DispatcherType.EventType == EventType>: UIViewController {

    public let dispatcher: DispatcherType
    
    private let _state: AnyProperty<StateType>
    
    init(state: AnyProperty<StateType>, dispatcher: DispatcherType) {
        _state = state
        self.dispatcher = dispatcher
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        _state.producer
            .map { [unowned self] in self.render($0) }
            .observeOn(UIScheduler())
            .startWithNext { [unowned self] in
                $0.renderIn(containerView: self.view)
            }
    }
    
    func render(state: StateType) -> View {
        return UIView()
    }
    
}

final class ComponentController<StateType, EventType, DispatcherType: Dispatcher
    where DispatcherType.EventType == EventType>: BaseComponentController<StateType, EventType, DispatcherType> {

    typealias Renderer = (DispatcherType, StateType) -> View
    
    private let _renderer: Renderer
    
    init(state: AnyProperty<StateType>, dispatcher: DispatcherType, renderer: Renderer) {
        _renderer = renderer
        super.init(state: state, dispatcher: dispatcher)
    }
    
    override func render(state: StateType) -> View {
        return _renderer(dispatcher, state)
    }
    
}
