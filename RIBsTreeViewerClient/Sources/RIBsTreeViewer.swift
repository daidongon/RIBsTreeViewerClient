//
//  RIBsTreeViewer.swift
//  RIBsTreeViewerClient
//
//  Created by yuki tamazawa on 2019/01/16.
//  Copyright © 2019 minipro. All rights reserved.
//

import Foundation
import RxSwift
import RIBs
import SocketIO

public enum RIBsTreeViewerOptions: String {
    case socketURL
}

public class RIBsTreeViewer {

    private let router: Routing
    private let socketClient: SocketClient
    private let disposeBag = DisposeBag()

    public init(router: Routing, option: [RIBsTreeViewerOptions: String]? = nil) {
        let url = option?[.socketURL]
        self.router = router

        if let url = url {
            self.socketClient = SocketClient.init(url: URL(string: url)!)
        } else {
            self.socketClient = SocketClient.init(url: nil)
        }
    }

    public func start() {
        Observable<Int>.interval(0.2, scheduler: MainScheduler.instance)
            .map { [unowned self] _ in
                self.tree(router: self.router)
            }
            .distinctUntilChanged { a, b in
                NSDictionary(dictionary: a).isEqual(to: b)
            }
            .subscribe(onNext: { [unowned self] in
                self.socketClient.send(tree: $0)
            })
            .disposed(by: disposeBag)

        socketClient.socket.on("take capture rib") { [unowned self] data, _ in
            guard let routerName = data[0] as? String else { return }
            if let data = self.captureView(from: routerName) {
                self.socketClient.socket.emit("capture image", data.base64EncodedString())
            }
        }
    }

    private func tree(router: Routing, appendImage: Bool = false) -> [String: Any] {
        var currentRouter = String(describing: type(of: router))
        if router is ViewableRouting {
            currentRouter += " (View) "
        }
        if router.children.isEmpty {
            return ["name": currentRouter, "children": []]
        } else {
            return ["name": currentRouter, "children": router.children.map { tree(router: $0, appendImage: appendImage) }]
        }
    }

    private func findRouter(target: String, router: Routing) -> Routing? {
        let currentRouter = String(describing: type(of: router))
        if target == currentRouter {
            return router
        } else if !router.children.isEmpty {
            return router.children.compactMap { findRouter(target: target, router: $0) }.first
        } else {
            return nil
        }
    }

    private func captureView(from targetRouter: String) -> Data? {
        guard let router = findRouter(target: targetRouter, router: router) as? ViewableRouting,
            let view = router.viewControllable.uiviewController.view,
            let captureImage = image(with: view) else {
                return nil
        }
        return captureImage.pngData()
    }

    private func image(with view: UIView) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.isOpaque, 0.0)
        defer { UIGraphicsEndImageContext() }
        if let context = UIGraphicsGetCurrentContext() {
            view.layer.render(in: context)
            let image = UIGraphicsGetImageFromCurrentImageContext()
            return image
        }
        return nil
    }
}

final class SocketClient {

    let socket: SocketIOClient
    private let manager: SocketManager
    private var isConnected: Bool = false

    init(url: URL?) {
        self.manager = SocketManager(socketURL: url ?? URL(string: "http://localhost:8000")!,
                                     config: [.log(false), .compress])
        self.socket = manager.socket(forNamespace: "/ribs")
        self.socket.on(clientEvent: .connect) {_, _ in
            self.isConnected = true
        }
        self.socket.connect()
    }

    func send(tree: [String: Any]) {
        guard isConnected else {
            return
        }
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: tree)
            let jsonString = String(bytes: jsonData, encoding: .utf8)!
            socket.emit("tree_update", jsonString)
        } catch {
            print(error)
        }
    }
}
